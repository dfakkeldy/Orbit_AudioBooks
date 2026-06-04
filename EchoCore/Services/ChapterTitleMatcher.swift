import Foundation

/// Matches audiobook chapter titles (from M4B metadata) to EPUB heading blocks
/// using fuzzy string comparison.
///
/// This serves as **Tier 0** in the alignment pipeline — a zero-cost bootstrap
/// that creates anchors from metadata before any audio transcription runs.
///
/// Many M4B/M4A files embed chapter titles (e.g., "Chapter 1: The Beginning")
/// that directly correspond to `<h1>`–`<h6>` elements in the EPUB. Matching
/// these gives us high-confidence anchors at essentially zero cost, shrinking
/// the search space for the downstream DTW pipeline.
struct ChapterTitleMatcher {

    /// A single title-to-heading match.
    struct Match: Equatable {
        let chapter: Chapter
        let block: EPubBlockRecord
        /// Composite similarity score in [0.0, 1.0].
        let confidence: Double
    }

    /// Confidence thresholds for match quality tiers.
    enum Threshold {
        /// Automatic anchor — skip DTW transcription for this chapter entirely.
        static let highConfidence: Double = 0.85
        /// Create anchor but still run DTW for refinement.
        static let mediumConfidence: Double = 0.60
    }

    // MARK: - Public API

    /// Finds the best-matching EPUB heading for each audiobook chapter title.
    ///
    /// - Parameters:
    ///   - chapters: Audiobook chapters parsed from M4B metadata via
    ///     `ChapterService.parseChapters(from:)`. Only chapters with non-nil,
    ///     non-empty titles are considered.
    ///   - blocks: All EPUB blocks in reading order. Only blocks with
    ///     `blockKind == "heading"` and non-nil `text` are candidates.
    /// - Returns: Matches where confidence ≥ `Threshold.mediumConfidence`,
    ///   sorted by chapter index. Each chapter appears at most once (its best
    ///   heading match). Headings may match multiple chapters if titles are
    ///   similar — the caller should handle that case.
    static func matchChapterTitles(
        chapters: [Chapter],
        blocks: [EPubBlockRecord]
    ) -> [Match] {
        let headingBlocks = blocks.filter {
            $0.blockKind == EPubBlockRecord.Kind.heading.rawValue && $0.text != nil
        }
        guard !headingBlocks.isEmpty else { return [] }

        var matches: [Match] = []

        for chapter in chapters {
            guard let title = chapter.title?.trimmingCharacters(in: .whitespaces),
                  !title.isEmpty else {
                continue
            }

            var best: (block: EPubBlockRecord, confidence: Double)?

            for heading in headingBlocks {
                guard let headingText = heading.text else { continue }
                let confidence = similarity(between: title, and: headingText)
                if confidence > (best?.confidence ?? 0) {
                    best = (heading, confidence)
                }
            }

            if let best, best.confidence >= Threshold.mediumConfidence {
                matches.append(Match(
                    chapter: chapter,
                    block: best.block,
                    confidence: best.confidence
                ))
            }
        }

        return matches.sorted { $0.chapter.index < $1.chapter.index }
    }

    // MARK: - Similarity

    /// Computes a composite similarity score between two title strings.
    ///
    /// Combines character-level Levenshtein distance and token-level Jaccard
    /// overlap, returning the **maximum** of the two — so a match succeeds if
    /// either the full-string edit distance or the bag-of-words overlap is
    /// strong.
    ///
    /// - Returns: A value in [0.0, 1.0] where 1.0 is an exact match.
    static func similarity(between a: String, and b: String) -> Double {
        let normalizedA = normalize(a)
        let normalizedB = normalize(b)

        // Character-level Levenshtein on the full normalized strings.
        let stringConfidence = normalizedA.normalizedLevenshteinSimilarity(to: normalizedB)

        // Short-circuit on near-perfect match — avoids tokenization overhead.
        if stringConfidence >= 0.95 { return stringConfidence }

        // Token-level Jaccard for cases like "Ch 1: The Beginning" vs
        // "Chapter One — The Beginning" where character edit distance is
        // high but the meaningful word overlap is strong.
        let tokensA = tokenize(normalizedA)
        let tokensB = tokenize(normalizedB)

        guard !tokensA.isEmpty, !tokensB.isEmpty else {
            return stringConfidence
        }

        let setA = Set(tokensA)
        let setB = Set(tokensB)
        let intersection = setA.intersection(setB).count
        let union = setA.union(setB).count
        let wordConfidence = union > 0 ? Double(intersection) / Double(union) : 0.0

        return max(stringConfidence, wordConfidence)
    }

    // MARK: - Private Helpers

    private static let nonLetters = CharacterSet.letters.inverted

    /// Lowercase, collapse whitespace, trim.
    private static func normalize(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Split into lowercase word tokens of 2+ letters for Jaccard comparison.
    private static func tokenize(_ text: String) -> [String] {
        text.components(separatedBy: nonLetters)
            .filter { $0.count >= 2 }
    }
}
