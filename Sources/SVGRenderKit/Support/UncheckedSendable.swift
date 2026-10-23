/// Hands a value that is not `Sendable` over to another queue, which owns it from then on
/// (the parser and layer built off-main, the override styles of a render).
struct UncheckedSendable<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}
