import XCTest
@testable import AIConsentKit

final class SSEParserTests: XCTestCase {

    func testParsesSingleEvent() {
        var parser = SSEParser()
        let events = parser.consume("event: delta\ndata: {\"text\":\"hi\"}\n\n")
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].name, "delta")
        XCTAssertEqual(events[0].data, "{\"text\":\"hi\"}")
    }

    /// The regression that matters: a chunk boundary landing mid-event.
    func testEventSplitAcrossChunks() {
        var parser = SSEParser()
        XCTAssertTrue(parser.consume("event: del").isEmpty)
        XCTAssertTrue(parser.consume("ta\ndata: {\"te").isEmpty)
        let events = parser.consume("xt\":\"hi\"}\n\n")
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].name, "delta")
        XCTAssertEqual(events[0].data, "{\"text\":\"hi\"}")
    }

    func testMultipleEventsInOneChunk() {
        var parser = SSEParser()
        let payload = """
        event: started
        data: {"input_tokens":5}

        event: delta
        data: {"text":"a"}

        event: delta
        data: {"text":"b"}


        """
        let events = parser.consume(payload)
        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events.map(\.name), ["started", "delta", "delta"])
    }

    func testHandlesCRLF() {
        var parser = SSEParser()
        let events = parser.consume("event: delta\r\ndata: x\r\n\r\n")
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].data, "x")
    }

    func testIgnoresCommentsAndPings() {
        var parser = SSEParser()
        let events = parser.consume(": heartbeat\n\nevent: delta\ndata: x\n\n")
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].name, "delta")
    }

    func testMultiLineDataIsNewlineJoined() {
        var parser = SSEParser()
        let events = parser.consume("event: delta\ndata: line one\ndata: line two\n\n")
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].data, "line one\nline two")
    }

    func testStripsExactlyOneLeadingSpace() {
        var parser = SSEParser()
        let events = parser.consume("event: delta\ndata:  two spaces\n\n")
        XCTAssertEqual(events[0].data, " two spaces")
    }
}
