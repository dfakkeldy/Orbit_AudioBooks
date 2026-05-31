import Foundation
import os.log

struct EPubTextExtraction {
    let id: String
    let text: String
}

struct MacEPUBParser {
    private let logger = Logger(subsystem: "com.orbitaudiobooks", category: "MacEPUBParser")
    
    /// Extracts text blocks from an EPUB file (or directory).
    /// Does not interact with SQL. Returns an array of text structures.
    func extractText(from epubURL: URL) throws -> [EPubTextExtraction] {
        var unzippedURL = epubURL
        var needsCleanup = false
        
        if epubURL.pathExtension.lowercased() == "epub" {
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            process.arguments = ["-q", epubURL.path, "-d", tempDir.path]
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus != 0 {
                throw NSError(domain: "MacEPUBParser", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to unzip EPUB (code \(process.terminationStatus))"])
            }
            
            unzippedURL = tempDir
            needsCleanup = true
        }
        
        defer {
            if needsCleanup {
                try? FileManager.default.removeItem(at: unzippedURL)
            }
        }
        
        let containerURL = unzippedURL.appendingPathComponent("META-INF/container.xml")
        guard FileManager.default.fileExists(atPath: containerURL.path) else {
            throw NSError(domain: "MacEPUBParser", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not a valid EPUB: missing container.xml"])
        }
        
        let opfRelativePath = try parseContainerXML(at: containerURL)
        let opfURL = unzippedURL.appendingPathComponent(opfRelativePath)
        let opfDir = opfURL.deletingLastPathComponent()
        let spine = try parseOPF(at: opfURL)
        
        var extractions: [EPubTextExtraction] = []
        var blockCount = 0
        
        for (spineIdx, item) in spine.enumerated() {
            let href = item.href
            let xhtmlURL: URL
            if href.hasPrefix("/") || href.contains("://") {
                xhtmlURL = unzippedURL.appendingPathComponent(href)
            } else {
                xhtmlURL = opfDir.appendingPathComponent(href)
            }
            
            guard FileManager.default.fileExists(atPath: xhtmlURL.path) else { continue }
            let xhtmlData = try Data(contentsOf: xhtmlURL)
            let blocks = try parseXHTML(data: xhtmlData, spineIndex: spineIdx)
            
            for blockText in blocks {
                let id = "epub-mac-s\(spineIdx)-b\(blockCount)"
                extractions.append(EPubTextExtraction(id: id, text: blockText))
                blockCount += 1
            }
        }
        
        return extractions
    }
    
    // MARK: - XML Parsing (Simplified)
    
    private func parseContainerXML(at url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let parser = ContainerXMLParser()
        parser.parse(data)
        guard let path = parser.rootfilePath else {
            throw NSError(domain: "MacEPUBParser", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing OPF path"])
        }
        return path
    }
    
    private func parseOPF(at url: URL) throws -> [SpineItemDescriptor] {
        let data = try Data(contentsOf: url)
        let parser = OPFParserDelegate()
        parser.parse(data)
        return parser.spineItems
    }
    
    private func parseXHTML(data: Data, spineIndex: Int) throws -> [String] {
        let parser = XHTMLBlockDelegate()
        parser.parse(data)
        return parser.texts
    }
}

// MARK: - XML Delegates

private struct SpineItemDescriptor {
    let id: String
    let href: String
    let mediaType: String
}

private final class ContainerXMLParser: NSObject, XMLParserDelegate {
    var rootfilePath: String?
    func parse(_ data: Data) {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
    }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if elementName == "rootfile", let path = attributeDict["full-path"] {
            rootfilePath = path
        }
    }
}

private final class OPFParserDelegate: NSObject, XMLParserDelegate {
    var spineItems: [SpineItemDescriptor] = []
    private var manifestItems: [String: SpineItemDescriptor] = [:]
    private var spineIDRefs: [String] = []
    private var currentAttributes: [String: String] = [:]
    
    func parse(_ data: Data) {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldProcessNamespaces = true
        parser.parse()
    }
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentAttributes = attributeDict
        if elementName == "itemref", let idref = attributeDict["idref"] {
            spineIDRefs.append(idref)
        }
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "item", let id = currentAttributes["id"], let href = currentAttributes["href"], let mediaType = currentAttributes["media-type"] {
            manifestItems[id] = SpineItemDescriptor(id: id, href: href, mediaType: mediaType)
        }
    }
    
    func parserDidEndDocument(_ parser: XMLParser) {
        spineItems = spineIDRefs.compactMap { manifestItems[$0] }
    }
}

private final class XHTMLBlockDelegate: NSObject, XMLParserDelegate {
    var texts: [String] = []
    private var currentText = ""
    private var isInBlock = false
    private var skipDepth = 0
    private let skipTags: Set<String> = ["script", "style", "head", "figcaption"]
    private let blockTags: Set<String> = ["p", "div", "h1", "h2", "h3", "h4", "h5", "h6", "blockquote", "li", "section"]
    
    func parse(_ data: Data) {
        let parser = XMLParser(data: data)
        parser.delegate = self
        currentText = ""
        parser.parse()
        flushBlock()
    }
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes attributeDict: [String: String] = [:]) {
        if skipTags.contains(elementName) { skipDepth += 1; return }
        guard skipDepth == 0 else { return }
        
        if ["h1", "h2", "h3", "h4", "h5", "h6"].contains(elementName) || blockTags.contains(elementName) {
            flushBlock()
            isInBlock = true
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard skipDepth == 0 else { return }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { currentText += trimmed + " " }
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        if skipTags.contains(elementName) { skipDepth = max(0, skipDepth - 1); return }
        guard skipDepth == 0 else { return }
        
        if ["h1", "h2", "h3", "h4", "h5", "h6"].contains(elementName) || blockTags.contains(elementName) {
            flushBlock()
            isInBlock = false
        }
    }
    
    private func flushBlock() {
        let text = currentText.trimmingCharacters(in: .whitespaces)
        currentText = ""
        if !text.isEmpty {
            texts.append(text)
        }
    }
}