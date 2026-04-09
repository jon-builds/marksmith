import AppKit

struct ClipboardWriter {

    private let pasteboard = NSPasteboard.general

    func write(plainText: String, html: String, rtf: Data?) {
        pasteboard.clearContents()

        // Use declareTypes instead of NSPasteboardItem — Pages and some Apple
        // apps ignore RTF/HTML written via NSPasteboardItem.
        // Order matters: first type is "most preferred". RTF must come before
        // plain text so Pages/Word prefer rich text over raw markdown.
        var types: [NSPasteboard.PasteboardType] = [.html]
        if rtf != nil { types.insert(.rtf, at: 0) }
        types.append(contentsOf: [.string, .markdownPasteMarker])
        pasteboard.declareTypes(types, owner: nil)

        pasteboard.setString(plainText, forType: .string)
        pasteboard.setString(html, forType: .html)

        if let rtfData = rtf {
            pasteboard.setData(rtfData, forType: .rtf)
        }

        // Always set marker to prevent re-processing our own writes
        pasteboard.setString("1", forType: .markdownPasteMarker)
    }
}
