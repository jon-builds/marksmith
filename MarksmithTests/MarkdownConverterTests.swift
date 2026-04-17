import XCTest
@testable import Marksmith

final class MarkdownConverterTests: XCTestCase {

    private let converter = MarkdownConverter()

    // MARK: - Headings

    func testHeadingsProduceCorrectTags() {
        for level in 1...6 {
            let hashes = String(repeating: "#", count: level)
            let result = converter.convert(markdown: "\(hashes) Heading \(level)")
            XCTAssertTrue(result.html.contains("<h\(level) "), "Expected <h\(level)> tag")
            XCTAssertTrue(result.html.contains("</h\(level)>"), "Expected </h\(level)> closing tag")
        }
    }

    // MARK: - Inline Formatting

    func testBoldProducesStrong() {
        let result = converter.convert(markdown: "**bold text**")
        XCTAssertTrue(result.html.contains("<strong>bold text</strong>"))
    }

    func testItalicProducesEm() {
        let result = converter.convert(markdown: "*italic text*")
        XCTAssertTrue(result.html.contains("<em>italic text</em>"))
    }

    func testStrikethroughProducesDel() {
        let result = converter.convert(markdown: "~~deleted~~")
        XCTAssertTrue(result.html.contains("<del>deleted</del>"))
    }

    // MARK: - Links and Images

    func testLinksProduceAnchorTags() {
        let result = converter.convert(markdown: "[Example](https://example.com)")
        XCTAssertTrue(result.html.contains("<a href=\"https://example.com\">Example</a>"))
    }

    func testImagesProduceImgTags() {
        let result = converter.convert(markdown: "![Alt](image.png)")
        XCTAssertTrue(result.html.contains("<img src=\"image.png\""))
        XCTAssertTrue(result.html.contains("alt=\"Alt\""))
    }

    // MARK: - Code

    func testInlineCodeProducesCodeTag() {
        let result = converter.convert(markdown: "Use `print()`")
        XCTAssertTrue(result.html.contains("<code>print()</code>"))
    }

    func testCodeBlockProducesPreCodeTags() {
        let result = converter.convert(markdown: "```swift\nlet x = 42\n```")
        XCTAssertTrue(result.html.contains("<pre><code"))
        XCTAssertTrue(result.html.contains("language-swift"))
    }

    func testCodeBlockWithoutLanguage() {
        let result = converter.convert(markdown: "```\nsome code\n```")
        XCTAssertTrue(result.html.contains("<pre><code>"))
    }

    // MARK: - Lists

    func testUnorderedListProducesUlLi() {
        let result = converter.convert(markdown: "- Item 1\n- Item 2")
        XCTAssertTrue(result.html.contains("<ul>"))
        XCTAssertTrue(result.html.contains("<li>"))
    }

    func testOrderedListProducesOlLi() {
        let result = converter.convert(markdown: "1. First\n2. Second")
        XCTAssertTrue(result.html.contains("<ol>"))
        XCTAssertTrue(result.html.contains("<li>"))
    }

    func testTaskListProducesCheckboxes() {
        let result = converter.convert(markdown: "- [x] Done\n- [ ] Not done")
        // Unicode ballot boxes: ☑ (checked) and ☐ (unchecked)
        XCTAssertTrue(result.html.contains("&#x2611;"))
        XCTAssertTrue(result.html.contains("&#x2610;"))
    }

    // MARK: - Block Elements

    func testBlockquoteProducesBlockquoteTag() {
        let result = converter.convert(markdown: "> A quote")
        XCTAssertTrue(result.html.contains("<blockquote>"))
    }

    func testHorizontalRuleProducesHrTag() {
        let result = converter.convert(markdown: "---")
        // Rendered as a border-top paragraph for RTF compatibility
        XCTAssertTrue(result.html.contains("border-top"))
    }

    // MARK: - Tables

    func testTableProducesFullStructure() {
        let markdown = """
        | Header 1 | Header 2 |
        |----------|----------|
        | Cell 1   | Cell 2   |
        """
        let result = converter.convert(markdown: markdown)
        XCTAssertTrue(result.html.contains("<table>"))
        XCTAssertTrue(result.html.contains("<thead>"))
        XCTAssertTrue(result.html.contains("<tbody>"))
        XCTAssertTrue(result.html.contains("<tr>"))
        XCTAssertTrue(result.html.contains("<th>"))
        XCTAssertTrue(result.html.contains("<td>"))
    }

    // MARK: - RTF Generation

    func testRTFDataIsNonNilForValidMarkdown() {
        let result = converter.convert(markdown: "# Hello\n\nSome **bold** text.")
        XCTAssertNotNil(result.rtf, "RTF data should be non-nil for valid markdown")
    }

    func testRTFDataIsNonNilForSimpleText() {
        let result = converter.convert(markdown: "Just plain text")
        XCTAssertNotNil(result.rtf)
    }

    // MARK: - HTML Escaping

    func testHTMLEntitiesAreEscaped() {
        // Use ampersand and angle brackets in a context where swift-markdown
        // parses them as Text nodes (not InlineHTML). Ampersand in regular text
        // and angle brackets inside inline code are escaped by our visitor.
        let result = converter.convert(markdown: "Tom & Jerry")
        XCTAssertTrue(result.html.contains("&amp;"), "Ampersand should be escaped")

        // Angle brackets inside code are escaped via escapeHTML in visitCodeBlock
        let codeResult = converter.convert(markdown: "`<div>`")
        XCTAssertTrue(codeResult.html.contains("&lt;div&gt;"), "Angle brackets in inline code should be escaped")
    }

    func testQuotesAreEscapedInAttributes() {
        // Quotes in link URLs are escaped by escapeHTML
        let result = converter.convert(markdown: "[link](https://example.com/a\"b)")
        XCTAssertTrue(result.html.contains("&quot;"), "Quotes in href should be escaped")
    }

    // MARK: - CSS Wrapper

    func testHTMLContainsCSSStyles() {
        let result = converter.convert(markdown: "# Test")
        XCTAssertTrue(result.html.contains("<style>"))
        XCTAssertTrue(result.html.contains("font-family"))
        XCTAssertTrue(result.html.contains("border-collapse"))
    }

    func testHTMLIsFullDocument() {
        let result = converter.convert(markdown: "# Test")
        XCTAssertTrue(result.html.contains("<!DOCTYPE html>"))
        XCTAssertTrue(result.html.contains("<html>"))
        XCTAssertTrue(result.html.contains("</html>"))
    }

    func testHTMLContainsBodyTags() {
        let result = converter.convert(markdown: "# Test")
        XCTAssertTrue(result.html.contains("<body>"))
        XCTAssertTrue(result.html.contains("</body>"))
    }

    // MARK: - Complex Documents

    func testFullGFMDocument() {
        let markdown = """
        # Title

        Paragraph with **bold**, *italic*, and `code`.

        ## Links

        [Example](https://example.com)

        ## List

        - Item 1
        - Item 2

        > A blockquote

        ```python
        print("hello")
        ```

        | Col 1 | Col 2 |
        |-------|-------|
        | A     | B     |
        """
        let result = converter.convert(markdown: markdown)
        XCTAssertTrue(result.html.contains("<h1 "))
        XCTAssertTrue(result.html.contains("<strong>"))
        XCTAssertTrue(result.html.contains("<em>"))
        XCTAssertTrue(result.html.contains("<code>"))
        XCTAssertTrue(result.html.contains("<a href"))
        XCTAssertTrue(result.html.contains("<ul>"))
        XCTAssertTrue(result.html.contains("<blockquote>"))
        XCTAssertTrue(result.html.contains("<pre>"))
        XCTAssertTrue(result.html.contains("<table>"))
        XCTAssertNotNil(result.rtf)
    }

    // MARK: - Specific Element Content

    func testHeadingContent() {
        let result = converter.convert(markdown: "# My Title")
        XCTAssertTrue(result.html.contains("My Title</h1>"))
    }

    func testNestedFormatting() {
        let result = converter.convert(markdown: "**bold and *italic***")
        XCTAssertTrue(result.html.contains("<strong>"))
        XCTAssertTrue(result.html.contains("<em>"))
    }

    func testCodeBlockEscapesContent() {
        let result = converter.convert(markdown: "```\n<script>alert('xss')</script>\n```")
        XCTAssertTrue(result.html.contains("&lt;script&gt;"))
        XCTAssertFalse(result.html.contains("<script>alert"))
    }

    func testHTMLBlockIsEscaped() {
        let result = converter.convert(markdown: "<img onerror=\"javascript:alert('xss')\" src=\"x\">")
        XCTAssertFalse(result.html.contains("<img onerror"), "Raw HTML block should be escaped")
        XCTAssertTrue(result.html.contains("&lt;img"))
    }

    func testInlineHTMLIsEscaped() {
        let result = converter.convert(markdown: "Hello <script>alert('xss')</script> world")
        XCTAssertFalse(result.html.contains("<script>"), "Inline HTML should be escaped")
        XCTAssertTrue(result.html.contains("&lt;script&gt;"))
    }

    func testLineBreak() {
        // Two trailing spaces followed by newline create a hard line break
        let result = converter.convert(markdown: "Line one  \nLine two")
        XCTAssertTrue(result.html.contains("<br>"))
    }

    // MARK: - Heading Style Compatibility (Word/Pages)

    func testHeadingHTMLContainsMsoStyleName() {
        for level in 1...6 {
            let hashes = String(repeating: "#", count: level)
            let result = converter.convert(markdown: "\(hashes) Heading \(level)")
            XCTAssertTrue(result.html.contains("mso-style-name:'Heading \(level)'"),
                          "Expected mso-style-name for heading level \(level)")
        }
    }

    func testRTFContainsHeadingStylesheet() {
        let result = converter.convert(markdown: "# Title\n\nBody text")
        let rtfString = String(data: result.rtf!, encoding: .ascii) ?? String(data: result.rtf!, encoding: .utf8)!
        XCTAssertTrue(rtfString.contains("Heading 1"), "RTF stylesheet should contain Heading 1 definition")
    }

    func testRTFHeading1HasStyleMarker() {
        let result = converter.convert(markdown: "# Title\n\nBody text")
        let rtfString = String(data: result.rtf!, encoding: .ascii) ?? String(data: result.rtf!, encoding: .utf8)!
        XCTAssertTrue(rtfString.contains("\\s1"), "RTF should contain \\s1 paragraph style marker")
    }

    func testRTFMultipleHeadingLevels() {
        let result = converter.convert(markdown: "# H1\n\n## H2\n\n### H3\n\nBody")
        let rtfString = String(data: result.rtf!, encoding: .ascii) ?? String(data: result.rtf!, encoding: .utf8)!
        XCTAssertTrue(rtfString.contains("Heading 1"), "RTF stylesheet should contain Heading 1")
        XCTAssertTrue(rtfString.contains("Heading 2"), "RTF stylesheet should contain Heading 2")
        XCTAssertTrue(rtfString.contains("Heading 3"), "RTF stylesheet should contain Heading 3")
        XCTAssertTrue(rtfString.contains("\\s1"), "RTF should contain \\s1 marker")
        XCTAssertTrue(rtfString.contains("\\s2"), "RTF should contain \\s2 marker")
        XCTAssertTrue(rtfString.contains("\\s3"), "RTF should contain \\s3 marker")
    }

    func testRTFHeadingWithInlineFormatting() {
        let result = converter.convert(markdown: "# **Bold** heading")
        let rtfString = String(data: result.rtf!, encoding: .ascii) ?? String(data: result.rtf!, encoding: .utf8)!
        XCTAssertTrue(rtfString.contains("\\s1"), "RTF should contain \\s1 marker even with inline formatting")
    }

    func testRTFOnlyUsedLevelsInStylesheet() {
        let result = converter.convert(markdown: "## Only H2\n\nBody")
        let rtfString = String(data: result.rtf!, encoding: .ascii) ?? String(data: result.rtf!, encoding: .utf8)!
        XCTAssertTrue(rtfString.contains("Heading 2"), "RTF stylesheet should contain Heading 2")
        XCTAssertFalse(rtfString.contains("Heading 1"), "RTF stylesheet should NOT contain Heading 1 when unused")
    }

    func testRTFNonHeadingParagraphsUnchanged() {
        let result = converter.convert(markdown: "# Heading\n\nRegular paragraph")
        let rtfString = String(data: result.rtf!, encoding: .ascii) ?? String(data: result.rtf!, encoding: .utf8)!
        // Find "Regular paragraph" and check the \pard before it does NOT have \s1
        if let range = rtfString.range(of: "Regular paragraph") {
            let before = rtfString[rtfString.startIndex..<range.lowerBound]
            if let pardRange = before.range(of: "\\pard", options: .backwards) {
                let afterPard = rtfString[pardRange.upperBound..<range.lowerBound]
                XCTAssertFalse(afterPard.contains("\\s1"), "Non-heading paragraph should not have \\s1 marker")
            }
        }
    }

    func testRTFEmptyHeadingSkipped() {
        // Empty heading should not crash
        let result = converter.convert(markdown: "#\n\nBody text")
        XCTAssertNotNil(result.rtf, "RTF should still be generated with empty heading")
    }

    func testHTMLHeadingTagsPreserved() {
        let result = converter.convert(markdown: "# Title\n\n## Subtitle")
        XCTAssertTrue(result.html.contains("<h1"), "HTML should still contain h1 tag")
        XCTAssertTrue(result.html.contains("<h2"), "HTML should still contain h2 tag")
    }

    // MARK: - Word-desktop recognition control words (v1.2.3)

    func testRTFStylesheetContainsOutlineLevels() {
        let markdown = (1...6).map { String(repeating: "#", count: $0) + " Heading \($0)" }.joined(separator: "\n\n")
        let result = converter.convert(markdown: markdown)
        let rtfString = String(data: result.rtf!, encoding: .ascii) ?? String(data: result.rtf!, encoding: .utf8)!
        for level in 1...6 {
            let expected = "\\outlinelevel\(level - 1)"
            XCTAssertTrue(rtfString.contains(expected),
                          "RTF should contain \(expected) for Heading \(level)")
        }
    }

    func testRTFStylesheetContainsSbasedonAndSnext() {
        let result = converter.convert(markdown: "# H1")
        let rtfString = String(data: result.rtf!, encoding: .ascii) ?? String(data: result.rtf!, encoding: .utf8)!
        XCTAssertTrue(rtfString.contains("\\sbasedon0"),
                      "Heading stylesheet entry should declare \\sbasedon0")
        XCTAssertTrue(rtfString.contains("\\snext0"),
                      "Heading stylesheet entry should declare \\snext0")
    }

    func testRTFStylesheetContainsKeepn() {
        let result = converter.convert(markdown: "# H1")
        let rtfString = String(data: result.rtf!, encoding: .ascii) ?? String(data: result.rtf!, encoding: .utf8)!
        XCTAssertTrue(rtfString.contains("\\keepn"),
                      "Heading stylesheet entry should include \\keepn")
    }

    func testRTFHeadingParagraphRestatesOutlineLevel() {
        let result = converter.convert(markdown: "## Heading 2 body")
        let rtfString = String(data: result.rtf!, encoding: .ascii) ?? String(data: result.rtf!, encoding: .utf8)!
        // Paragraph marker should include \s2\keepn\outlinelevel1 — Word reads
        // paragraph properties directly on paste, so we restate them.
        XCTAssertTrue(rtfString.contains("\\s2\\keepn\\outlinelevel1\\sb240\\sa60"),
                      "Heading paragraph marker should restate outline level + keepn + spacing")
    }

    func testRTFOnlyUsedOutlineLevelsEmitted() {
        let result = converter.convert(markdown: "### H3 only\n\nBody")
        let rtfString = String(data: result.rtf!, encoding: .ascii) ?? String(data: result.rtf!, encoding: .utf8)!
        XCTAssertTrue(rtfString.contains("\\outlinelevel2"),
                      "Used H3 should emit \\outlinelevel2")
        XCTAssertFalse(rtfString.contains("\\outlinelevel0"),
                       "Unused H1 should NOT emit \\outlinelevel0 in stylesheet")
    }
}
