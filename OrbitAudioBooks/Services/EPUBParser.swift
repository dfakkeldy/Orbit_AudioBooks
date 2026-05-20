import Foundation

// MARK: - Parse Result

/// The result of parsing an EPUB into ordered blocks.
struct EPUBParseResult {
    let blocks: [EpubBlockRecord]
    let imagePaths: [String] // source paths (absolute or relative to EPUB root)
}

// MARK: - Parser Protocol

/// Parses an EPUB into ordered blocks. Implementations handle the actual
/// extraction and parsing strategy (ZIP-based, directory-based, etc.).
protocol EPUBParserProtocol {
    /// Parse an EPUB at the given URL and return ordered blocks + image paths.
    func parse(epubURL: URL, audiobookID: String) throws -> EPUBParseResult
}

// MARK: - Directory-Based Parser (V1)

/// Parses an already-extracted EPUB directory. EPUBs are ZIP archives;
/// users can extract them manually (e.g. via Files app) for V1 import.
///
/// Expects a directory containing `META-INF/container.xml` and XHTML files
/// referenced by the OPF manifest.
///
/// Uses `Foundation.XMLParser` (SAX-style, available on iOS).
struct DirectoryEPUBParser: EPUBParserProtocol {
    func parse(epubURL: URL, audiobookID: String) throws -> EPUBParseResult {
        // Step 1: Parse container.xml to find OPF path
        let containerURL = epubURL.appendingPathComponent("META-INF/container.xml")
        let opfPath = try parseContainerXML(at: containerURL)
        let opfURL = epubURL.appendingPathComponent(opfPath)

        // Step 2: Parse OPF for spine order and manifest
        let spine = try parseOPF(at: opfURL)

        // Step 3: Parse each spine item into blocks
        var blocks: [EpubBlockRecord] = []
        var imagePaths: [String] = []
        var globalSeq = 0

        for (spineIdx, item) in spine.enumerated() {
            let href = item.href
            let itemURL = opfURL
                .deletingLastPathComponent()
                .appendingPathComponent(href)

            guard FileManager.default.fileExists(atPath: itemURL.path) else {
                continue
            }

            let itemBlocks = try parseXHTML(
                at: itemURL,
                audiobookID: audiobookID,
                spineHref: href,
                spineIndex: spineIdx,
                chapterIndex: item.chapterIndex,
                startingSequence: &globalSeq
            )
            blocks.append(contentsOf: itemBlocks)

            for block in itemBlocks where block.blockKind == "image" {
                if let imgPath = block.imagePath {
                    imagePaths.append(imgPath)
                }
            }
        }

        return EPUBParseResult(blocks: blocks, imagePaths: imagePaths)
    }

    // MARK: - Container XML Parsing

    private func parseContainerXML(at url: URL) throws -> String {
        let parser = ContainerXMLParser()
        let data = try Data(contentsOf: url)
        parser.parse(data)
        guard let opfPath = parser.rootfileFullPath else {
            throw EPUBParserError.missingOPFPath
        }
        return opfPath
    }

    // MARK: - OPF Parsing

    private func parseOPF(at url: URL) throws -> [SpineItem] {
        let parser = OPFParserDelegate()
        let data = try Data(contentsOf: url)
        parser.parse(data)
        return parser.spineItems
    }

    // MARK: - XHTML Parsing

    private func parseXHTML(
        at url: URL,
        audiobookID: String,
        spineHref: String,
        spineIndex: Int,
        chapterIndex: Int?,
        startingSequence: inout Int
    ) throws -> [EpubBlockRecord] {
        let parser = XHTMLBlockParser(
            audiobookID: audiobookID,
            spineHref: spineHref,
            spineIndex: spineIndex,
            chapterIndex: chapterIndex,
            startSequence: startingSequence
        )
        let data = try Data(contentsOf: url)
        parser.parse(data)
        startingSequence = parser.nextSequence
        return parser.blocks
    }
}

// MARK: - XMLParser Delegates

private struct SpineItem {
    let href: String
    let chapterIndex: Int?
}

private let blockTagSet: Set<String> = [
    "h1", "h2", "h3", "h4", "h5", "h6", "p", "div",
    "img", "blockquote", "pre", "li", "figcaption"
]

private final class ContainerXMLParser: NSObject, XMLParserDelegate {
    var rootfileFullPath: String?
    private var inRootfile = false

    func parse(_ data: Data) {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        if elementName == "rootfile" {
            inRootfile = true
            rootfileFullPath = attributes["full-path"]
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        if elementName == "rootfile" { inRootfile = false }
    }
}

private final class OPFParserDelegate: NSObject, XMLParserDelegate {
    private var manifest: [String: String] = [:]
    private var spineOrder: [String] = []
    private var inManifest = false
    private var inSpine = false
    var spineItems: [SpineItem] = []

    func parse(_ data: Data) {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        switch elementName {
        case "manifest":
            inManifest = true
        case "spine":
            inSpine = true
        case "item" where inManifest:
            if let id = attributes["id"], let href = attributes["href"] {
                manifest[id] = href
            }
        case "itemref" where inSpine:
            if let idref = attributes["idref"] {
                let linear = attributes["linear"]
                if linear != "no" {
                    spineOrder.append(idref)
                }
            }
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        if elementName == "manifest" { inManifest = false }
        if elementName == "spine" {
            inSpine = false
            // Build spine items from order
            for (i, idref) in spineOrder.enumerated() {
                if let href = manifest[idref] {
                    spineItems.append(SpineItem(href: href, chapterIndex: i))
                }
            }
        }
    }
}

private final class XHTMLBlockParser: NSObject, XMLParserDelegate {
    let audiobookID: String
    let spineHref: String
    let spineIndex: Int
    let chapterIndex: Int?
    private var seq: Int
    private var blockIdx: Int
    private(set) var blocks: [EpubBlockRecord] = []
    var nextSequence: Int { seq }
    private var currentElementName: String?
    private var currentText = ""
    private var currentAttributes: [String: String] = [:]
    private var depth = 0
    private var inBody = false
    private var skipDepth = 0

    init(audiobookID: String, spineHref: String, spineIndex: Int,
         chapterIndex: Int?, startSequence: Int) {
        self.audiobookID = audiobookID
        self.spineHref = spineHref
        self.spineIndex = spineIndex
        self.chapterIndex = chapterIndex
        self.seq = startSequence
        self.blockIdx = startSequence
    }

    func parse(_ data: Data) {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        // Skip non-body content
        if elementName.lowercased() == "body" {
            inBody = true
            return
        }
        guard inBody else { return }

        // Skip script, style, head
        if ["script", "style", "head"].contains(elementName.lowercased()) {
            skipDepth = depth
        }

        if skipDepth > 0 { depth += 1; return }

        currentElementName = elementName.lowercased()
        currentAttributes = attributes
        currentText = ""
        depth += 1
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard inBody, skipDepth == 0 else { return }
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        if elementName.lowercased() == "body" {
            inBody = false
            return
        }
        guard inBody else { return }

        if skipDepth > 0 {
            depth -= 1
            if depth <= skipDepth { skipDepth = 0 }
            return
        }

        depth -= 1
        let name = elementName.lowercased()

        if blockTagSet.contains(name) {
            let trimmed = currentText
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

            let kind: String
            let text: String?
            let imgPath: String?

            if name.hasPrefix("h") {
                kind = "heading"
                text = trimmed.isEmpty ? nil : trimmed
                imgPath = nil
            } else if name == "img" {
                kind = "image"
                imgPath = currentAttributes["src"]
                text = currentAttributes["alt"] ?? imgPath ?? "Image"
            } else {
                kind = "paragraph"
                text = trimmed.isEmpty ? nil : trimmed
                imgPath = nil
            }

            let block = EpubBlockRecord(
                id: "epub-\(audiobookID)-\(spineIndex)-\(blockIdx)",
                audiobookID: audiobookID,
                spineHref: spineHref,
                spineIndex: spineIndex,
                blockIndex: blockIdx,
                sequenceIndex: seq,
                blockKind: kind,
                text: text,
                imagePath: imgPath,
                chapterIndex: chapterIndex,
                isHidden: false,
                hiddenReason: nil,
                createdAt: nil,
                modifiedAt: nil
            )
            blocks.append(block)
            blockIdx += 1
            seq += 1
        }

        currentElementName = nil
        currentAttributes = [:]
    }
}

// MARK: - Errors

enum EPUBParserError: LocalizedError {
    case invalidContainerXML
    case missingOPFPath
    case invalidOPF
    case notAnEPUBDirectory

    var errorDescription: String? {
        switch self {
        case .invalidContainerXML: "Invalid META-INF/container.xml"
        case .missingOPFPath: "Could not find OPF path in container.xml"
        case .invalidOPF: "Invalid content.opf"
        case .notAnEPUBDirectory: "Directory does not contain a valid EPUB structure"
        }
    }
}
