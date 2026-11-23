import XCTest

final class SSEParserTests: XCTestCase {
    func testSingleEvent() {
        var parser = SSEParser()
        XCTAssertEqual(parser.feed("data: {\"a\":1}\n"), ["{\"a\":1}"])
    }

    func testMultipleEventsInOneChunk() {
        var parser = SSEParser()
        XCTAssertEqual(parser.feed("data: un\ndata: deux\n"), ["un", "deux"])
    }

    func testEventSplitAcrossChunks() {
        var parser = SSEParser()
        XCTAssertEqual(parser.feed("data: {\"mess"), [])
        XCTAssertEqual(parser.feed("age\": \"salut\"}\n"), ["{\"message\": \"salut\"}"])
    }

    func testIgnoresCommentsAndOtherFields() {
        var parser = SSEParser()
        let payloads = parser.feed(": keep-alive\nid: 42\nevent: message\ndata: hello\n\n")
        XCTAssertEqual(payloads, ["hello"])
    }

    func testCRLFLineEndings() {
        var parser = SSEParser()
        XCTAssertEqual(parser.feed("data: a\r\ndata: b\r\n"), ["a", "b"])
    }

    func testDoneMarkerIsPassedThrough() {
        var parser = SSEParser()
        XCTAssertEqual(parser.feed("data: [DONE]\n"), ["[DONE]"])
    }

    func testFinishFlushesTrailingPayload() {
        var parser = SSEParser()
        XCTAssertEqual(parser.feed("data: tail"), [])
        XCTAssertEqual(parser.finish(), ["tail"])
        XCTAssertEqual(parser.finish(), [])
    }

    func testEmptyDataLineIsIgnored() {
        var parser = SSEParser()
        XCTAssertEqual(parser.feed("data:\n\n"), [])
    }
}
