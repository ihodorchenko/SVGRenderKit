#!/usr/bin/env python3
"""Rewrites a CSS-animated SVG into the SVGRenderKit SMIL profile (build-time step).

Usage:
    css-to-smil.py INPUT.svg [--output OUTPUT.svg] [--samples-per-second N] [--strict] [--quiet]
    css-to-smil.py --self-test

Why a build-time converter: the runtime parser animates only the SMIL subset
(`<animate>`, `<animateTransform>`, `<set>` — see CONFORMANCE.md and
`Sources/SVGRenderKit/Tags/SVGAnimation.swift`). Designer tools export CSS animations instead
(`<style>` with `@keyframes` plus `animation` shorthands). Converting the asset once keeps the
runtime profile small, the app's parse cost unchanged and the animation semantics on the
already-tested Core Animation path. The runtime CSS engine is a separate, much bigger work item
(`docs/css-animations-plan.md`); this script covers the common export class in the meantime.

What is converted:
- simple/compound/descendant CSS selectors (tag, `.class`, `#id`, `*`) from every `<style>` block;
  the matched declarations are inlined into the element so the runtime keeps its current cascade
  (the runtime has no document-wide stylesheet registry);
- `animation` shorthand and the `animation-*` longhands (comma lists, any value order);
- `@keyframes` with `%`, `from`/`to` and comma-separated offsets; missing `0%`/`100%` keyframes get
  the element's base value, exactly as CSS requires;
- the timing function (`linear`, `ease*`, `cubic-bezier()`, `steps()`) is *baked into sampled
  keyframes*: the SMIL profile has no `keySplines`/`calcMode`, and Core Animation cannot express
  an overshooting bezier with `CAMediaTimingFunction` anyway (`cubic-bezier(1,-.43,0,1.29)` is a
  real designer value);
- `animation-direction` (`normal`/`reverse`/`alternate`/`alternate-reverse`), negative and positive
  `animation-delay`, `animation-iteration-count` and `animation-fill-mode` are folded into one SMIL
  animation (a full `alternate` cycle repeats with `repeatCount="indefinite"`; finite counts are
  expanded into a single sampled duration);
- animated properties: `transform`, `opacity`, `fill` and `stroke`. Transform lists are flattened to
  the 2D plane (`translate3d`/`scale3d`, `rotateZ`/`rotate3d` about z, `skewX`/`skewY`); a list of
  same-kind functions collapses into one (`translateX + translateY` → `translate`), and a mixed list
  (`translate(...) scale(...)`) becomes a chain of wrapper `<g>` layers with one `<animateTransform>`
  per function, because the runtime animates one transform function per layer. `transform-origin` is
  not modelled: SVG's initial origin is `0 0` and a pure translation is origin-independent,
  everything else is reported;
- properties outside the SMIL profile (`stroke-dashoffset`, `stroke-width`, …) and `@media`/`@supports`/
  `@import`/CSS transitions cannot be converted: they are dropped with a warning (the runtime animates
  only `transform`/`opacity`/`fill`/`stroke`, and has no media queries — a dark variant belongs to the
  app);
Output: a document with the same geometry, CSS inlined as presentation/inline style, the consumed
`<style>` blocks and `animation*` declarations removed, and one `<animate>`/`<animateTransform>` per
animated property (a mixed transform list gains one nested `<g>` wrapper per function). Animated
documents stay out of the pixel-corpus
(`CorpusLoader.hasRenderingAnimation` detects `<animate`/`@keyframes`), so a converted asset is
safe to bundle next to its original for the Example gallery.

Exit codes: 0 — converted (warnings are degradation, see the runtime policy); 1 — usage/parse error
or, with `--strict`, any warning; 2 — nothing to convert (no `<style>` and no `animation`), no output
written unless `--output` is given.
"""
import argparse
import math
import re
import sys
import xml.etree.ElementTree as ET
from collections import OrderedDict

SVG_NS = "http://www.w3.org/2000/svg"
XLINK_NS = "http://www.w3.org/1999/xlink"

SUPPORTED_ANIMATED_PROPS = ("transform", "opacity", "fill", "stroke")
ANIMATION_LONGHANDS = (
    "animation-name", "animation-duration", "animation-timing-function", "animation-delay",
    "animation-iteration-count", "animation-direction", "animation-fill-mode",
    "animation-play-state",
)
ANIMATED_TAGS = frozenset(
    {"g", "path", "rect", "circle", "ellipse", "line", "polyline", "polygon", "text", "tspan"})
CONTAINER_ONLY_TAGS = frozenset({"defs", "symbol", "mask", "pattern", "clipPath", "marker", "svg"})

MAX_SAMPLES = 4000          # per property animation; bounds the output size of a hostile document
MAX_BAKED_ITERATIONS = 20.0  # above this finite count the whole cycles go to `repeatCount`
TIME_RE = re.compile(r"^-?(?:\d+\.?\d*|\.\d+)(?:s|ms)$")
NUMBER_RE = re.compile(r"^-?(?:\d+\.?\d*|\.\d+)$")
IDENT_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_-]*$")

EASING_KEYWORDS = {
    "linear": (0.0, 0.0, 1.0, 1.0),
    "ease": (0.25, 0.1, 0.25, 1.0),
    "ease-in": (0.42, 0.0, 1.0, 1.0),
    "ease-out": (0.0, 0.0, 0.58, 1.0),
    "ease-in-out": (0.42, 0.0, 0.58, 1.0),
}

# Only the colors that show up in designer exports; anything else is reported and skipped.
NAMED_COLORS = {
    "black": (0, 0, 0), "white": (255, 255, 255), "red": (255, 0, 0), "lime": (0, 255, 0),
    "blue": (0, 0, 255), "yellow": (255, 255, 0), "cyan": (0, 255, 255),
    "aqua": (0, 255, 255), "magenta": (255, 0, 255), "fuchsia": (255, 0, 255),
    "gray": (128, 128, 128), "grey": (128, 128, 128), "silver": (192, 192, 192),
    "maroon": (128, 0, 0), "olive": (128, 128, 0), "green": (0, 128, 0),
    "purple": (128, 0, 128), "teal": (0, 128, 128), "navy": (0, 0, 128),
    "orange": (255, 165, 0), "brown": (165, 42, 42), "pink": (255, 192, 203),
    "gold": (255, 215, 0), "violet": (238, 130, 238), "indigo": (75, 0, 130),
    "coral": (255, 127, 80), "salmon": (250, 128, 114), "crimson": (220, 20, 60),
    "khaki": (240, 230, 140), "beige": (245, 245, 220), "ivory": (255, 255, 240),
    "lavender": (230, 230, 250), "plum": (221, 160, 221), "orchid": (218, 112, 214),
    "tan": (210, 180, 140), "chocolate": (210, 105, 30), "turquoise": (64, 224, 208),
}


class Warnings:
    """Collects degradation messages so the whole file can be converted before failing `--strict`."""

    def __init__(self):
        self.messages = []

    def warn(self, message):
        self.messages.append(message)

    def __len__(self):
        return len(self.messages)


def local_name(tag):
    """The tag without its `{namespace}` prefix (ET keeps namespaces by default)."""
    return tag.rsplit("}", 1)[-1] if isinstance(tag, str) and tag.startswith("{") else tag


def namespace_of(tag):
    return tag[1:tag.index("}")] if isinstance(tag, str) and tag.startswith("{") else ""


# --------------------------------------------------------------------------------------------
# CSS text parsing
# --------------------------------------------------------------------------------------------

def strip_css_comments(text):
    out, i, n = [], 0, len(text)
    while i < n:
        if text.startswith("/*", i):
            close = text.find("*/", i + 2)
            if close < 0:
                break
            i = close + 2
        else:
            out.append(text[i])
            i += 1
    return "".join(out)


def split_top_level(text, separator):
    """Splits on `separator` outside parentheses, brackets, quotes and braces."""
    parts, current = [], []
    depth, quote = 0, None
    for ch in text:
        if quote:
            current.append(ch)
            if ch == quote:
                quote = None
        elif ch in "\"'":
            quote = ch
            current.append(ch)
        elif ch in "([{":
            depth += 1
            current.append(ch)
        elif ch in ")]}":
            depth = max(0, depth - 1)
            current.append(ch)
        elif ch == separator and depth == 0:
            parts.append("".join(current))
            current = []
        else:
            current.append(ch)
    parts.append("".join(current))
    return parts


def parse_declarations(text):
    """`(property, value, important)` triples in source order; `:` inside a value is kept."""
    declarations = []
    for chunk in split_top_level(text, ";"):
        chunk = chunk.strip()
        if not chunk:
            continue
        prop, sep, value = chunk.partition(":")
        if not sep:
            continue
        prop = prop.strip().lower()
        if not prop:
            continue
        value = value.strip()
        important = False
        if value.lower().endswith("!important"):
            important = True
            value = value[: -len("!important")].strip()
        declarations.append((prop, value, important))
    return declarations


def match_brace(text, open_index):
    """Index of the `}` matching `text[open_index]`, skipping strings and nested braces."""
    depth, quote = 0, None
    i = open_index
    while i < len(text):
        ch = text[i]
        if quote:
            if ch == quote:
                quote = None
        elif ch in "\"'":
            quote = ch
        elif ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return len(text) - 1


class Compound:
    """One compound selector: optional tag, classes and id (no combinators)."""

    __slots__ = ("tag", "classes", "id")

    def __init__(self, tag=None, classes=(), id=None):
        self.tag = tag
        self.classes = tuple(classes)
        self.id = id

    def specificity(self):
        return (1 if self.id else 0, len(self.classes), 1 if self.tag else 0)


class Rule:
    __slots__ = ("chain", "declarations", "order")

    def __init__(self, chain, declarations, order):
        self.chain = chain
        self.declarations = declarations
        self.order = order

    def specificity(self):
        ids = classes = tags = 0
        for compound in self.chain:
            i, c, t = compound.specificity()
            ids += i
            classes += c
            tags += t
        return (ids, classes, tags)


def parse_compound(text):
    """`path`, `.a`, `#u`, `path.a#u`, `*` — `None` for anything the runtime profile cannot match."""
    text = text.strip()
    if not text:
        return None
    tag, classes, id_ = None, [], None
    i, n = 0, len(text)
    if text[i] == "*":
        i += 1
    else:
        start = i
        while i < n and (text[i].isalnum() or text[i] in "-_"):
            i += 1
        if i > start:
            tag = text[start:i]
            if not (tag[0].isalpha() or tag[0] == "_"):
                return None
    while i < n:
        marker = text[i]
        if marker not in ".#":
            return None
        i += 1
        start = i
        while i < n and (text[i].isalnum() or text[i] in "-_"):
            i += 1
        name = text[start:i]
        if not name:
            return None
        if marker == ".":
            classes.append(name)
        else:
            if id_ is not None:
                return None
            id_ = name
    return Compound(tag, classes, id_)


def parse_selector(text):
    """Ancestor-to-leaf compound chain, or `None` for a selector the converter drops."""
    text = text.strip()
    if not text:
        return None
    if any(ch in text for ch in ">+~:[]()\"'"):
        return None
    chain = []
    for token in text.split():
        compound = parse_compound(token)
        if compound is None:
            return None
        chain.append(compound)
    return chain or None


def parse_offsets(prelude):
    """Keyframe offsets: `0%`, `33.3%`, `from`, `to`, comma lists."""
    offsets = []
    for token in split_top_level(prelude, ","):
        token = token.strip().lower()
        if token == "from":
            offsets.append(0.0)
        elif token == "to":
            offsets.append(1.0)
        elif token.endswith("%"):
            try:
                offsets.append(float(token[:-1]) / 100.0)
            except ValueError:
                return []
        else:
            return []
    return offsets


def parse_keyframes_body(body, warnings, name):
    frames = []
    i = 0
    while True:
        open_index = body.find("{", i)
        if open_index < 0:
            break
        prelude = body[i:open_index].strip()
        close_index = match_brace(body, open_index)
        offsets = parse_offsets(prelude)
        if not offsets:
            warnings.warn("@keyframes %s: unsupported keyframe selector '%s' skipped" % (name, prelude))
        else:
            declarations = parse_declarations(body[open_index + 1:close_index])
            for offset in offsets:
                frames.append((offset, declarations))
        i = close_index + 1
    frames.sort(key=lambda frame: frame[0])
    deduped = []
    for offset, declarations in frames:
        if deduped and abs(deduped[-1][0] - offset) < 1e-9:
            deduped[-1] = (offset, declarations)
        else:
            deduped.append((offset, declarations))
    return deduped


def parse_stylesheet(text, warnings):
    """Returns `(rules, keyframes)`: matched declarations and `@keyframes` by name."""
    text = strip_css_comments(text)
    rules, keyframes, order = [], {}, 0
    i = 0
    while True:
        open_index = text.find("{", i)
        if open_index < 0:
            break
        prelude = text[i:open_index].strip()
        close_index = match_brace(text, open_index)
        body = text[open_index + 1:close_index]
        if prelude.startswith("@"):
            at_name = prelude[1:].split(None, 1)[0].lower() if len(prelude) > 1 else ""
            if at_name == "keyframes" or at_name.endswith("keyframes"):
                name = prelude[len("@" + at_name):].strip()
                if name:
                    keyframes[name] = parse_keyframes_body(body, warnings, name)
            elif ";" in prelude:
                # A statement at-rule shares the upcoming `{` with the rule that follows it.
                tail = prelude.rsplit(";", 1)[1].strip()
                warnings.warn("skipped at-rule '@%s'" % at_name)
                if tail:
                    chains = [parse_selector(part) for part in split_top_level(tail, ",")]
                    kept = [chain for chain in chains if chain]
                    if len(kept) != len(chains):
                        warnings.warn("selector '%s': unsupported combinator/pseudo-class skipped" % tail)
                    if kept:
                        rules.append(Rule(kept[0], parse_declarations(body), order))
                        order += 1
            else:
                warnings.warn("skipped at-rule '@%s' (media/supports/font-face are out of scope)" % at_name)
        else:
            selectors = split_top_level(prelude, ",")
            chains = [parse_selector(part) for part in selectors]
            kept = [chain for chain in chains if chain]
            if len(kept) != len(chains):
                warnings.warn("rule '%s': unsupported selector skipped" % prelude.strip())
            if kept:
                rules.append(Rule(kept[0], parse_declarations(body), order))
                order += 1
        i = close_index + 1
    return rules, keyframes


# --------------------------------------------------------------------------------------------
# Selector matching and the cascade
# --------------------------------------------------------------------------------------------

def element_classes(element):
    return set((element.get("class") or "").split())


def matches_compound(element, compound):
    if compound.tag is not None and local_name(element.tag) != compound.tag:
        return False
    if compound.id is not None and element.get("id") != compound.id:
        return False
    if compound.classes:
        classes = element_classes(element)
        if not set(compound.classes).issubset(classes):
            return False
    return True


def matches_selector(element, chain, parents):
    if not matches_compound(element, chain[-1]):
        return False
    remaining = len(chain) - 2
    ancestor = parents.get(element)
    while remaining >= 0:
        if ancestor is None:
            return False
        if matches_compound(ancestor, chain[remaining]):
            remaining -= 1
        ancestor = parents.get(ancestor)
    return True


def parse_inline_style(element):
    text = element.get("style")
    return parse_declarations(text) if text else []


def cascade(element, rules, parents):
    """Cascaded declarations in application order: normal first, `!important` last."""
    entries = []
    for rule in rules:
        if not matches_selector(element, rule.chain, parents):
            continue
        specificity = rule.specificity()
        for index, (prop, value, important) in enumerate(rule.declarations):
            entries.append((1 if important else 0, 0, specificity, rule.order, index, prop, value))
    for index, (prop, value, important) in enumerate(parse_inline_style(element)):
        entries.append((1 if important else 0, 1, (0, 0, 0), 0, index, prop, value))
    entries.sort(key=lambda entry: entry[:5])
    return [(prop, value) for _, _, _, _, _, prop, value in entries]


def apply_cascade(element, rules, parents, warnings):
    """Splits the cascaded declarations into `(style_props, animation_declarations)`."""
    style_props = OrderedDict()
    animation_declarations = []
    for prop, value in cascade(element, rules, parents):
        if prop == "animation" or prop in ANIMATION_LONGHANDS:
            animation_declarations.append((prop, value))
        elif prop in ("transform-origin", "transform-box"):
            warnings.warn("%s: '%s' is not converted (the SVG initial 0 0 / view-box is assumed; "
                          "pure translations are unaffected)" % (describe(element), prop))
        else:
            style_props[prop] = value
    return style_props, animation_declarations


# --------------------------------------------------------------------------------------------
# Animations: shorthand/longhands -> per-property sampling
# --------------------------------------------------------------------------------------------

def parse_time(value, warnings, what):
    value = value.strip()
    if value.endswith("ms"):
        try:
            return float(value[:-2]) / 1000.0
        except ValueError:
            warnings.warn("%s: bad time '%s'" % (what, value))
            return None
    if value.endswith("s"):
        try:
            return float(value[:-1])
        except ValueError:
            warnings.warn("%s: bad time '%s'" % (what, value))
            return None
    warnings.warn("%s: time without a unit '%s' (CSS requires s or ms)" % (what, value))
    return None


class Easing:
    """A CSS timing function sampled by the caller (bezier control points or a step function)."""

    def __init__(self, kind, points=None, steps=None):
        self.kind = kind          # "bezier" | "steps"
        self.points = points      # (x1, y1, x2, y2)
        self.steps = steps        # (count, position)

    def __call__(self, x):
        if self.kind == "bezier":
            return solve_bezier(self.points, x)
        return solve_steps(self.steps, x)


def solve_bezier(points, x):
    x1, y1, x2, y2 = points
    if x <= 0:
        return 0.0
    if x >= 1:
        return 1.0
    low, high = 0.0, 1.0
    t = x
    for _ in range(60):
        bx = 3 * (1 - t) ** 2 * t * x1 + 3 * (1 - t) * t ** 2 * x2 + t ** 3
        if bx < x:
            low = t
        else:
            high = t
        t = (low + high) / 2
    return 3 * (1 - t) ** 2 * t * y1 + 3 * (1 - t) * t ** 2 * y2 + t ** 3


def solve_steps(steps, x):
    count, position = steps
    x = min(max(x, 0.0), 1.0)
    if position == "start":      # jump-start
        return min(1.0, math.ceil(x * count) / count) if count else x
    if position == "none":       # jump-none
        return min(1.0, math.floor(x * count) / (count - 1)) if count > 1 else 0.0
    if position == "both":       # jump-both
        return min(1.0, (math.floor(x * count) + 1) / (count + 1))
    return min(1.0, math.floor(x * count) / count)  # jump-end / end


def parse_timing_function(value, warnings, what):
    value = value.strip().lower()
    if value in EASING_KEYWORDS:
        return Easing("bezier", EASING_KEYWORDS[value])
    if value.startswith("cubic-bezier("):
        body = value[len("cubic-bezier("):-1]
        numbers = [part.strip() for part in body.split(",")]
        if len(numbers) != 4:
            warnings.warn("%s: bad cubic-bezier '%s'" % (what, value))
            return None
        try:
            x1, y1, x2, y2 = (float(number) for number in numbers)
        except ValueError:
            warnings.warn("%s: bad cubic-bezier '%s'" % (what, value))
            return None
        if not (0 <= x1 <= 1 and 0 <= x2 <= 1):
            warnings.warn("%s: cubic-bezier x control points outside [0,1] in '%s'" % (what, value))
            return None
        return Easing("bezier", (x1, y1, x2, y2))
    if value.startswith("steps("):
        body = value[len("steps("):-1]
        pieces = [piece.strip() for piece in body.split(",")]
        try:
            count = int(pieces[0])
        except (ValueError, IndexError):
            warnings.warn("%s: bad steps() '%s'" % (what, value))
            return None
        if count <= 0:
            warnings.warn("%s: steps() needs a positive count in '%s'" % (what, value))
            return None
        position = pieces[1].lower() if len(pieces) > 1 else "end"
        if position == "jump-start":
            position = "start"
        elif position == "jump-end":
            position = "end"
        elif position == "jump-none":
            position = "none"
        elif position == "jump-both":
            position = "both"
        if position not in ("start", "end", "none", "both"):
            warnings.warn("%s: bad steps() position '%s'" % (what, value))
            return None
        return Easing("steps", steps=(count, position))
    if value.startswith("linear("):
        warnings.warn("%s: linear() easing is not converted (it needs the explicit stop list)" % what)
        return None
    warnings.warn("%s: unsupported timing function '%s'" % (what, value))
    return None


def split_animation_items(value):
    return [item.strip() for item in split_top_level(value, ",") if item.strip()]


def parse_shorthand_item(item, warnings, what):
    fields = {
        "name": None, "duration": 0.0, "timing": "ease", "delay": 0.0,
        "iterations": 1.0, "direction": "normal", "fill": "none", "play": "running",
    }
    tokens = []
    depth, current = 0, []
    for ch in item:
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth = max(0, depth - 1)
        if ch.isspace() and depth == 0:
            if current:
                tokens.append("".join(current))
                current = []
        else:
            current.append(ch)
    if current:
        tokens.append("".join(current))

    time_seen = False
    for token in tokens:
        lower = token.lower()
        if TIME_RE.match(lower):
            seconds = parse_time(lower, warnings, what)
            if seconds is None:
                continue
            if not time_seen:
                fields["duration"] = seconds
                time_seen = True
            else:
                fields["delay"] = seconds
        elif lower in EASING_KEYWORDS or lower.startswith(("cubic-bezier(", "steps(", "linear(")):
            fields["timing"] = lower
        elif lower == "infinite":
            fields["iterations"] = math.inf
        elif NUMBER_RE.match(lower):
            fields["iterations"] = float(lower)
        elif lower in ("normal", "reverse", "alternate", "alternate-reverse"):
            fields["direction"] = lower
        elif lower in ("forwards", "backwards", "both"):
            fields["fill"] = lower
        elif lower in ("running", "paused"):
            fields["play"] = lower
        elif lower == "none":
            if fields["name"] is None and len(tokens) == 1:
                fields["name"] = "none"
            else:
                fields["fill"] = "none"
        elif IDENT_RE.match(token):
            if fields["name"] is None:
                fields["name"] = token
            else:
                warnings.warn("%s: unexpected token '%s' in the animation shorthand" % (what, token))
        else:
            warnings.warn("%s: unexpected token '%s' in the animation shorthand" % (what, token))
    return fields


def animation_items(declarations, warnings, what):
    """Expands the cascaded `animation`/`animation-*` declarations into one record per animation."""
    items = []
    longhands = {}
    for prop, value in declarations:
        if prop == "animation":
            items = [parse_shorthand_item(item, warnings, what) for item in split_animation_items(value)]
            longhands = {}
        else:
            key = prop[len("animation-"):]
            if key == "name":
                longhands["name"] = [part.strip() for part in split_top_level(value, ",") if part.strip()]
            elif key in ("duration", "delay"):
                parsed = [parse_time(part.strip(), warnings, what) for part in split_top_level(value, ",")]
                longhands[key] = [0.0 if parsed_time is None else parsed_time
                                  for parsed_time in parsed]
            elif key == "timing-function":
                longhands["timing"] = [part.strip().lower() for part in split_top_level(value, ",")]
            elif key == "iteration-count":
                counts = []
                for part in split_top_level(value, ","):
                    part = part.strip().lower()
                    if part == "infinite":
                        counts.append(math.inf)
                    elif NUMBER_RE.match(part):
                        counts.append(float(part))
                    else:
                        warnings.warn("%s: bad animation-iteration-count '%s'" % (what, part))
                        counts.append(1.0)
                longhands["iterations"] = counts
            elif key == "direction":
                longhands["direction"] = [part.strip().lower() for part in split_top_level(value, ",")]
            elif key == "fill-mode":
                longhands["fill"] = [part.strip().lower() for part in split_top_level(value, ",")]
            elif key == "play-state":
                longhands["play"] = [part.strip().lower() for part in split_top_level(value, ",")]
    if not items and "name" not in longhands:
        return []
    count = max(len(items), len(longhands.get("name", [])) or 1)

    def cycle(values):
        return [values[index % len(values)] for index in range(count)] if values else None

    records = []
    for index in range(count):
        record = dict(items[index % len(items)]) if items else {
            "name": None, "duration": 0.0, "timing": "ease", "delay": 0.0,
            "iterations": 1.0, "direction": "normal", "fill": "none", "play": "running",
        }
        overrides = {
            "name": cycle(longhands.get("name")),
            "duration": cycle(longhands.get("duration")),
            "timing": cycle(longhands.get("timing")),
            "delay": cycle(longhands.get("delay")),
            "iterations": cycle(longhands.get("iterations")),
            "direction": cycle(longhands.get("direction")),
            "fill": cycle(longhands.get("fill")),
            "play": cycle(longhands.get("play")),
        }
        for key, values in overrides.items():
            if values is not None:
                record[key] = values[index]
        for key in ("duration", "delay", "iterations"):
            if record[key] is None:
                record[key] = 0.0 if key != "iterations" else 1.0
        records.append(record)
    return records


# --------------------------------------------------------------------------------------------
# Values: transforms, numbers, colors
# --------------------------------------------------------------------------------------------

class UnsupportedValue(Exception):
    pass


def parse_length(token, warnings=None, what=""):
    token = token.strip().lower()
    match = re.match(r"^(-?(?:\d+\.?\d*|\.\d+))(px)?$", token)
    if match:
        return float(match.group(1))
    if warnings:
        warnings.warn("%s: length '%s' is not a px/user-unit value; the animation is skipped"
                      % (what, token))
    raise UnsupportedValue(token)


def parse_angle(token, warnings=None, what=""):
    token = token.strip().lower()
    match = re.match(r"^(-?(?:\d+\.?\d*|\.\d+))(deg|rad|grad|turn)?$", token)
    if not match:
        if warnings:
            warnings.warn("%s: angle '%s' is not supported" % (what, token))
        raise UnsupportedValue(token)
    value = float(match.group(1))
    unit = match.group(2) or "deg"
    if unit == "rad":
        return value * 180.0 / math.pi
    if unit == "grad":
        return value * 0.9
    if unit == "turn":
        return value * 360.0
    return value


def parse_color(token):
    """`(r, g, b, a)` in 0…1 or `None`. Mirrors the color syntaxes the runtime parses."""
    token = token.strip().lower()
    if token == "transparent":
        return (0.0, 0.0, 0.0, 0.0)
    if token in NAMED_COLORS:
        red, green, blue = NAMED_COLORS[token]
        return (red / 255.0, green / 255.0, blue / 255.0, 1.0)
    if token.startswith("#"):
        hex_text = token[1:]
        if len(hex_text) in (3, 4):
            channels = [int(ch * 2, 16) / 255.0 for ch in hex_text]
        elif len(hex_text) in (6, 8):
            channels = [int(hex_text[index:index + 2], 16) / 255.0
                        for index in range(0, len(hex_text), 2)]
        else:
            return None
        if len(channels) == 3:
            channels.append(1.0)
        return tuple(channels)
    function = re.match(r"^(rgba?|hsla?)\((.*)\)$", token)
    if not function:
        return None
    name, body = function.group(1), function.group(2)
    if name.startswith("hsl"):
        return None  # rare in exports; the runtime supports it but the converter does not sample it
    body = body.replace("/", " ")
    pieces = [piece for piece in re.split(r"[\s,]+", body.strip()) if piece]
    if len(pieces) < 3:
        return None
    values = []
    for piece in pieces[:3]:
        try:
            values.append(float(piece[:-1]) / 100.0 if piece.endswith("%") else float(piece) / 255.0)
        except ValueError:
            return None
    alpha = 1.0
    if len(pieces) > 3:
        try:
            alpha = float(pieces[3][:-1]) / 100.0 if pieces[3].endswith("%") else float(pieces[3])
        except ValueError:
            return None
    return (values[0], values[1], values[2], alpha)


def format_number(value):
    if abs(value) < 5e-7:
        return "0"
    text = ("%.6f" % value).rstrip("0").rstrip(".")
    return text or "0"


def format_seconds(value):
    return format_number(value) + "s"


def format_color(color):
    red, green, blue, alpha = color
    red, green, blue = (int(round(channel * 255)) for channel in (red, green, blue))
    if alpha >= 0.999:
        return "#%02x%02x%02x" % (red, green, blue)
    return "rgba(%d, %d, %d, %s)" % (red, green, blue, format_number(alpha))


def clamp(value, low=0.0, high=1.0):
    return max(low, min(high, value))


def parse_transform_functions(text, css):
    """A list of `(kind, params)` for `translate`/`scale`/`rotate`, or `raise UnsupportedValue`."""
    text = (text or "").strip()
    if not text or text.lower() == "none":
        return []
    if css:
        # CSS allows whitespace between arguments; the SVG attribute uses commas. Normalize to the
        # function syntax both grammars share.
        text = re.sub(r"\s+", " ", text)
    functions = []
    i, n = 0, len(text)
    while i < n:
        while i < n and text[i] in " ,\t\n\r":
            i += 1
        if i >= n:
            break
        match = re.match(r"([A-Za-z][A-Za-z0-9]*)\s*\(", text[i:])
        if not match:
            raise UnsupportedValue(text)
        name = match.group(1).lower()
        start = i + match.end()
        depth, j = 1, start
        while j < n and depth:
            if text[j] == "(":
                depth += 1
            elif text[j] == ")":
                depth -= 1
            j += 1
        if depth:
            raise UnsupportedValue(text)
        arguments = [part.strip() for part in re.split(r"[,\s]+", text[start:j - 1].strip()) if part]
        i = j
        functions.append(normalize_transform_function(name, arguments, css))
    return functions


def normalize_transform_function(name, arguments, css):
    """Maps one CSS/SVG transform function to `(kind, params)` in the 2D plane.

    3D aliases are flattened: the runtime is a 2D layer renderer, so `translate3d`/`scale3d` and
    `translateZ`/`scaleZ` keep their x/y part and a rotation about z (`rotateZ`, or `rotate3d`
    with a z axis only) becomes the ordinary `rotate`. Anything else is reported by the caller.
    """
    if name == "translate":
        if not 1 <= len(arguments) <= 2:
            raise UnsupportedValue(name)
        x = parse_length(arguments[0])
        y = parse_length(arguments[1]) if len(arguments) > 1 else 0.0
        return ("translate", (x, y))
    if name == "translatex":
        return ("translate", (parse_length(arguments[0]), 0.0))
    if name == "translatey":
        return ("translate", (0.0, parse_length(arguments[0])))
    if name == "translatez":
        return ("translate", (0.0, 0.0))
    if name == "translate3d":
        if len(arguments) != 3:
            raise UnsupportedValue(name)
        return ("translate", (parse_length(arguments[0]), parse_length(arguments[1])))
    if name == "scale":
        if not 1 <= len(arguments) <= 2:
            raise UnsupportedValue(name)
        x = parse_length(arguments[0])
        y = parse_length(arguments[1]) if len(arguments) > 1 else x
        return ("scale", (x, y))
    if name == "scalex":
        return ("scale", (parse_length(arguments[0]), 1.0))
    if name == "scaley":
        return ("scale", (1.0, parse_length(arguments[0])))
    if name == "scalez":
        return ("scale", (1.0, 1.0))
    if name == "scale3d":
        if len(arguments) != 3:
            raise UnsupportedValue(name)
        return ("scale", (parse_length(arguments[0]), parse_length(arguments[1])))
    if name in ("rotate", "rotatez"):
        if len(arguments) != 1:
            raise UnsupportedValue(name)  # the 3-argument rotation about a point is not a CSS form
        return ("rotate", (parse_angle(arguments[0]),))
    if name == "rotate3d":
        if len(arguments) != 4:
            raise UnsupportedValue(name)
        x, y, z = (float(arguments[0]), float(arguments[1]), float(arguments[2]))
        if abs(x) > 1e-9 or abs(y) > 1e-9 or abs(z) < 1e-9:
            raise UnsupportedValue(name)  # not a 2D rotation
        return ("rotate", (parse_angle(arguments[3]),))
    if name == "skewx":
        return ("skewX", (parse_angle(arguments[0]),))
    if name == "skewy":
        return ("skewY", (parse_angle(arguments[0]),))
    raise UnsupportedValue(name)


# One identity value per transform function kind (padding for implicit `0%`/`100%` keyframes and
# for `transform: none`).
TRANSFORM_IDENTITIES = {
    "translate": (0.0, 0.0),
    "scale": (1.0, 1.0),
    "rotate": (0.0,),
    "skewX": (0.0,),
    "skewY": (0.0,),
}


def identity_transform_like(functions):
    return [(kind, TRANSFORM_IDENTITIES[kind]) for kind, _ in functions]


def merge_same_kind(functions):
    """Collapses a transform list whose functions all share one kind.

    CSS composes `translate(a) translate(b)` as `translate(a + b)`, scales multiply and rotations
    add, so the list fits the runtime's one-function-per-animation model. A list that mixes kinds
    is left alone: it needs nested wrapper layers (`wrap_with_transform_animations`).
    """
    if len(functions) <= 1:
        return functions
    kinds = {kind for kind, _ in functions}
    if len(kinds) != 1:
        return functions
    kind = kinds.pop()
    if kind == "translate":
        params = (sum(parameters[0] for _, parameters in functions),
                  sum(parameters[1] for _, parameters in functions))
    elif kind == "scale":
        sx = sy = 1.0
        for _, (x, y) in functions:
            sx *= x
            sy *= y
        params = (sx, sy)
    elif kind == "rotate":
        params = (sum(parameters[0] for _, parameters in functions),)
    else:
        return functions  # skew lists do not compose additively; keep them as they are
    return [(kind, params)]


def transform_function_value(kind, params):
    """One SMIL `values` entry of a transform function (`0 4`, `1.5 1.5`, `45`)."""
    if kind in ("rotate", "skewX", "skewY"):
        return format_number(params[0])
    return " ".join(format_number(parameter) for parameter in params)


def format_transform_list(functions):
    """A transform list as the SVG `transform` attribute syntax (kit parses chains of these)."""
    pieces = []
    for kind, params in functions:
        if kind in ("translate", "scale"):
            pieces.append("%s(%s, %s)" % (kind, format_number(params[0]), format_number(params[1])))
        elif kind in ("rotate", "skewX", "skewY"):
            pieces.append("%s(%s)" % (kind, format_number(params[0])))
    return " ".join(pieces) if pieces else "none"


def interpolate_transform(start, end, factor):
    """Component-wise interpolation of two equal-shaped transform lists (CSS §Interpolation)."""
    if len(start) != len(end):
        if not start:
            start = identity_transform_like(end)
        elif not end:
            end = identity_transform_like(start)
        else:
            raise UnsupportedValue("transform list length")
    result = []
    for (kind_a, params_a), (kind_b, params_b) in zip(start, end):
        if kind_a != kind_b:
            raise UnsupportedValue("transform function kind")
        params = tuple(a + (b - a) * factor for a, b in zip(params_a, params_b))
        result.append((kind_a, params))
    return result


def interpolate_color(start, end, factor):
    return tuple(clamp(a + (b - a) * factor) for a, b in zip(start, end))


def interpolate_number(start, end, factor):
    return start + (end - start) * factor


# --------------------------------------------------------------------------------------------
# Conversion
# --------------------------------------------------------------------------------------------

def describe(element):
    identity = element.get("id")
    if identity:
        return "<%s id=%s>" % (local_name(element.tag), identity)
    classes = element.get("class")
    if classes:
        return "<%s class=%s>" % (local_name(element.tag), classes)
    return "<%s>" % local_name(element.tag)


def build_base_transform(element, style_props, warnings):
    """The computed `transform` property: the CSS property wins over the attribute it presents."""
    if "transform" in style_props:
        raw = style_props["transform"]
        try:
            functions = merge_same_kind(parse_transform_functions(raw, css=True))
            return raw, functions
        except UnsupportedValue:
            warnings.warn("%s: static CSS transform '%s' is not representable; kept as is"
                          % (describe(element), raw))
            return raw, None
    attribute = element.get("transform")
    if attribute:
        try:
            return attribute, merge_same_kind(parse_transform_functions(attribute, css=False))
        except UnsupportedValue:
            # Only the implicit 0%/100% keyframes would need it; sampling reports that case.
            return attribute, None
    return None, []


def inherited_property(element, prop, parents, style_props):
    """The computed value of an inherited presentation property (`fill`/`stroke`)."""
    current = element
    while current is not None:
        if prop in style_props.get(current, {}):
            return style_props[current][prop]
        attribute = current.get(prop)
        if attribute is not None:
            return attribute
        current = parents.get(current)
    return None


def base_value(element, prop, parents, style_props, base_transforms):
    """The computed value used for implicit `0%`/`100%` keyframes."""
    if prop == "transform":
        raw, functions = base_transforms
        return raw, functions
    if prop == "opacity":
        if prop in style_props.get(element, {}):
            return style_props[element][prop], None
        attribute = element.get("opacity")
        return (attribute, None) if attribute is not None else ("1", None)
    value = inherited_property(element, prop, parents, style_props)
    return (value, None) if value is not None else (None, None)


class PropertyAnimation:
    """One CSS animation split into one SMIL animation per animated property."""

    def __init__(self, css_name, prop, duration, timing, delay, iterations, direction, fill, play):
        self.css_name = css_name
        self.timing = timing
        self.prop = prop
        self.duration = duration
        self.delay = delay
        self.iterations = iterations
        self.direction = direction
        self.fill = fill
        self.play = play


def parse_property_value(prop, raw):
    """Parses one keyframe value into the converter's internal representation."""
    if prop == "transform":
        return parse_transform_functions(raw, css=True)
    if prop == "opacity":
        if not NUMBER_RE.match(raw.strip()):
            raise UnsupportedValue(raw)
        return float(raw.strip())
    color = parse_color(raw)
    if color is None:
        raise UnsupportedValue(raw)
    return color


def interpolate_value(prop, start, end, factor):
    if prop == "transform":
        return interpolate_transform(start, end, factor)
    if prop == "opacity":
        return interpolate_number(start, end, factor)
    return interpolate_color(start, end, factor)


def format_property_value(prop, value):
    if prop == "transform":
        return format_transform_list(value)
    if prop == "opacity":
        return format_number(value)
    return format_color(value)


def sample_frames(prop, frames, base_raw, base_parsed, animation, warnings, samples_per_second,
                  identity_value=None):
    """Uniform samples of one CSS property animation over a single iteration (times 0…1).

    CSS animations are per-property: a keyframe that does not mention the property is ignored for
    it (CSS Animations L1 §keyframes), so the frames are filtered first and only the missing
    endpoints are filled from the element's base value.
    """
    if base_parsed is not None and not base_parsed and identity_value is not None:
        base_parsed = identity_value
        base_raw = format_transform_list(base_parsed)
    processed = []
    for offset, declarations, declarations_by_prop in frames:
        raw = declarations_by_prop.get(prop)
        if raw is None:
            continue  # this keyframe does not animate the property
        try:
            value = parse_property_value(prop, raw)
        except UnsupportedValue:
            warnings.warn("%s: unsupported '%s' value '%s'; the animation is skipped"
                          % (animation.css_name, prop, raw))
            return None
        if prop == "transform":
            if not value and identity_value is not None:
                value = identity_value  # `transform: none` interpolates as the matching identity
            else:
                value = merge_same_kind(value)
            raw = format_transform_list(value)
        timing_text = declarations_by_prop.get("animation-timing-function")
        processed.append((offset, raw, value, timing_text))
    if not processed:
        return None
    # Implicit 0%/100% keyframes from the element's base value (CSS Animations L1 §keyframes).
    if processed[0][0] > 1e-9:
        if base_parsed is None:
            warnings.warn("%s: missing 0%% keyframe and no base value for '%s'"
                          % (animation.css_name, prop))
            return None
        processed.insert(0, (0.0, base_raw, base_parsed, None))
    if processed[-1][0] < 1.0 - 1e-9:
        if base_parsed is None:
            warnings.warn("%s: missing 100%% keyframe and no base value for '%s'"
                          % (animation.css_name, prop))
            return None
        processed.append((1.0, base_raw, base_parsed, None))
    # Validate that adjacent frames are interpolable before sampling.
    for index in range(len(processed) - 1):
        start, end = processed[index][2], processed[index + 1][2]
        if prop == "transform":
            try:
                interpolate_transform(start, end, 0.0)
            except UnsupportedValue:
                warnings.warn("%s: '%s' keyframes are not interpolable (transform functions differ); "
                              "the animation is skipped" % (animation.css_name, prop))
                return None

    sampled = [(0.0, processed[0][2])]
    for index in range(len(processed) - 1):
        offset_a, _, value_a, timing_text = processed[index]
        offset_b, _, value_b, _ = processed[index + 1]
        span = max(offset_b - offset_a, 1e-9)
        easing = parse_timing_function(timing_text, warnings, animation.css_name) \
            if timing_text else parse_timing_function(animation.timing, warnings, animation.css_name)
        if easing is None:
            return None
        points = max(2, int(round(span * animation.duration * samples_per_second)) + 1)
        for step in range(1, points):
            local = step / (points - 1)
            factor = easing(local)
            offset = offset_a + span * local
            sampled.append((offset, interpolate_value(prop, value_a, value_b, factor)))
    # Normalize the times so the first sample is exactly 0 and the last exactly 1.
    span_total = sampled[-1][0] - sampled[0][0]
    if span_total <= 0:
        return None
    return [((offset - sampled[0][0]) / span_total, value) for offset, value in sampled]


def iteration_is_forward(direction, index):
    """CSS direction for iteration `index`: normal/reverse, alternate flips on odd iterations."""
    if direction == "normal":
        return True
    if direction == "reverse":
        return False
    if direction == "alternate":
        return index % 2 == 0
    return index % 2 == 1  # alternate-reverse


def build_timeline(sampled_iteration, direction, iterations):
    """Concatenates the per-iteration samples; returns `(times, values, repeat_count, total_duration)`."""
    cycle_length = 2 if direction in ("alternate", "alternate-reverse") else 1
    if math.isinf(iterations):
        baked_iterations = cycle_length
        repeat_count = "indefinite"
    else:
        if iterations <= 0:
            return None
        if iterations > MAX_BAKED_ITERATIONS:
            full_cycles = int(iterations // cycle_length)
            baked_iterations = cycle_length
            repeat_count = str(full_cycles)
        else:
            baked_iterations = float(iterations)
            repeat_count = None
    times, values = [], []
    for index in range(int(math.ceil(baked_iterations))):
        remaining = baked_iterations - index
        fraction = min(1.0, remaining)
        forward = iteration_is_forward(direction, index)
        source = sampled_iteration if forward \
            else [(1.0 - offset, value) for offset, value in reversed(sampled_iteration)]
        for offset, value in source:
            if offset > fraction + 1e-9:
                continue
            if times and abs(offset + index - times[-1]) < 1e-9:
                continue  # the boundary sample belongs to the previous iteration
            times.append(index + offset)
            values.append(value)
        if fraction < 1.0 and index + 1 >= baked_iterations:
            # Partial last iteration: close it on the exact boundary value.
            last_time = index + fraction
            if abs(times[-1] - last_time) > 1e-9:
                times.append(last_time)
                values.append(values[-1])
    total = baked_iterations
    return ([time / total for time in times], values, repeat_count, total)


def smil_value(prop, value):
    """One SMIL `values` entry for a non-transform property."""
    if prop == "opacity":
        return format_number(value)
    return format_color(value)


def set_animation_attributes(animation, values_text, times, duration, begin, repeat_count):
    animation.set("values", values_text)
    animation.set("keyTimes", ";".join(format_number(time) for time in times))
    animation.set("dur", format_seconds(max(duration, 1e-6)))
    animation.set("begin", format_seconds(begin))
    if repeat_count:
        animation.set("repeatCount", repeat_count)


def resolve_transform_animation(declarations_by_prop, base_functions, warnings, label):
    """The common transform chain of one CSS animation and the value of its implicit keyframes.

    Returns `(shape, base, drop_attribute)`: `shape` is the tuple of function kinds shared by every
    frame (`None` when the animation cannot be expressed), `base` the list used for implicit
    `0%`/`100%` keyframes, and `drop_attribute` whether the element's `transform` attribute has to
    go (a wrapper chain would otherwise compose with it).
    """
    declared = []
    for _, _, merged in declarations_by_prop:
        raw = merged.get("transform")
        if raw is None:
            continue
        try:
            declared.append(merge_same_kind(parse_transform_functions(raw, css=True)))
        except UnsupportedValue as error:
            warnings.warn("%s: unsupported transform value '%s' (%s); the transform part is skipped"
                          % (label, raw, error))
            return None, None, False
    shape = None
    for functions in declared:
        if not functions:
            continue  # `transform: none` is padded with identities once the shape is known
        kinds = tuple(kind for kind, _ in functions)
        if shape is None:
            shape = kinds
        elif kinds != shape:
            warnings.warn("%s: the keyframes use different transform lists (%s vs %s); the transform "
                          "part is skipped" % (label, " ".join(shape), " ".join(kinds)))
            return None, None, False
    if shape is None:
        return None, None, False  # every frame says `transform: none`: nothing moves
    identity = [(kind, TRANSFORM_IDENTITIES[kind]) for kind in shape]
    base = merge_same_kind(base_functions) if base_functions else []
    if not base:
        base = identity
    elif tuple(kind for kind, _ in base) != shape:
        offsets = [offset for offset, _, merged in declarations_by_prop if "transform" in merged]
        covers = bool(offsets) and min(offsets) <= 1e-9 and max(offsets) >= 1.0 - 1e-9
        if not covers:
            warnings.warn("%s: the static transform does not match the animated function list and "
                          "the keyframes do not cover 0%%/100%%; the transform part is skipped"
                          % label)
            return None, None, False
        base = identity  # the animation replaces the attribute for its whole active duration
    return shape, base, len(shape) > 1


def wrap_with_transform_animations(element, parents, shape, values, times, duration, begin,
                                   repeat_count, warnings):
    """Nests one `<g>` per CSS transform function and attaches its SMIL animation.

    The runtime animates one transform function per layer, so a CSS list such as
    `translate(...) scale(...)` becomes a chain of wrapper layers (the first function is the
    outermost composition, matching how CSS applies the list).
    """
    parent = parents.get(element)
    if parent is None:
        warnings.warn("%s: the animated transform cannot be wrapped (the element has no parent); "
                      "skipped" % describe(element))
        return False
    if element.get("transform") is not None:
        # The CSS `transform` property replaces the attribute; keeping it would compose twice.
        del element.attrib["transform"]
        if begin > 0 or repeat_count != "indefinite":
            warnings.warn("%s: the static transform attribute is dropped (the CSS animation replaces "
                          "it); the state outside the animation may differ" % describe(element))
    ns = namespace_of(parent.tag)
    tag = "{%s}g" % ns if ns else "g"
    index = list(parent).index(element)
    parent.remove(element)
    wrappers = []
    outermost = ET.Element(tag)
    parent.insert(index, outermost)
    wrappers.append(outermost)
    for _ in range(len(shape) - 1):
        child = ET.Element(tag)
        wrappers[-1].append(child)
        wrappers.append(child)
    wrappers[-1].append(element)
    for position, kind in enumerate(shape):
        animation = ET.Element("{%s}animateTransform" % ns if ns else "animateTransform")
        animation.set("attributeName", "transform")
        animation.set("type", kind)
        set_animation_attributes(
            animation,
            ";".join(transform_function_value(kind, value[position][1]) for value in values),
            times, duration, begin, repeat_count)
        wrappers[position].append(animation)
    return True


def convert_element_animations(element, animation_records, keyframes, parents, style_props,
                               base_transforms, warnings, samples_per_second):
    """Builds `<animate>`/`<animateTransform>` children for one element; returns their count."""
    tag = local_name(element.tag)
    if tag in CONTAINER_ONLY_TAGS:
        if animation_records:
            warnings.warn("%s: CSS animations on <%s> are not converted (definition content and "
                          "the root viewport are not animation targets)" % (describe(element), tag))
        return 0
    if tag not in ANIMATED_TAGS:
        if animation_records:
            warnings.warn("%s: CSS animations on <%s> are not converted (the runtime animates "
                          "shapes and <g> only)" % (describe(element), tag))
        return 0

    ns = namespace_of(element.tag)
    base_transform_raw, base_transform_functions = base_transforms

    prepared = []
    for record in animation_records:
        css_name = record["name"]
        if css_name in (None, "none"):
            continue
        if record["play"] == "paused":
            warnings.warn("%s: animation '%s' is paused; skipped" % (describe(element), css_name))
            continue
        if css_name not in keyframes:
            warnings.warn("%s: animation '%s' has no @keyframes; skipped" % (describe(element), css_name))
            continue
        if record["duration"] is None or record["duration"] <= 0:
            warnings.warn("%s: animation '%s' has no positive duration; skipped"
                          % (describe(element), css_name))
            continue
        if record["iterations"] is None or record["iterations"] <= 0:
            continue
        if not math.isinf(record["iterations"]) and record["iterations"] > MAX_BAKED_ITERATIONS:
            warnings.warn("%s: animation '%s' repeats %g times; whole cycles are baked and the "
                          "partial remainder is dropped" % (describe(element), css_name,
                                                           record["iterations"]))

        declarations_by_prop = []
        for offset, declarations in keyframes[css_name]:
            merged = OrderedDict()
            for prop, value, _ in declarations:
                merged[prop] = value
            declarations_by_prop.append((offset, declarations, merged))

        animated = [prop for prop in SUPPORTED_ANIMATED_PROPS
                    if any(prop in merged for _, _, merged in declarations_by_prop)]
        unsupported = sorted({prop for _, _, merged in declarations_by_prop for prop in merged
                              if prop not in SUPPORTED_ANIMATED_PROPS
                              and prop != "animation-timing-function"})
        for prop in unsupported:
            warnings.warn("%s: animation '%s' animates '%s', which the SMIL profile cannot express; "
                          "that property is dropped" % (describe(element), css_name, prop))
        if not animated:
            continue

        shape, base_parsed, drop_attribute = None, None, False
        if "transform" in animated:
            shape, base_parsed, drop_attribute = resolve_transform_animation(
                declarations_by_prop, base_transform_functions, warnings, describe(element))
            if shape is None:
                animated = [prop for prop in animated if prop != "transform"]
                if not animated:
                    continue
        prepared.append({
            "record": record,
            "frames": declarations_by_prop,
            "animated": animated,
            "shape": shape,
            "identity": [(kind, TRANSFORM_IDENTITIES[kind]) for kind in shape] if shape else None,
            "base": base_parsed,
            "drop_attribute": drop_attribute,
        })

    if not prepared:
        return 0

    # CSS: when several animations of one element target the same property, the later one wins.
    winners = {}
    for index, preparation in enumerate(prepared):
        for prop in preparation["animated"]:
            winners[prop] = index

    emitted = 0
    for index, preparation in enumerate(prepared):
        record = preparation["record"]
        css_name = record["name"]
        lost = sorted(prop for prop in preparation["animated"] if winners.get(prop) != index)
        if lost:
            warnings.warn("%s: another CSS animation targets %s; the later one wins in the runtime"
                          % (describe(element), ", ".join(lost)))
        animated = [prop for prop in preparation["animated"] if winners.get(prop) == index]
        if not animated:
            continue

        for prop in animated:
            shape = preparation["shape"] if prop == "transform" else None
            identity = preparation["identity"] if prop == "transform" else None
            if prop == "transform":
                base_parsed = preparation["base"]
                base_raw = format_transform_list(base_parsed) if base_parsed is not None else None
            else:
                base_raw, _ = base_value(element, prop, parents, style_props, base_transforms)
                base_parsed = None
                if base_raw is not None:
                    try:
                        base_parsed = parse_property_value(prop, base_raw)
                    except UnsupportedValue:
                        base_parsed = None

            sampled = sample_frames(prop, preparation["frames"], base_raw, base_parsed,
                                    PropertyAnimation(css_name, prop, record["duration"],
                                                      record["timing"], record["delay"],
                                                      record["iterations"], record["direction"],
                                                      record["fill"], record["play"]),
                                    warnings, samples_per_second, identity)
            if sampled is None:
                continue
            timeline = build_timeline(sampled, record["direction"], record["iterations"])
            if timeline is None:
                continue
            times, values, repeat_count, total_iterations = timeline
            total_duration = record["duration"] * total_iterations
            if len(values) > MAX_SAMPLES:
                warnings.warn("%s: animation '%s' needs %d keyframes; the sampling rate is reduced"
                              % (describe(element), css_name, len(values)))
                # Re-sample at a lower rate once; a hostile document cannot grow unbounded.
                scaled_rate = max(2, int(samples_per_second * MAX_SAMPLES / len(values)))
                sampled = sample_frames(prop, preparation["frames"], base_raw, base_parsed,
                                        PropertyAnimation(css_name, prop, record["duration"],
                                                          record["timing"], record["delay"],
                                                          record["iterations"], record["direction"],
                                                          record["fill"], record["play"]),
                                        warnings, scaled_rate, identity)
                if sampled is None:
                    continue
                timeline = build_timeline(sampled, record["direction"], record["iterations"])
                if timeline is None:
                    continue
                times, values, repeat_count, total_iterations = timeline
                total_duration = record["duration"] * total_iterations
            if len(values) < 2 or len(times) != len(values):
                continue
            if prop == "transform" and any(len(value) != len(shape) for value in values):
                warnings.warn("%s: animation '%s' produced a transform list of a different shape; "
                              "skipped" % (describe(element), css_name))
                continue

            # `fill-mode: forwards/both` cannot be expressed: the runtime does not freeze a
            # finished animation. Only worth a warning when the final value differs from the base.
            if not math.isinf(record["iterations"]) and record["fill"] in ("forwards", "both"):
                if prop == "transform":
                    final_base = preparation["base"]
                elif base_raw is not None:
                    try:
                        final_base = parse_property_value(prop, base_raw)
                    except UnsupportedValue:
                        final_base = None
                else:
                    final_base = None
                if not values_equal(prop, values[-1], final_base):
                    warnings.warn("%s: animation '%s' ends off its base value with "
                                  "fill-mode '%s'; the runtime will snap back (no freeze)"
                                  % (describe(element), css_name, record["fill"]))

            begin_seconds = record["delay"]
            if record["delay"] > 0 and record["fill"] in ("backwards", "both") \
                    and not math.isinf(record["iterations"]):
                hold = record["delay"] / (record["delay"] + total_duration)
                times = [0.0, hold] + [hold + (1.0 - hold) * time for time in times]
                values = [values[0], values[0]] + values
                total_duration += record["delay"]
                begin_seconds = 0.0
            elif record["delay"] > 0 and record["fill"] in ("backwards", "both"):
                warnings.warn("%s: animation '%s' has a delay with fill-mode '%s'; the runtime shows "
                              "the base value during the delay" % (describe(element), css_name,
                                                                   record["fill"]))
            if prop == "transform":
                if len(shape) == 1:
                    kind = shape[0]
                    animation = ET.Element("{%s}animateTransform" % ns if ns else "animateTransform")
                    animation.set("attributeName", "transform")
                    animation.set("type", kind)
                    set_animation_attributes(
                        animation,
                        ";".join(transform_function_value(kind, value[0][1]) for value in values),
                        times, total_duration, begin_seconds, repeat_count)
                    element.append(animation)
                elif not wrap_with_transform_animations(element, parents, shape, values, times,
                                                        total_duration, begin_seconds, repeat_count,
                                                        warnings):
                    continue
            else:
                animation = ET.Element("{%s}animate" % ns if ns else "animate")
                animation.set("attributeName", prop)
                set_animation_attributes(animation, ";".join(smil_value(prop, value)
                                                             for value in values),
                                         times, total_duration, begin_seconds, repeat_count)
                element.append(animation)
            emitted += 1
    return emitted


def values_equal(prop, value, base):
    if base is None:
        return True
    if prop == "transform":
        return [kind for kind, _ in value] == [kind for kind, _ in base] and all(
            abs(a - b) < 1e-6 for (_, params_a), (_, params_b) in zip(value, base)
            for a, b in zip(params_a, params_b))
    if prop == "opacity":
        return abs(value - base) < 1e-6
    return all(abs(a - b) < 1e-6 for a, b in zip(value, base))


# --------------------------------------------------------------------------------------------
# Document conversion
# --------------------------------------------------------------------------------------------

def register_namespaces(root):
    namespaces = {namespace_of(element.tag) for element in root.iter() if namespace_of(element.tag)}
    try:
        for element in root.iter():
            for key in element.attrib:
                if key.startswith("{"):
                    namespaces.add(namespace_of(key))
    except Exception:  # pragma: no cover - attribute namespaces are best-effort
        pass
    if SVG_NS in namespaces:
        ET.register_namespace("", SVG_NS)
    for ns in sorted(namespaces):
        if ns in ("", SVG_NS):
            continue
        if ns == XLINK_NS:
            ET.register_namespace("xlink", ns)
        else:
            try:
                ET.register_namespace("ns%d" % (list(namespaces).index(ns)), ns)
            except ValueError:
                pass


def rewrite_style_attribute(element, style_props):
    if not style_props:
        if element.get("style") is not None:
            del element.attrib["style"]
        return
    element.set("style", ";".join("%s:%s" % (prop, value) for prop, value in style_props.items()))


def convert_document(root, warnings, samples_per_second):
    """Converts the document in place; returns `(animated_elements, emitted_animations)`."""
    parents = {child: parent for parent in root.iter() for child in parent}

    style_elements = [element for element in root.iter() if local_name(element.tag) == "style"]
    rules, keyframes = [], {}
    for style_element in style_elements:
        text = "".join(style_element.itertext())
        block_rules, block_keyframes = parse_stylesheet(text, warnings)
        rules.extend(block_rules)
        keyframes.update(block_keyframes)
    # Document order matters: a later rule wins at equal specificity.
    rules.sort(key=lambda rule: rule.order)
    for index, rule in enumerate(rules):
        rule.order = index

    style_props = {}
    animation_declarations = {}
    for element in root.iter():
        style_props[element] = OrderedDict()
        animation_declarations[element] = []
    for element in root.iter():
        element_style, element_animations = apply_cascade(element, rules, parents, warnings)
        style_props[element] = element_style
        animation_declarations[element] = element_animations

    base_transforms = {}
    for element in root.iter():
        base_transforms[element] = build_base_transform(element, style_props[element], warnings)

    animated_elements = 0
    emitted_animations = 0
    for element in list(root.iter()):
        if local_name(element.tag) in ("style",):
            continue
        # The CSS `transform` property replaces the `transform` attribute (SVG 2 presentation
        # attribute); the runtime reads only the attribute, so convert it for static elements too.
        if "transform" in style_props[element]:
            raw = style_props[element].pop("transform")
            try:
                functions = parse_transform_functions(raw, css=True)
                if functions:
                    element.set("transform", format_transform_list(functions))
            except UnsupportedValue:
                warnings.warn("%s: static CSS transform '%s' is not representable"
                              % (describe(element), raw))
        records = animation_items(animation_declarations[element], warnings, describe(element))
        if records:
            emitted = convert_element_animations(element, records, keyframes, parents, style_props,
                                                 base_transforms[element], warnings,
                                                 samples_per_second)
            if emitted:
                animated_elements += 1
                emitted_animations += emitted
        rewrite_style_attribute(element, style_props[element])

    # Drop the consumed stylesheets; the declarations they matched are inlined above.
    if style_elements:
        for parent in list(root.iter()):
            for child in list(parent):
                if local_name(child.tag) == "style":
                    parent.remove(child)

    return animated_elements, emitted_animations


# --------------------------------------------------------------------------------------------
# Self-test
# --------------------------------------------------------------------------------------------

def self_test():
    def check(condition, message):
        if not condition:
            raise AssertionError(message)

    # Declarations: values may contain ':' and function arguments with commas.
    declarations = parse_declarations("fill:url(#sea);animation:cubic-bezier(1,-.43,0,1.29) 1s;x:a:b !important")
    check(declarations[0] == ("fill", "url(#sea)", False), "declaration value with ':'")
    check(declarations[1][1] == "cubic-bezier(1,-.43,0,1.29) 1s", "declaration with commas")
    check(declarations[2] == ("x", "a:b", True), "!important stripping and inner ':'")

    # Selectors and specificity: descendant chain, compound, universal.
    chain = parse_selector(".wA path")
    check(chain is not None and len(chain) == 2, "descendant selector chain")
    check(parse_selector("g > path") is None, "combinators are rejected")
    check(parse_selector("path:first-child") is None, "pseudo-classes are rejected")
    rule = Rule([parse_compound(".wA"), parse_compound("path")], [], 0)
    check(rule.specificity() == (0, 1, 1), "specificity")

    # `1_29.svg`'s shorthand, tokens in CSS order.
    record = parse_shorthand_item("lock 1s cubic-bezier(1,-.43,0,1.29) both infinite alternate-reverse",
                                 Warnings(), "test")
    check(record["name"] == "lock", "shorthand name")
    check(record["duration"] == 1.0, "shorthand duration")
    check(record["fill"] == "both", "shorthand fill")
    check(record["iterations"] == math.inf, "shorthand iteration count")
    check(record["direction"] == "alternate-reverse", "shorthand direction")
    check(record["timing"] == "cubic-bezier(1,-.43,0,1.29)", "shorthand timing function")

    # Bezier sampling: endpoints and the `ease` midpoint.
    ease = Easing("bezier", EASING_KEYWORDS["ease"])
    check(abs(ease(0.0)) < 1e-9 and abs(ease(1.0) - 1.0) < 1e-9, "bezier endpoints")
    check(abs(ease(0.5) - 0.8024) < 1e-3, "ease(0.5) ≈ 0.8024")

    # Direction: alternate-reverse starts at the far keyframe and ends at the near one.
    # CSS progress 0 is the `0%` keyframe (translateY(-2px)), progress 1 the implicit base (0).
    sampled = [(0.0, -2.0), (0.5, -1.0), (1.0, 0.0)]
    timeline = build_timeline(sampled, "alternate-reverse", math.inf)
    check(timeline is not None, "timeline built")
    times, values, repeat_count, total = timeline
    check(repeat_count == "indefinite" and abs(total - 2.0) < 1e-9, "cycle length for alternate")
    check(abs(values[0]) < 1e-9, "alternate-reverse starts at the base value")
    check(any(abs(t - 0.5) < 1e-9 and abs(v + 2.0) < 1e-9 for t, v in zip(times, values)),
          "alternate-reverse reaches the far value at the end of the reversed iteration")
    check(all(b > a for a, b in zip(times, times[1:])), "keyTimes strictly increase")

    # Colors.
    check(parse_color("#fff") == (1.0, 1.0, 1.0, 1.0), "short hex")
    check(parse_color("rgba(255, 0, 0, 0.5)") == (1.0, 0.0, 0.0, 0.5), "rgba()")
    check(interpolate_color((0, 0, 0, 1), (1, 1, 1, 1), 0.5) == (0.5, 0.5, 0.5, 1), "color interpolation")

    # End-to-end: the `1_29.svg` shape of a document.
    source = (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">'
        '<style>@keyframes lock{0%{transform:translateY(-2px)}}</style>'
        '<path fill="#265BFF" d="M0 0h1v1z" '
        'style="animation:lock 1s cubic-bezier(1,-.43,0,1.29) both infinite alternate-reverse"/>'
        '</svg>')
    root = ET.fromstring(source)
    animated, emitted = convert_document(root, Warnings(), 24)
    check((animated, emitted) == (1, 1), "one element, one animation")
    transform = root.find(".//{%s}animateTransform" % SVG_NS)
    check(transform is not None, "animateTransform is emitted")
    check(transform.get("type") == "translate", "type=translate")
    check(transform.get("dur") == "2s", "alternate cycle duration")
    check(transform.get("repeatCount") == "indefinite", "infinite repeat")
    check(transform.get("begin") == "0s", "begin")
    values = transform.get("values").split(";")
    times = transform.get("keyTimes").split(";")
    check(len(values) == len(times), "values and keyTimes have the same length")
    check(times[0] == "0" and times[-1] == "1", "keyTimes span 0…1")
    check(float(values[0].split()[1]) == 0.0, "starts at the base translate")
    check(min(float(value.split()[1]) for value in values) < -2.0, "bakes the overshoot")
    check(not root.findall(".//{%s}style" % SVG_NS), "the consumed <style> is removed")
    # No CSS animation leftovers on the element.
    check("animation" not in (root.find(".//{%s}path" % SVG_NS).get("style") or ""), "animation removed")
    # Transform extensions: CSS 3D aliases are flattened and same-kind lists collapse, so the
    # common designer chains fit one SMIL animation.
    check(parse_transform_functions("scale3d(1.25,.75,1)", css=True) == [("scale", (1.25, 0.75))],
          "scale3d alias")
    check(parse_transform_functions("translate3d(10px,4px,0)", css=True)
          == [("translate", (10.0, 4.0))], "translate3d alias")
    check(parse_transform_functions("rotateZ(90deg)", css=True) == [("rotate", (90.0,))],
          "rotateZ alias")
    merged = merge_same_kind(parse_transform_functions("translateY(-2px) translateX(3px)", css=True))
    check(merged == [("translate", (3.0, -2.0))], "same-kind translate merging")
    merged = merge_same_kind(parse_transform_functions("scale(2) scale(.5, 3)", css=True))
    check(merged == [("scale", (1.0, 6.0))], "same-kind scale merging")

    # A mixed chain (`translate` + `scale`) is not one SMIL function: it becomes nested wrappers.
    source = (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">'
        '<style>@keyframes pop{0%{transform:translate(0,0) scale(1)}'
        '100%{transform:translate(10px,0) scale(2)}}</style>'
        '<rect width="2" height="2" fill="#f00" style="animation:pop 2s linear infinite"/></svg>')
    root = ET.fromstring(source)
    warnings = Warnings()
    animated, emitted = convert_document(root, warnings, 24)
    check((animated, emitted) == (1, 1), "mixed-chain element converted")
    wrappers = [element for element in root.iter()
                if local_name(element.tag) == "g"
                and any(local_name(child.tag) == "animateTransform" for child in element)]
    check(len(wrappers) == 2, "one wrapper per transform function")
    outer = [child.get("type") for child in wrappers[0]
             if local_name(child.tag) == "animateTransform"]
    inner = [child.get("type") for child in wrappers[-1]
             if local_name(child.tag) == "animateTransform"]
    check(outer == ["translate"] and inner == ["scale"], "wrapper order matches the CSS list")
    rect = root.find(".//{%s}rect" % SVG_NS)
    check(rect is not None, "the animated element is still in the document")
    parents = {child: parent for parent in root.iter() for child in parent}
    check(parents.get(rect) is wrappers[-1], "the element sits inside the innermost wrapper")
    translate_values = [child for child in wrappers[0]
                        if local_name(child.tag) == "animateTransform"][0].get("values").split(";")
    check(translate_values[0] == "0 0" and translate_values[-1] == "10 0", "translation values")
    scale_values = [child for child in wrappers[-1]
                    if local_name(child.tag) == "animateTransform"][0].get("values").split(";")
    check(scale_values[0] == "1 1" and scale_values[-1] == "2 2", "scale values")

    print("self-test: OK")


# --------------------------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------------------------

def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Convert a CSS-animated SVG into the SVGRenderKit SMIL profile.")
    parser.add_argument("input", nargs="?", help="input .svg file")
    parser.add_argument("-o", "--output", help="output path (default: <input>-fixed.svg)")
    parser.add_argument("--samples-per-second", type=int, default=24,
                        help="sampling rate used to bake the CSS timing function (default: 24)")
    parser.add_argument("--strict", action="store_true", help="exit 1 when anything was degraded")
    parser.add_argument("--quiet", action="store_true", help="do not print the summary")
    parser.add_argument("--self-test", action="store_true", help="run the built-in checks and exit")
    arguments = parser.parse_args(argv)

    if arguments.self_test:
        self_test()
        return 0
    if not arguments.input:
        parser.error("an input file is required")

    warnings = Warnings()
    try:
        tree = ET.parse(arguments.input)
    except (ET.ParseError, OSError) as error:
        print("css-to-smil: cannot parse %s: %s" % (arguments.input, error), file=sys.stderr)
        return 1
    root = tree.getroot()
    register_namespaces(root)
    animated, emitted = convert_document(root, warnings, max(2, arguments.samples_per_second))

    # Degradation messages are diagnostics of what was left out, so they are printed even when
    # nothing could be converted (a file whose CSS animates only unsupported properties).
    for message in warnings.messages:
        print("warning: %s" % message, file=sys.stderr)

    if animated == 0:
        print("css-to-smil: nothing to convert in %s" % arguments.input, file=sys.stderr)
        if arguments.output:
            tree.write(arguments.output, encoding="UTF-8", xml_declaration=True)
        return 2

    output = arguments.output or re.sub(r"\.svg$", "", arguments.input) + "-fixed.svg"
    tree.write(output, encoding="UTF-8", xml_declaration=True)
    if not arguments.quiet:
        print("css-to-smil: %s -> %s (%d element(s), %d animation(s), %d warning(s))"
              % (arguments.input, output, animated, emitted, len(warnings)))
    if arguments.strict and warnings:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
