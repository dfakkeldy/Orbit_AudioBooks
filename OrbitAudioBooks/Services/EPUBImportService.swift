import Foundation

// MARK: - Import Error

enum EPUBImportError: Error, LocalizedError {
    case notAnEPUB(path: String)
    case missingOPF
    case missingSpineItem(String)
    case parseError(String)
    case fileWriteError(Error)
    case databaseError(Error)

    var errorDescription: String? {
        switch self {
        case .notAnEPUB(let path): return "Not a valid EPUB: \(path)"
        case .missingOPF: return "content.opf not found in EPUB"
        case .missingSpineItem(let href): return "Spine item not found: \(href)"
        case .parseError(let detail): return "Parse error: \(detail)"
        case .fileWriteError(let e): return "File write failed: \(e.localizedDescription)"
        case .databaseError(let e): return "Database error: \(e.localizedDescription)"
        }
    }
}

// MARK: - Import Result

struct EPUBImportResult {
    let audiobookID: String
    let blockCount: Int
    let imageCount: Int
}

// MARK: - EPUB Import Service

/// Imports an EPUB into the app's storage, parsing XHTML spine items into
/// ordered blocks and copying images to local asset paths.
///
/// The import expects an already-extracted EPUB directory. Use ZIPFoundation
/// or a similar library to extract the EPUB ZIP archive before calling this
/// service. The extracted directory should contain:
/// - META-INF/container.xml (points to the OPF)
/// - The OPF file (usually OEBPS/content.opf)
/// - XHTML spine items referenced by the OPF
struct EPUBImportService {

    /// Application Support subdirectory for EPUB assets.
    static func epubAssetsRoot() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil, create: true
        )
        return appSupport.appendingPathComponent("EPUBAssets", isDirectory: true)
    }

    static func epubAssetsDir(audiobookID: String) throws -> URL {
        let safeID = SafeFileName.fromAudiobookID(audiobookID)
        let dir = try epubAssetsRoot().appendingPathComponent(safeID, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    let db: DatabaseWriter

    // MARK: - Public API

    func `import`(epubDir: URL, audiobookID: String) async throws -> EPUBImportResult {
        // 1. Locate and parse OPF
        let opfURL = try locateOPF(in: epubDir)
        let opf = try parseOPF(at: opfURL)

        // 2. Walk spine, parsing XHTML into ordered blocks
        let opfBase = opfURL.deletingLastPathComponent()
        var blocks: [EPubBlockRecord] = []
        var sequenceIndex = 0
        var imageCount = 0

        let assetsDir = try Self.epubAssetsDir(audiobookID: audiobookID)

        for (spineIndex, itemref) in opf.items.enumerated() {
            guard let manifestItem = opf.manifest[itemref.idref] else {
                throw EPUBImportError.missingSpineItem(itemref.idref)
            }
            let xhtmlURL = opfBase.appendingPathComponent(manifestItem.href)
            let xhtmlBlocks = try parseXHTML(
                at: xhtmlURL,
                audiobookID: audiobookID,
                spineHref: manifestItem.href,
                spineIndex: spineIndex,
                startSequence: &sequenceIndex,
                assetsDir: assetsDir,
                opfBase: opfBase
            )
            blocks.append(contentsOf: xhtmlBlocks)
            imageCount += xhtmlBlocks.filter { $0.blockKind == "image" }.count
        }

        // 3. Persist blocks to SQL
        let dao = EPubBlockDAO(db: db)
        try dao.deleteAll(for: audiobookID)
        try dao.insertAll(blocks, audiobookID: audiobookID)

        return EPUBImportResult(
            audiobookID: audiobookID,
            blockCount: blocks.count,
            imageCount: imageCount
        )
    }

    // MARK: - OPF Location

    private func locateOPF(in epubDir: URL) throws -> URL {
        let containerURL = epubDir.appendingPathComponent("META-INF/container.xml")
        guard FileManager.default.fileExists(atPath: containerURL.path) else {
            throw EPUBImportError.missingOPF
        }
        let data = try Data(contentsOf: containerURL)
        let parser = ContainerXMLParser()
        let opfPath = try parser.parseOPFPath(from: data)

        let opfURL = epubDir.appendingPathComponent(opfPath)
        guard FileManager.default.fileExists(atPath: opfURL.path) else {
            throw EPUBImportError.missingOPF
        }
        return opfURL
    }

    // MARK: - OPF Parsing

    private struct OPFManifestItem {
        let id: String
        let href: String
        let mediaType: String
    }

    private struct OPFSpineItem {
        let idref: String
    }

    private struct OPF {
        let manifest: [String: OPFManifestItem]
        let items: [OPFSpineItem]
    }

    private func parseOPF(at url: URL) throws -> OPF {
        let data = try Data(contentsOf: url)
        let parser = OPFContentParser()
        return try parser.parse(data: data)
    }

    // MARK: - XHTML Parsing

    private func parseXHTML(
        at url: URL,
        audiobookID: String,
        spineHref: String,
        spineIndex: Int,
        startSequence: inout Int,
        assetsDir: URL,
        opfBase: URL
    ) throws -> [EPubBlockRecord] {
        let data = try Data(contentsOf: url)
        let parser = XHTMLBlockParser(
            audiobookID: audiobookID,
            spineHref: spineHref,
            spineIndex: spineIndex,
            startSequence: &startSequence,
            assetsDir: assetsDir,
            opfBase: opfBase
        )
        return try parser.parse(data: data)
    }
}

// MARK: - Container XML Parser

private final class ContainerXMLParser: NSObject, XMLParserDelegate {
    private var opfPath: String?
    private var isInRootfile = false
    private var error: Error?

    func parseOPFPath(from data: Data) throws -> String {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        if let error { throw error }
        guard let path = opfPath else { throw EPUBImportError.missingOPF }
        return path
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        if elementName == "rootfile" {
            opfPath = attributes["full-path"]
        }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        error = parseError
    }
}

// MARK: - OPF Content Parser

private final class OPFContentParser: NSObject, XMLParserDelegate {
    private enum Element: String {
        case item, itemref
    }

    private var manifest: [String: EPUBImportService.OPFManifestItem] = [:]
    private var spineItems: [EPUBImportService.OPFSpineItem] = []
    private var error: Error?

    func parse(data: Data) throws -> EPUBImportService.OPF {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        if let error { throw error }
        return EPUBImportService.OPF(manifest: manifest, items: spineItems)
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        switch elementName {
        case "item":
            if let id = attributes["id"],
               let href = attributes["href"] {
                let mediaType = attributes["media-type"] ?? ""
                manifest[id] = EPUBImportService.OPFManifestItem(id: id, href: href, mediaType: mediaType)
            }
        case "itemref":
            if let idref = attributes["idref"] {
                spineItems.append(EPUBImportService.OPFSpineItem(idref: idref))
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        error = parseError
    }
}

// MARK: - XHTML Block Parser

private final class XHTMLBlockParser: NSObject, XMLParserDelegate {
    let audiobookID: String
    let spineHref: String
    let spineIndex: Int
    var startSequence: UnsafeMutablePointer<Int>
    let assetsDir: URL
    let opfBase: URL

    private var blocks: [EPubBlockRecord] = []
    private var currentText = ""
    private var currentElement = ""
    private var blockIndex = 0
    private var currentImageSrc: String?
    private var error: Error?
    private var isInBody = false
    private var depth = 0

    private let headingTags: Set<String> = ["h1", "h2", "h3", "h4", "h5", "h6"]
    private let blockTags: Set<String> = ["p", "div", "li", "td", "th", "blockquote", "pre"]
    private let imageTags: Set<String> = ["img", "image"]

    init(audiobookID: String, spineHref: String, spineIndex: Int, startSequence: UnsafeMutablePointer<Int>, assetsDir: URL, opfBase: URL) {
        self.audiobookID = audiobookID
        self.spineHref = spineHref
        self.spineIndex = spineIndex
        self.startSequence = startSequence
        self.assetsDir = assetsDir
        self.opfBase = opfBase
    }

    func parse(data: Data) throws -> [EPubBlockRecord] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldProcessNamespaces = true
        parser.parse()
        flushTextBlock()
        if let error { throw error }
        return blocks
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        depth += 1
        let tag = elementName.lowercased()

        if tag == "body" { isInBody = true }
        guard isInBody else { return }

        // Flush accumulated text before starting a new block element
        if headingTags.contains(tag) || blockTags.contains(tag) || imageTags.contains(tag) {
            flushTextBlock()
        }

        if headingTags.contains(tag) {
            currentElement = tag
        } else if blockTags.contains(tag) {
            currentElement = tag
        } else if imageTags.contains(tag) {
            currentImageSrc = attributes["src"] ?? attributes["xlink:href"]
            if let src = currentImageSrc {
                let localPath = copyImage(src: src)
                let seq = startSequence.pointee
                startSequence.pointee += 1
                let block = EPubBlockRecord(
                    id: "epub-\(audiobookID)-\(seq)",
                    audiobookID: audiobookID,
                    spineHref: spineHref,
                    spineIndex: spineIndex,
                    blockIndex: blockIndex,
                    sequenceIndex: seq,
                    blockKind: "image",
                    text: nil,
                    imagePath: localPath,
                    chapterIndex: nil,
                    isHidden: false,
                    hiddenReason: nil,
                    createdAt: Date().ISO8601Format(),
                    modifiedAt: nil
                )
                blocks.append(block)
                blockIndex += 1
            }
            currentImageSrc = nil
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        depth -= 1
        let tag = elementName.lowercased()
        guard isInBody else {
            if tag == "body" { isInBody = false }
            return
        }

        if headingTags.contains(tag) || blockTags.contains(tag) {
            flushTextBlock()
            currentElement = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard isInBody else { return }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            // Preserve space between words
            if currentText.last != " " { currentText += " " }
            return
        }
        currentText += trimmed + " "
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        let nsErr = parseError as NSError
        // XMLParser reports non-fatal errors for common HTML quirks;
        // only treat truly fatal codes as errors.
        if nsErr.domain == "NSXMLParserErrorDomain" && nsErr.code <= 2 {
            error = parseError
        }
    }

    private func flushTextBlock() {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        currentText = ""
        guard !text.isEmpty else { return }

        let seq = startSequence.pointee
        startSequence.pointee += 1

        let kind: String
        if headingTags.contains(currentElement) {
            kind = "heading"
        } else {
            kind = "paragraph"
        }

        let block = EPubBlockRecord(
            id: "epub-\(audiobookID)-\(seq)",
            audiobookID: audiobookID,
            spineHref: spineHref,
            spineIndex: spineIndex,
            blockIndex: blockIndex,
            sequenceIndex: seq,
            blockKind: kind,
            text: text,
            imagePath: nil,
            chapterIndex: nil,
            isHidden: false,
            hiddenReason: nil,
            createdAt: Date().ISO8601Format(),
            modifiedAt: nil
        )
        blocks.append(block)
        blockIndex += 1
    }

    // MARK: - Image Copying

    /// Copies an EPUB image to the local assets directory.
    /// Returns the destination file path usable by UIImage(contentsOfFile:).
    private func copyImage(src: String) -> String? {
        // Resolve relative paths against the OPF base
        let imageURL: URL
        if src.hasPrefix("/") {
            imageURL = URL(fileURLWithPath: src)
        } else {
            imageURL = opfBase.appendingPathComponent(src)
        }

        guard FileManager.default.fileExists(atPath: imageURL.path) else { return nil }

        let safeFilename = SafeFileName.fromAudiobookID(src)
        let ext = imageURL.pathExtension.isEmpty ? "jpg" : imageURL.pathExtension
        let destURL = assetsDir.appendingPathComponent("\(safeFilename).\(ext)")

        // Skip if already copied
        if FileManager.default.fileExists(atPath: destURL.path) {
            return destURL.path
        }

        do {
            try FileManager.default.copyItem(at: imageURL, to: destURL)
            return destURL.path
        } catch {
            // Best-effort image copying — return nil on failure
            return nil
        }
    }
}
