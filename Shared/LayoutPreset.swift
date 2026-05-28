import Foundation

public struct WatchPreset: Codable, Identifiable, Hashable {
    public let id: UUID
    public var name: String
    public var page1: [WatchAction]
    public var page2: [WatchAction]

    public init(id: UUID = UUID(), name: String, page1: [WatchAction], page2: [WatchAction]) {
        self.id = id
        self.name = name
        self.page1 = page1
        self.page2 = page2
    }
}

public struct PhonePreset: Codable, Identifiable, Hashable {
    public let id: UUID
    public var name: String
    public var slots: [WatchAction]

    public init(id: UUID = UUID(), name: String, slots: [WatchAction]) {
        self.id = id
        self.name = name
        self.slots = slots
    }
}
