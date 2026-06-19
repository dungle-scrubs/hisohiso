@testable import Hisohiso
import XCTest

final class CLIArgumentsTests: XCTestCase {
    func testParseWithoutFlagsLaunchesApp() {
        let result = CLIArguments.parse(["hisohiso"])
        XCTAssertEqual(result, .success(.app(showHistoryOnLaunch: false)))
    }

    func testParseHistoryFlagLaunchesAppAndOpensHistory() {
        let result = CLIArguments.parse(["hisohiso", "--history"])
        XCTAssertEqual(result, .success(.app(showHistoryOnLaunch: true)))
    }

    func testParseHelpCommand() {
        let result = CLIArguments.parse(["hisohiso", "--help"])
        XCTAssertEqual(result, .success(.cli(command: .help)))
    }

    func testParseVersionCommand() {
        let result = CLIArguments.parse(["hisohiso", "--version"])
        XCTAssertEqual(result, .success(.cli(command: .version)))
    }

    func testParseListModelsCommand() {
        let result = CLIArguments.parse(["hisohiso", "--list-models"])
        XCTAssertEqual(result, .success(.cli(command: .listModels)))
    }

    func testParseTranscribeCommandWithDuration() {
        let result = CLIArguments.parse(["hisohiso", "--transcribe", "8"])
        XCTAssertEqual(
            result,
            .success(.cli(command: .transcribe(duration: 8, model: nil, rawOutput: false)))
        )
    }

    func testParseInteractiveTranscribeCommandWithoutDuration() {
        let result = CLIArguments.parse(["hisohiso", "--transcribe"])
        XCTAssertEqual(
            result,
            .success(.cli(command: .transcribe(duration: nil, model: nil, rawOutput: false)))
        )
    }

    func testParseTranscribeCommandWithModelAndRawOutput() {
        let result = CLIArguments.parse([
            "hisohiso", "--transcribe", "5", "--model", "openai_whisper-base.en", "--raw",
        ])

        XCTAssertEqual(
            result,
            .success(.cli(command: .transcribe(
                duration: 5,
                model: .whisperBase,
                rawOutput: true
            )))
        )
    }

    func testParseRejectsUnknownOption() {
        let result = CLIArguments.parse(["hisohiso", "--bogus"])
        XCTAssertEqual(result, .failure(.unknownOption("--bogus")))
    }

    func testParseRejectsModelWithoutTranscribe() {
        let result = CLIArguments.parse(["hisohiso", "--model", "openai_whisper-base.en"])
        XCTAssertEqual(result, .failure(.missingTranscribeFlag))
    }

    func testParseControlStartCommand() {
        let result = CLIArguments.parse(["hisohiso", "ctl", "start"])
        XCTAssertEqual(result, .success(.cli(command: .control(.start(model: nil)))))
    }

    func testParseControlStartWithModelCommand() {
        let result = CLIArguments.parse([
            "hisohiso", "ctl", "start", "--model", "openai_whisper-base.en",
        ])
        XCTAssertEqual(result, .success(.cli(command: .control(.start(model: .whisperBase)))))
    }

    func testParseControlPingCommand() {
        let result = CLIArguments.parse(["hisohiso", "ctl", "ping"])
        XCTAssertEqual(result, .success(.cli(command: .control(.ping))))
    }

    func testParseControlStatusCommand() {
        let result = CLIArguments.parse(["hisohiso", "ctl", "status"])
        XCTAssertEqual(result, .success(.cli(command: .control(.status))))
    }

    func testParseRejectsModelOverrideForPingControlCommand() {
        let result = CLIArguments.parse(["hisohiso", "ctl", "ping", "--model", "openai_whisper-base.en"])
        XCTAssertEqual(result, .failure(.conflictingCommands))
    }

    func testParseRejectsModelOverrideForStatusControlCommand() {
        let result = CLIArguments.parse(["hisohiso", "ctl", "status", "--model", "openai_whisper-base.en"])
        XCTAssertEqual(result, .failure(.conflictingCommands))
    }

    func testParseControlStopCommand() {
        let result = CLIArguments.parse(["hisohiso", "ctl", "stop"])
        XCTAssertEqual(result, .success(.cli(command: .control(.stop))))
    }

    func testParseControlCancelCommand() {
        let result = CLIArguments.parse(["hisohiso", "ctl", "cancel"])
        XCTAssertEqual(result, .success(.cli(command: .control(.cancel))))
    }

    func testParseRejectsModelOverrideForStopControlCommand() {
        let result = CLIArguments.parse(["hisohiso", "ctl", "stop", "--model", "openai_whisper-base.en"])
        XCTAssertEqual(result, .failure(.conflictingCommands))
    }

    func testParseRejectsUnknownControlCommand() {
        let result = CLIArguments.parse(["hisohiso", "ctl", "boom"])
        XCTAssertEqual(result, .failure(.invalidControlCommand("boom")))
    }

    func testParseRejectsMissingControlCommand() {
        let result = CLIArguments.parse(["hisohiso", "ctl"])
        XCTAssertEqual(result, .failure(.missingControlCommand))
    }

    func testParseRejectsConflictingHistoryAndHeadlessCommand() {
        let result = CLIArguments.parse(["hisohiso", "--history", "--help"])
        XCTAssertEqual(result, .failure(.conflictingCommands))
    }
}
