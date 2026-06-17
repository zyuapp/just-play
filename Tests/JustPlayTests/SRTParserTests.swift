import XCTest
@testable import JustPlay

final class SRTParserTests: XCTestCase {
  private func srt(_ lines: [String]) -> String {
    lines.joined(separator: "\n")
  }

  func testParsesCuesWithCommaTimestamps() {
    let text = srt([
      "1",
      "00:00:01,000 --> 00:00:02,500",
      "Hello world",
      "",
      "2",
      "00:00:03,000 --> 00:00:04,000",
      "Second line"
    ])

    let cues = SRTSubtitleParser().parse(text: text)

    XCTAssertEqual(cues.count, 2)
    XCTAssertEqual(cues[0].start, 1.0, accuracy: 0.001)
    XCTAssertEqual(cues[0].end, 2.5, accuracy: 0.001)
    XCTAssertEqual(cues[0].text, "Hello world")
    XCTAssertEqual(cues[1].start, 3.0, accuracy: 0.001)
    XCTAssertEqual(cues[1].text, "Second line")
  }

  func testParsesPeriodTimestampsAndHoursComponent() {
    let text = srt([
      "1",
      "01:02:03.500 --> 01:02:04.000",
      "With hours"
    ])

    let cues = SRTSubtitleParser().parse(text: text)

    XCTAssertEqual(cues.count, 1)
    XCTAssertEqual(cues[0].start, 3723.5, accuracy: 0.001)
    XCTAssertEqual(cues[0].end, 3724.0, accuracy: 0.001)
  }

  func testNormalizesCarriageReturnsAndJoinsMultiLineText() {
    let text = "1\r\n00:00:01,000 --> 00:00:02,000\r\nLine one\r\nLine two\r\n"

    let cues = SRTSubtitleParser().parse(text: text)

    XCTAssertEqual(cues.count, 1)
    XCTAssertEqual(cues[0].text, "Line one\nLine two")
  }

  func testSortsCuesByStartTime() {
    let text = srt([
      "1",
      "00:00:10,000 --> 00:00:11,000",
      "Later",
      "",
      "2",
      "00:00:02,000 --> 00:00:03,000",
      "Earlier"
    ])

    let cues = SRTSubtitleParser().parse(text: text)

    XCTAssertEqual(cues.map(\.text), ["Earlier", "Later"])
  }

  func testSkipsBlocksWithoutTimingLine() {
    let text = srt([
      "This is just a note with no timing",
      "",
      "1",
      "00:00:01,000 --> 00:00:02,000",
      "Valid"
    ])

    let cues = SRTSubtitleParser().parse(text: text)

    XCTAssertEqual(cues.count, 1)
    XCTAssertEqual(cues[0].text, "Valid")
  }

  func testSkipsCuesWhereEndIsNotAfterStart() {
    let text = srt([
      "1",
      "00:00:05,000 --> 00:00:05,000",
      "Zero length",
      "",
      "2",
      "00:00:09,000 --> 00:00:08,000",
      "Inverted"
    ])

    XCTAssertTrue(SRTSubtitleParser().parse(text: text).isEmpty)
  }

  func testSkipsMalformedSecondsTimestampWithoutCrashing() {
    let text = srt([
      "1",
      "00:00:. --> 00:00:01,000",
      "Malformed seconds",
      "",
      "2",
      "00:00:01,000 --> 00:00:02,000",
      "Valid"
    ])

    let cues = SRTSubtitleParser().parse(text: text)

    XCTAssertEqual(cues.map(\.text), ["Valid"])
  }

  func testSkipsCuesWithNoTextLines() {
    let text = srt([
      "1",
      "00:00:01,000 --> 00:00:02,000"
    ])

    XCTAssertTrue(SRTSubtitleParser().parse(text: text).isEmpty)
  }

  func testEmptyInputProducesNoCues() {
    XCTAssertTrue(SRTSubtitleParser().parse(text: "").isEmpty)
  }

  func testParseURLReadsUTF8File() throws {
    let text = srt([
      "1",
      "00:00:01,000 --> 00:00:02,000",
      "From disk"
    ])
    let url = try writeTemporaryFile(contents: Data(text.utf8))

    let cues = try SRTSubtitleParser().parse(url: url)

    XCTAssertEqual(cues.count, 1)
    XCTAssertEqual(cues[0].text, "From disk")
  }

  func testParseURLDecodesUTF16File() throws {
    let text = srt([
      "1",
      "00:00:01,000 --> 00:00:02,000",
      "UTF sixteen"
    ])
    let data = try XCTUnwrap(text.data(using: .utf16))
    let url = try writeTemporaryFile(contents: data)

    let cues = try SRTSubtitleParser().parse(url: url)

    XCTAssertEqual(cues.count, 1)
    XCTAssertEqual(cues[0].text, "UTF sixteen")
  }

  private var temporaryFiles: [URL] = []

  override func tearDown() {
    for url in temporaryFiles {
      try? FileManager.default.removeItem(at: url)
    }
    temporaryFiles.removeAll()
    super.tearDown()
  }

  private func writeTemporaryFile(contents: Data) throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("SRTParserTests-\(UUID().uuidString).srt")
    try contents.write(to: url)
    temporaryFiles.append(url)
    return url
  }
}
