import Foundation
import CloudKit
import GRDB
import os.log

@MainActor
final class CloudKitSyncService {
    private let logger = Logger(subsystem: "com.orbitaudiobooks", category: "CloudKitSyncService")
    private let container = CKContainer(identifier: "iCloud.com.orbitaudiobooks")
    private var publicDatabase: CKDatabase { container.publicCloudDatabase }
    
    // Dependencies
    private let db: DatabaseWriter
    
    init(db: DatabaseWriter) {
        self.db = db
    }
    
    /// Uploads manual alignment anchors for a specific audiobook to the public CloudKit database.
    func uploadAnchors(audiobookID: String, title: String, author: String, duration: Double) async throws {
        // Fetch anchors
        let anchors = try await db.read { db in
            try AlignmentAnchorRecord.filter(Column("audiobook_id") == audiobookID)
                .fetchAll(db)
        }
        
        guard !anchors.isEmpty else {
            logger.info("No anchors to upload for \(title).")
            return
        }
        
        let encoder = JSONEncoder()
        let payloadData = try encoder.encode(anchors)
        guard let payloadString = String(data: payloadData, encoding: .utf8) else {
            throw NSError(domain: "CloudKitSync", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to encode anchors"])
        }
        
        // Fingerprint id
        let recordID = CKRecord.ID(recordName: "\(title.hashValue)-\(author.hashValue)-\(Int(duration))")
        let record = CKRecord(recordType: "SharedAlignment", recordID: recordID)
        
        record["audiobookTitle"] = title as CKRecordValue
        record["audiobookAuthor"] = author as CKRecordValue
        record["audioDuration"] = duration as CKRecordValue
        record["anchorsPayload"] = payloadString as CKRecordValue
        
        do {
            _ = try await publicDatabase.save(record)
            logger.info("Successfully uploaded \(anchors.count) anchors for \(title).")
        } catch let error as CKError where error.code == .serverRecordChanged {
            // Already exists, could merge or overwrite. For now, overwrite.
            let existingRecord = try await publicDatabase.record(for: recordID)
            existingRecord["anchorsPayload"] = payloadString as CKRecordValue
            _ = try await publicDatabase.save(existingRecord)
            logger.info("Successfully updated \(anchors.count) anchors for \(title).")
        } catch {
            logger.error("Failed to upload anchors: \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Downloads alignment anchors from the public CloudKit database if a match is found.
    func downloadAnchors(audiobookID: String, title: String, author: String, duration: Double) async throws -> [AlignmentAnchorRecord] {
        let predicate = NSPredicate(format: "audiobookTitle == %@ AND audiobookAuthor == %@ AND audioDuration == %f", title, author, duration)
        let query = CKQuery(recordType: "SharedAlignment", predicate: predicate)
        
        let (matchResults, _) = try await publicDatabase.records(matching: query, resultsLimit: 1)
        
        guard let firstMatch = matchResults.first else {
            logger.info("No shared alignment found for \(title).")
            return []
        }
        
        switch firstMatch.1 {
        case .success(let record):
            guard let payloadString = record["anchorsPayload"] as? String,
                  let payloadData = payloadString.data(using: .utf8) else {
                return []
            }
            
            let decoder = JSONDecoder()
            let anchors = try decoder.decode([AlignmentAnchorRecord].self, from: payloadData)
            
            // Map the downloaded anchors to this specific local audiobookID
            let localizedAnchors = anchors.map { anchor in
                var updated = anchor
                updated.audiobookID = audiobookID
                updated.source = AlignmentAnchorRecord.Source.imported.rawValue
                return updated
            }
            
            logger.info("Successfully downloaded \(localizedAnchors.count) anchors for \(title).")
            return localizedAnchors
            
        case .failure(let error):
            logger.error("Failed to fetch record: \(error.localizedDescription)")
            throw error
        }
    }
}
