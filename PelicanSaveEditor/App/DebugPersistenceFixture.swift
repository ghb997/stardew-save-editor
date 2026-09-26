#if DEBUG
import Foundation

/// Each persistence UI test owns a UUID namespace, separate from real copies and backups.
enum DebugPersistenceFixture {
    static var root: URL? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--ui-library"), args.indices.contains(index + 1),
              let id = UUID(uuidString: args[index + 1]),
              let support = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                       appropriateFor: nil, create: true) else { return nil }
        return support.appendingPathComponent("PersistenceUITests/\(id.uuidString)", isDirectory: true)
    }
    static var worker: SaveWorkService? {
        guard let root else { return nil }
        return SaveWorkService(backupRootURL: root.appendingPathComponent("Backups"),
            transactionDirectoryURL: root.appendingPathComponent("Transactions"), localRootURL: root.appendingPathComponent("ImportedSaves"))
    }
    static func seedURLs() throws -> [URL] {
        guard let root else { throw SaveValidationError.invalid("Missing UI test namespace") }
        let directory = root.appendingPathComponent("Game/Farmer_123", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let player = """
        <name>TestFarmer</name><farmName>TestFarm</farmName><favoriteThing>Tea</favoriteThing>
        <uniqueMultiplayerID>42</uniqueMultiplayerID><money>100</money><maxHealth>100</maxHealth><maxStamina>270</maxStamina>
        <yearForSaveGame>1</yearForSaveGame><seasonForSaveGame>0</seasonForSaveGame><dayOfMonthForSaveGame>1</dayOfMonthForSaveGame>
        <items/><maxItems>12</maxItems><Gender>Male</Gender><hair>0</hair><skin>0</skin><accessory>-1</accessory>
        """
        let urls = [directory.appendingPathComponent("Farmer_123"), directory.appendingPathComponent("SaveGameInfo")]
        try Data("<SaveGame><gameVersion>1.6.15</gameVersion><player>\(player)</player><year>1</year><currentSeason>spring</currentSeason><dayOfMonth>1</dayOfMonth><locations/></SaveGame>".utf8).write(to: urls[0])
        try Data("<Farmer>\(player)</Farmer>".utf8).write(to: urls[1])
        return urls
    }
}
#endif
