@testable import Hisohiso
import Security
import XCTest

/// Tests that avoid touching a real login Keychain. `SecItem*` calls against
/// the real Keychain are flaky in headless CI, so these focus on the pure,
/// deterministic surface: the `APIKeyType` account mapping and the
/// `OSStatus` -> `KeychainError` description mapping.
final class KeychainManagerTests: XCTestCase {
    // MARK: - APIKeyType account mapping

    func testAPIKeyTypeRawValuesAreStable() {
        // The raw values are the Keychain account names. Changing them silently
        // orphans previously stored keys, so pin them.
        XCTAssertEqual(KeychainManager.APIKeyType.openAI.rawValue, "openai-api-key")
        XCTAssertEqual(KeychainManager.APIKeyType.groq.rawValue, "groq-api-key")
    }

    func testAPIKeyTypeRoundTripsThroughRawValue() {
        for type in [KeychainManager.APIKeyType.openAI, .groq] {
            XCTAssertEqual(KeychainManager.APIKeyType(rawValue: type.rawValue), type)
        }
    }

    func testAPIKeyTypeRejectsUnknownRawValue() {
        XCTAssertNil(KeychainManager.APIKeyType(rawValue: "anthropic-api-key"))
        XCTAssertNil(KeychainManager.APIKeyType(rawValue: ""))
    }

    // MARK: - KeychainError descriptions

    func testEncodingErrorDescriptionIsStable() {
        XCTAssertEqual(KeychainError.encodingError.errorDescription, "Failed to encode data")
    }

    func testUnableToStoreDescriptionEmbedsStatus() {
        let error = KeychainError.unableToStore(status: errSecDuplicateItem)
        XCTAssertEqual(
            error.errorDescription,
            "Failed to store in Keychain (status: \(errSecDuplicateItem))"
        )
    }

    func testUnableToDeleteDescriptionEmbedsStatus() {
        let error = KeychainError.unableToDelete(status: errSecItemNotFound)
        XCTAssertEqual(
            error.errorDescription,
            "Failed to delete from Keychain (status: \(errSecItemNotFound))"
        )
    }

    func testStoreAndDeleteDescriptionsDifferForSameStatus() {
        let status: OSStatus = -12345
        let store = KeychainError.unableToStore(status: status)
        let delete = KeychainError.unableToDelete(status: status)

        XCTAssertNotEqual(store.errorDescription, delete.errorDescription)
        XCTAssertTrue(store.errorDescription?.contains("store") == true)
        XCTAssertTrue(delete.errorDescription?.contains("delete") == true)
    }

    func testStatusValueAppearsVerbatimInDescription() {
        // A caller diagnosing a failure needs the exact OSStatus in the message.
        let status: OSStatus = -25308 // errSecInteractionNotAllowed (locked keychain)
        let error = KeychainError.unableToStore(status: status)
        XCTAssertEqual(error.errorDescription?.contains("\(status)"), true)
    }
}
