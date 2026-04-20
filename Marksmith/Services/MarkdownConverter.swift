import Foundation
import Markdown
import AppKit

struct MarkdownConverter {

    func convert(markdown: String, fontSize: Int = 14) -> (html: String, rtf: Data?) {
        let document = Document(parsing: markdown)
        var visitor = HTMLVisitor()
        let bodyHTML = visitor.visit(document)
        let fullHTML = wrapInHTMLDocument(bodyHTML, fontSize: fontSize)
        let rtf = generateRTF(from: fullHTML, headings: visitor.headings)
        return (html: fullHTML, rtf: rtf)
    }

    // MARK: - HTML Document Wrapper

    private func wrapInHTMLDocument(_ body: String, fontSize: Int = 14) -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="ProgId" content="Word.Document">
        <style>
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif; font-size: \(fontSize)px; line-height: 1.6; color: #333; }
        h1 { mso-style-name: "Heading 1"; mso-style-next: Normal; mso-outline-level: 1; page-break-after: avoid; }
        h2 { mso-style-name: "Heading 2"; mso-style-next: Normal; mso-outline-level: 2; page-break-after: avoid; }
        h3 { mso-style-name: "Heading 3"; mso-style-next: Normal; mso-outline-level: 3; page-break-after: avoid; }
        h4 { mso-style-name: "Heading 4"; mso-style-next: Normal; mso-outline-level: 4; page-break-after: avoid; }
        h5 { mso-style-name: "Heading 5"; mso-style-next: Normal; mso-outline-level: 5; page-break-after: avoid; }
        h6 { mso-style-name: "Heading 6"; mso-style-next: Normal; mso-outline-level: 6; page-break-after: avoid; }
        code { background-color: #f0f0f0; padding: 2px 6px; border-radius: 3px; font-family: "SF Mono", Menlo, monospace; font-size: 0.9em; }
        pre { background-color: #f6f8fa; padding: 12px; border-radius: 6px; overflow-x: auto; }
        pre code { background: none; padding: 0; }
        blockquote { border-left: 4px solid #ddd; margin: 0; padding: 0 1em; color: #666; }
        table { border-collapse: collapse; width: 100%; }
        th, td { border: 1px solid #ddd; padding: 8px 12px; text-align: left; }
        th { background-color: #f6f8fa; font-weight: 600; }
        hr { border: none; border-top: 1px solid #ddd; margin: 1.5em 0; }
        a { color: #0366d6; text-decoration: none; }
        img { max-width: 100%; }
        del { color: #999; }
        ul, ol { padding-left: 2em; }
        </style></head>
        <body>
        \(body)
        </body>
        </html>
        """
    }

    // MARK: - RTF Generation

    private func generateRTF(from html: String, headings: [HeadingInfo]) -> Data? {
        guard let htmlData = html.data(using: .utf8) else { return nil }
        guard let attrStr = NSAttributedString(
            html: htmlData,
            options: [.documentType: NSAttributedString.DocumentType.html,
                      .characterEncoding: String.Encoding.utf8.rawValue],
            documentAttributes: nil
        ) else { return nil }
        guard var rtfData = try? attrStr.data(
            from: NSRange(location: 0, length: attrStr.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        ) else { return nil }

        if !headings.isEmpty {
            rtfData = injectHeadingStyles(into: rtfData, headings: headings)
        }
        return rtfData
    }

    // MARK: - RTF Heading Style Injection

    /// Post-process RTF data to add heading paragraph styles that Word/Pages recognize.
    private func injectHeadingStyles(into rtfData: Data, headings: [HeadingInfo]) -> Data {
        guard var rtfString = String(data: rtfData, encoding: .ascii)
                ?? String(data: rtfData, encoding: .utf8) else {
            return rtfData
        }

        rtfString = injectStylesheet(into: rtfString, headings: headings)
        rtfString = markHeadingParagraphs(in: rtfString, headings: headings)

        return rtfString.data(using: .ascii) ?? rtfString.data(using: .utf8) ?? rtfData
    }

    /// Insert heading style definitions into the RTF stylesheet group.
    /// Creates the stylesheet if NSAttributedString didn't generate one.
    private func injectStylesheet(into rtf: String, headings: [HeadingInfo]) -> String {
        let usedLevels = Set(headings.map(\.level))

        // RTF font sizes in half-points
        let styleDefs: [(level: Int, name: String, fs: Int)] = [
            (1, "Heading 1", 48), (2, "Heading 2", 36), (3, "Heading 3", 28),
            (4, "Heading 4", 24), (5, "Heading 5", 22), (6, "Heading 6", 20)
        ]

        var styleEntries = ""
        for def in styleDefs where usedLevels.contains(def.level) {
            let outlineLevel = def.level - 1
            styleEntries += "{\\s\(def.level)\\sb240\\sa60\\keepn\\outlinelevel\(outlineLevel)\\b\\fs\(def.fs)\\sbasedon0\\snext0 \(def.name);}"
        }

        guard !styleEntries.isEmpty else { return rtf }

        var result = rtf

        if let stylesheetStart = result.range(of: "{\\stylesheet") {
            // Stylesheet exists — find its closing brace and insert before it
            var depth = 0
            var endIndex = stylesheetStart.lowerBound
            for idx in result[stylesheetStart.lowerBound...].indices {
                let ch = result[idx]
                if ch == "{" { depth += 1 }
                else if ch == "}" {
                    depth -= 1
                    if depth == 0 { endIndex = idx; break }
                }
            }
            result.insert(contentsOf: styleEntries, at: endIndex)
        } else {
            // No stylesheet — create one before the first \pard
            let stylesheet = "{\\stylesheet{\\s0 Normal;}\(styleEntries)}"
            if let pardRange = result.range(of: "\\pard") {
                result.insert(contentsOf: "\n\(stylesheet)\n", at: pardRange.lowerBound)
            }
        }

        return result
    }

    /// Add \sN paragraph style markers to heading paragraphs in RTF.
    private func markHeadingParagraphs(in rtf: String, headings: [HeadingInfo]) -> String {
        var result = rtf
        // Start search after the first \pard so heading plain text ("Heading 1")
        // doesn't false-match the stylesheet's style-name entries we injected
        // earlier ({\s1 ... Heading 1;}).
        var searchFrom = result.range(of: "\\pard")?.lowerBound ?? result.startIndex

        for heading in headings {
            let searchText = heading.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !searchText.isEmpty else { continue }

            // Find the heading text in the RTF after our current search position
            guard let textRange = result.range(of: searchText, range: searchFrom..<result.endIndex) else {
                continue
            }

            // Scan backwards to find \pard as a complete control word (not inside \pardeftab etc.)
            guard let pardRange = findPardBackwards(in: result, before: textRange.lowerBound) else {
                continue
            }

            // Insert \sN and paragraph properties right after \pard.
            // Word desktop applies paragraph properties directly on paste
            // (not via style lookup), so we restate outline level + keepn
            // at paragraph level for the Styles pane to report "Heading N".
            let insertionPoint = pardRange.upperBound
            let outlineLevel = heading.level - 1
            let styleMarker = "\\s\(heading.level)\\keepn\\outlinelevel\(outlineLevel)\\sb240\\sa60"
            let sentinel = "\\s\(heading.level)"

            let afterPard = result[insertionPoint...]
            if !afterPard.hasPrefix(sentinel) {
                result.insert(contentsOf: styleMarker, at: insertionPoint)
                // Advance search past this heading to handle duplicates correctly
                let offset = result.distance(from: result.startIndex, to: insertionPoint) + styleMarker.count
                searchFrom = result.index(result.startIndex, offsetBy: offset)
            } else {
                searchFrom = textRange.upperBound
            }
        }

        return result
    }

    /// Find \pard as a complete RTF control word (not a prefix of \pardeftab etc.)
    /// by scanning backwards from the given position.
    private func findPardBackwards(in rtf: String, before end: String.Index) -> Range<String.Index>? {
        var searchEnd = end
        while let range = rtf[rtf.startIndex..<searchEnd].range(of: "\\pard", options: .backwards) {
            // Check the character after \pard is not a lowercase letter
            let afterPard = range.upperBound
            if afterPard >= rtf.endIndex || !rtf[afterPard].isLowercase {
                return range
            }
            // This \pard is part of a longer control word — keep searching
            searchEnd = range.lowerBound
        }
        return nil
    }
}

// MARK: - HTMLVisitor

private struct HeadingInfo {
    let level: Int
    let plainText: String
}

private struct HTMLVisitor: MarkupVisitor {
    typealias Result = String

    // Track whether we are inside a table head to differentiate <th> vs <td>
    private var inTableHead = false
    // Track column alignments from the current table
    private var columnAlignments: [Table.ColumnAlignment?] = []
    private var currentColumnIndex = 0
    // Collected heading metadata for RTF post-processing
    private(set) var headings: [HeadingInfo] = []

    // MARK: - Default

    mutating func defaultVisit(_ markup: any Markup) -> String {
        var result = ""
        for child in markup.children {
            result += visit(child)
        }
        return result
    }

    // MARK: - Block Elements

    mutating func visitDocument(_ document: Document) -> String {
        return defaultVisit(document)
    }

    mutating func visitHeading(_ heading: Heading) -> String {
        let level = heading.level
        let content = defaultVisit(heading)
        headings.append(HeadingInfo(level: level, plainText: heading.plainText))
        return "<h\(level) style=\"mso-style-name:&quot;Heading \(level)&quot;;mso-outline-level:\(level)\">\(content)</h\(level)>\n"
    }

    mutating func visitParagraph(_ paragraph: Paragraph) -> String {
        let content = defaultVisit(paragraph)
        return "<p>\(content)</p>\n"
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> String {
        let content = defaultVisit(blockQuote)
        return "<blockquote>\(content)</blockquote>\n"
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> String {
        let escaped = escapeHTML(codeBlock.code)
        if let language = codeBlock.language, !language.isEmpty {
            return "<pre><code class=\"language-\(escapeHTML(language))\">\(escaped)</code></pre>\n"
        }
        return "<pre><code>\(escaped)</code></pre>\n"
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) -> String {
        // <hr> is often stripped during HTML→RTF conversion. A border-top on a
        // near-invisible paragraph is more reliably preserved across rich-text apps.
        return "<p style=\"border-top: 1px solid #ddd; margin: 1em 0; padding: 0; font-size: 1px; line-height: 0;\">&nbsp;</p>\n"
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) -> String {
        return escapeHTML(html.rawHTML)
    }

    // MARK: - List Elements

    mutating func visitOrderedList(_ orderedList: OrderedList) -> String {
        let content = defaultVisit(orderedList)
        return "<ol>\(content)</ol>\n"
    }

    mutating func visitUnorderedList(_ unorderedList: UnorderedList) -> String {
        let content = defaultVisit(unorderedList)
        return "<ul>\(content)</ul>\n"
    }

    mutating func visitListItem(_ listItem: ListItem) -> String {
        if let checkbox = listItem.checkbox {
            // Visit children inline, skipping the <p> wrapper on single-paragraph
            // items so the checkbox character and text appear on the same line.
            let content = listItem.children.map { child -> String in
                if let paragraph = child as? Paragraph {
                    return defaultVisit(paragraph)
                }
                return visit(child)
            }.joined()
            let marker = checkbox == .checked ? "&#x2611;" : "&#x2610;"
            return "<li style=\"list-style: none;\">\(marker) \(content)</li>\n"
        }
        let content = defaultVisit(listItem)
        return "<li>\(content)</li>\n"
    }

    // MARK: - Table Elements

    mutating func visitTable(_ table: Table) -> String {
        columnAlignments = table.columnAlignments
        let content = defaultVisit(table)
        columnAlignments = []
        return "<table>\(content)</table>\n"
    }

    mutating func visitTableHead(_ tableHead: Table.Head) -> String {
        inTableHead = true
        currentColumnIndex = 0
        let content = defaultVisit(tableHead)
        inTableHead = false
        return "<thead>\(content)</thead>\n"
    }

    mutating func visitTableBody(_ tableBody: Table.Body) -> String {
        let content = defaultVisit(tableBody)
        return "<tbody>\(content)</tbody>\n"
    }

    mutating func visitTableRow(_ tableRow: Table.Row) -> String {
        currentColumnIndex = 0
        let content = defaultVisit(tableRow)
        return "<tr>\(content)</tr>\n"
    }

    mutating func visitTableCell(_ tableCell: Table.Cell) -> String {
        let content = defaultVisit(tableCell)
        let tag = inTableHead ? "th" : "td"

        var alignAttr = ""
        if currentColumnIndex < columnAlignments.count,
           let alignment = columnAlignments[currentColumnIndex] {
            switch alignment {
            case .left:
                alignAttr = " style=\"text-align: left;\""
            case .center:
                alignAttr = " style=\"text-align: center;\""
            case .right:
                alignAttr = " style=\"text-align: right;\""
            }
        }
        currentColumnIndex += 1

        return "<\(tag)\(alignAttr)>\(content)</\(tag)>"
    }

    // MARK: - Inline Elements

    mutating func visitText(_ text: Text) -> String {
        return escapeHTML(text.string)
    }

    mutating func visitStrong(_ strong: Strong) -> String {
        let content = defaultVisit(strong)
        return "<strong>\(content)</strong>"
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) -> String {
        let content = defaultVisit(emphasis)
        return "<em>\(content)</em>"
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) -> String {
        let content = defaultVisit(strikethrough)
        return "<del>\(content)</del>"
    }

    mutating func visitLink(_ link: Link) -> String {
        let content = defaultVisit(link)
        let href = link.destination ?? ""
        return "<a href=\"\(escapeHTML(href))\">\(content)</a>"
    }

    mutating func visitImage(_ image: Image) -> String {
        let alt = defaultVisit(image)
        let src = image.source ?? ""
        return "<img src=\"\(escapeHTML(src))\" alt=\"\(escapeHTML(alt))\">"
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) -> String {
        return "<code>\(escapeHTML(inlineCode.code))</code>"
    }

    mutating func visitInlineHTML(_ inlineHTML: InlineHTML) -> String {
        return escapeHTML(inlineHTML.rawHTML)
    }

    mutating func visitSoftBreak(_ softBreak: SoftBreak) -> String {
        return " "
    }

    mutating func visitLineBreak(_ lineBreak: LineBreak) -> String {
        return "<br>"
    }

    // MARK: - HTML Escaping

    private func escapeHTML(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
