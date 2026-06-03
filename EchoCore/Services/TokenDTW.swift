import Foundation

struct TokenDTW {
    struct EPubToken {
        let text: String
        let blockID: String
    }
    
    struct AudioToken {
        let text: String
        let time: TimeInterval
    }
    
    static func align(epub: [EPubToken], audio: [AudioToken]) -> [String: TimeInterval] {
        let n = epub.count
        let m = audio.count
        
        guard n > 0, m > 0 else { return [:] }
        
        // Cost matrix. We only need two rows for space optimization, but to reconstruct the path
        // we need the full matrix of directions.
        // For 3000x3000 = 9M elements. Using a flat array of Int8 for direction to save memory.
        // 0: match/sub, 1: insert, 2: delete
        var cost = Array(repeating: Int32.max / 2, count: (n + 1) * (m + 1))
        var dir = Array(repeating: Int8(0), count: (n + 1) * (m + 1))
        
        cost[0] = 0 // (0, 0)

        // Initialize boundary row (deletion of EPUB tokens) and column
        // (insertion of audio tokens) with cumulative gap costs so the DP
        // can skip leading tokens that have no match in the other sequence.
        for i in 1...n {
            cost[i * (m + 1) + 0] = Int32(i) * 2
        }
        for j in 1...m {
            cost[0 * (m + 1) + j] = Int32(j) * 2
        }

        for i in 1...n {
            for j in 1...m {
                let eToken = epub[i - 1].text
                let aToken = audio[j - 1].text
                
                // Levenshtein-like distance between words, or just strict equality
                // Fast path: exact match
                let matchCost: Int32
                if eToken == aToken {
                    matchCost = 0
                } else if eToken.hasPrefix(aToken) || aToken.hasPrefix(eToken) {
                    matchCost = 1
                } else {
                    matchCost = 2 // Substitution cost
                }
                
                let sub = cost[(i - 1) * (m + 1) + (j - 1)] + matchCost
                let ins = cost[i * (m + 1) + (j - 1)] + 2 // Insertion in audio (skip audio token)
                let del = cost[(i - 1) * (m + 1) + j] + 2 // Deletion in epub (skip epub token)
                
                let idx = i * (m + 1) + j
                if sub <= ins && sub <= del {
                    cost[idx] = sub
                    dir[idx] = 0
                } else if ins <= del {
                    cost[idx] = ins
                    dir[idx] = 1
                } else {
                    cost[idx] = del
                    dir[idx] = 2
                }
            }
        }
        
        // Backtrack
        var i = n
        var j = m
        
        var blockStartTimes: [String: [TimeInterval]] = [:]
        
        while i > 0 && j > 0 {
            let idx = i * (m + 1) + j
            let d = dir[idx]
            if d == 0 {
                // match/sub
                let blockID = epub[i - 1].blockID
                let time = audio[j - 1].time
                if blockStartTimes[blockID] == nil {
                    blockStartTimes[blockID] = []
                }
                blockStartTimes[blockID]?.append(time)
                i -= 1
                j -= 1
            } else if d == 1 {
                // insert
                j -= 1
            } else {
                // delete
                i -= 1
            }
        }
        
        // The path was reconstructed backwards, so the last appended time is the FIRST word's time!
        var result: [String: TimeInterval] = [:]
        for (blockID, times) in blockStartTimes {
            if let firstWordTime = times.last {
                result[blockID] = firstWordTime
            }
        }
        
        return result
    }
    
    static func normalize(_ text: String) -> [String] {
        let nonLetters = CharacterSet.letters.inverted
        return text.lowercased()
            .components(separatedBy: nonLetters)
            .filter { $0.count >= 2 }
    }
}
