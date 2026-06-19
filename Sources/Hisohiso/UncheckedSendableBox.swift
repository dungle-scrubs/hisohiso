struct UncheckedSendableBox<Value>: @unchecked Sendable {
    let value: Value
}
