#!/bin/bash
#
# Запуск тестов пакета SVGRenderKit с принудительным завершением зависшего xcodebuild.
#
# Зачем: после последнего теста `xcodebuild test` нередко не завершается сам (Xcode 26/27),
# хотя итог уже напечатан, и инструменты, которые ждут выхода процесса, висят. Скрипт ждёт
# строку итога, даёт процессу GRACE_SECONDS выйти самому, иначе гасит его и сам разбирает лог.
#
# Использование (из любого каталога):
#   Scripts/run-tests.sh                                            — все тесты
#   Scripts/run-tests.sh -only-testing:SVGRenderKitTests/SVGMemoryManagementTests
#   LOG=/tmp/svg.log DESTINATION='platform=iOS Simulator,name=iPhone 17' Scripts/run-tests.sh
#
# Итог печатается в конце и пишется в "$LOG.verdict"; последняя строка — одно из слов:
# PASSED, WARNINGS, FAILED, BUILD-FAILED, CRASHED, HUNG, NO-RESULT. Код возврата: 0 только у PASSED.
#
# HUNG — лог не растёт дольше STALL_SECONDS (по умолчанию 180): зависший тест не держит
# прогон вечно; в вердикте указан тест, на котором остановились.
# CLEAN=1 — чистая пересборка (тогда компилятор предупреждает обо всех файлах пакета).

set -u
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="${LOG:-$(mktemp -t svgrenderkit-tests).log}"
SCHEME="${SCHEME:-SVGRenderKit-Package}"
DESTINATION="${DESTINATION:-platform=iOS Simulator,name=iPhone 17}"
GRACE_SECONDS="${GRACE_SECONDS:-15}"
STALL_SECONDS="${STALL_SECONDS:-180}"

rm -f "$LOG" "$LOG.verdict"
cd "$ROOT_DIR" || exit 1

if [ "${CLEAN:-0}" = 1 ]; then
  xcodebuild -scheme "$SCHEME" -destination "$DESTINATION" clean > /dev/null 2>&1
fi

xcodebuild -scheme "$SCHEME" -destination "$DESTINATION" "$@" test > "$LOG" 2>&1 &
PID=$!
DONE='\*\* TEST (SUCCEEDED|FAILED) \*\*|\*\* BUILD FAILED \*\*|Test Suite .(All tests|Selected tests). (passed|failed)'

LAST_SIZE=0
LAST_GROWTH=$(date +%s)
STALLED=0

while kill -0 $PID 2>/dev/null; do
  SIZE=$(stat -f %z "$LOG" 2>/dev/null || echo 0)
  NOW=$(date +%s)
  if [ "$SIZE" != "$LAST_SIZE" ]; then
    LAST_SIZE=$SIZE
    LAST_GROWTH=$NOW
  elif [ $((NOW - LAST_GROWTH)) -ge "$STALL_SECONDS" ] && ! grep -qE "$DONE" "$LOG"; then
    kill $PID
    STALLED=1
    break
  fi
  if grep -qE "$DONE" "$LOG"; then
    for _ in $(seq $GRACE_SECONDS); do kill -0 $PID 2>/dev/null || break; sleep 1; done
    if kill -0 $PID 2>/dev/null; then
      kill $PID
      echo "xcodebuild завис после итога — завершён принудительно" >> "$LOG.verdict"
    fi
    break
  fi
  sleep 2
done
wait $PID 2>/dev/null

# Предупреждения: уникальные строки `файл:строка:столбец: warning:` из файлов самого пакета.
# Предупреждения зависимостей (.build/checkouts) и служебные без пути не считаются.
COMPILER_WARNINGS=$(grep -E "^$ROOT_DIR/(Sources|Tests|Example)/.*\.swift:[0-9]+:[0-9]+: warning:" "$LOG" | sort -u)
COMPILER_COUNT=$(printf '%s' "$COMPILER_WARNINGS" | grep -c . || true)

{
  echo "--- вердикт ($LOG) ---"
  if [ "$STALLED" = 1 ]; then
    grep -E "Test Case .* started" "$LOG" | tail -1 | sed "s/^[[:space:]]*/завис на: /"
  fi
  # Каждый тестовый бандл печатает свой итог; складываем по одному на бандл.
  awk '/Test Suite .*\.xctest. (passed|failed)/ { name = $3; want = 1; next }
       want && /Executed [0-9]+ tests/ && !(name in seen) { seen[name] = 1; n += $2; f += $5; want = 0 }
       END { if (length(seen)) printf "Executed %d tests, with %d failures, бандлов: %d\n", n, f, length(seen) }' "$LOG"
  grep -c "Restarting after unexpected exit" "$LOG" | sed 's/^/перезапусков после падения: /'
  grep -E "^\s+[A-Za-z]+Tests\.test[A-Za-z0-9_]*\(\)" "$LOG" | sort -u | sed 's/^[[:space:]]*/упавший: /'
  grep -E "^/.*\.swift:[0-9]+(:[0-9]+)?: error:" "$LOG" | sort -u | head -10
  echo "предупреждений компилятора: $COMPILER_COUNT"
  if [ "$COMPILER_COUNT" -gt 0 ]; then
    printf '%s\n' "$COMPILER_WARNINGS" | sed "s#^$ROOT_DIR/##" | head -20 | sed 's/^/  /'
  fi
  if [ "$STALLED" = 1 ]; then echo "HUNG"
  elif ! grep -q "Test Suite" "$LOG" && grep -qE "\*\* BUILD FAILED \*\*|\.swift:[0-9]+:[0-9]+: error:" "$LOG"; then echo "BUILD-FAILED"
  elif grep -q "Restarting after unexpected exit" "$LOG"; then echo "CRASHED"
  # Несколько бандлов печатают по своему «All tests»: упавший хоть где-то — это FAILED.
  elif grep -qE "Test Suite .(All tests|Selected tests). failed|: error: -\[" "$LOG"; then echo "FAILED"
  elif grep -qE "Test Suite .(All tests|Selected tests). passed" "$LOG"; then
    if [ "$COMPILER_COUNT" -gt 0 ]; then echo "WARNINGS"; else echo "PASSED"; fi
  else echo "NO-RESULT"; fi
} | tee -a "$LOG.verdict"

[ "$(tail -1 "$LOG.verdict")" = "PASSED" ]
