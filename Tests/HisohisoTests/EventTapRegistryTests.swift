@testable import Hisohiso
import XCTest

final class EventTapRegistryTests: XCTestCase {
    private final class CallRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [String] = []

        func append(_ value: String) {
            lock.withLock { values.append(value) }
        }

        var recordedValues: [String] {
            lock.withLock { values }
        }
    }

    func testDispatchCallsMatchingHandlersInRegistrationOrder() throws {
        let registry = EventTapRegistry()
        let event = try Self.makeEvent()
        let calls = CallRecorder()

        registry.register(id: "first", eventTypes: [.keyDown]) { _, _ in
            calls.append("first")
            return false
        }
        registry.register(id: "second", eventTypes: [.keyDown]) { _, _ in
            calls.append("second")
            return false
        }

        XCTAssertFalse(registry.dispatch(event: event, type: .keyDown))
        XCTAssertEqual(calls.recordedValues, ["first", "second"])
    }

    func testDispatchStopsAfterFirstConsumingHandler() throws {
        let registry = EventTapRegistry()
        let event = try Self.makeEvent()
        let calls = CallRecorder()

        registry.register(id: "first", eventTypes: [.keyDown]) { _, _ in
            calls.append("first")
            return true
        }
        registry.register(id: "second", eventTypes: [.keyDown]) { _, _ in
            calls.append("second")
            return false
        }

        XCTAssertTrue(registry.dispatch(event: event, type: .keyDown))
        XCTAssertEqual(calls.recordedValues, ["first"])
    }

    func testUnregisterPreventsFutureDispatch() throws {
        let registry = EventTapRegistry()
        let event = try Self.makeEvent()
        let calls = CallRecorder()

        registry.register(id: "handler", eventTypes: [.keyDown]) { _, _ in
            calls.append("handler")
            return false
        }
        registry.unregister(id: "handler")

        XCTAssertFalse(registry.dispatch(event: event, type: .keyDown))
        XCTAssertTrue(registry.isEmpty)
        XCTAssertTrue(calls.recordedValues.isEmpty)
    }

    func testRegisteringSameIDReplacesHandler() throws {
        let registry = EventTapRegistry()
        let event = try Self.makeEvent()
        let calls = CallRecorder()

        registry.register(id: "handler", eventTypes: [.keyDown]) { _, _ in
            calls.append("old")
            return false
        }
        registry.register(id: "handler", eventTypes: [.keyDown]) { _, _ in
            calls.append("new")
            return false
        }

        XCTAssertFalse(registry.dispatch(event: event, type: .keyDown))
        XCTAssertEqual(calls.recordedValues, ["new"])
    }

    func testEventMaskReflectsRegisteredEventTypes() {
        let registry = EventTapRegistry()
        registry.register(id: "key", eventTypes: [.keyDown, .flagsChanged]) { _, _ in false }

        let expected = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        XCTAssertEqual(registry.eventMask(), CGEventMask(expected))
    }

    private static func makeEvent() throws -> CGEvent {
        try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true))
    }
}
