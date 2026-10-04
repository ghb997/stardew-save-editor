#if DEBUG
import Foundation

/// Each persistence UI test owns a UUID namespace, separate from real copies and backups.
enum DebugPersistenceFixture {
    enum ExportDirectorySelection {
        case systemPicker
        case cancelled
        case selected(URL)
    }

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

    /// Only replaces the system picker. The real worker still inspects, backs up,
    /// writes, rereads and verifies both files in this test-owned directory.
    static func exportDirectorySelection() throws -> ExportDirectorySelection {
        guard let root, let mode = exportMode else { return .systemPicker }
        let directory = root.appendingPathComponent("Game/Farmer_123", isDirectory: true)
        let marker = root.appendingPathComponent("export-selection-\(mode)")
        let firstSelection = !FileManager.default.fileExists(atPath: marker.path)
        if firstSelection {
            try Data(mode.utf8).write(to: marker, options: .atomic)
            if mode == "cancel-once" { return .cancelled }
            if mode == "wrong-farm-once" {
                let other = root.appendingPathComponent("OtherGame/Farmer_123", isDirectory: true)
                try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
                for name in ["Farmer_123", "SaveGameInfo"] {
                    let xml = try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
                        .replacingOccurrences(of: "<uniqueMultiplayerID>42</uniqueMultiplayerID>",
                                              with: "<uniqueMultiplayerID>84</uniqueMultiplayerID>")
                    try Data(xml.utf8).write(to: other.appendingPathComponent(name), options: .atomic)
                }
                return .selected(other)
            }
        }
        return .selected(directory)
    }

    /// Simulates another app changing the already-inspected target. It never
    /// changes a source URL supplied by the user and fires once per UUID only.
    static func beforeExportCommit() throws {
        guard let root, exportMode == "stale-once" else { return }
        let marker = root.appendingPathComponent("export-target-changed")
        guard !FileManager.default.fileExists(atPath: marker.path) else { return }
        let directory = root.appendingPathComponent("Game/Farmer_123", isDirectory: true)
        for name in ["Farmer_123", "SaveGameInfo"] {
            let xml = try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
                .replacingOccurrences(of: "<money>100</money>", with: "<money>101</money>")
            try Data(xml.utf8).write(to: directory.appendingPathComponent(name), options: .atomic)
        }
        try Data("changed".utf8).write(to: marker, options: .atomic)
    }

    private static var exportMode: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--ui-export-fixture"),
              arguments.indices.contains(index + 1) else { return nil }
        let mode = arguments[index + 1]
        return ["success", "cancel-once", "wrong-farm-once", "stale-once"].contains(mode) ? mode : nil
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
        let animals = [("1", "Alpha"), ("2", "Beta")].map { id, name in
            """
            <item><key><long>\(id)</long></key><value><FarmAnimal>
            <name>\(name)</name><displayName>\(name)</displayName><type>White Cow</type><buildingTypeILiveIn>Barn</buildingTypeILiveIn>
            <friendshipTowardFarmer>400</friendshipTowardFarmer><happiness>180</happiness><fullness>160</fullness><daysOwned>20</daysOwned><age>20</age>
            </FarmAnimal></value></item>
            """
        }.joined()
        try Data("<SaveGame xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\"><gameVersion>1.6.15</gameVersion><player>\(player)</player><year>1</year><currentSeason>spring</currentSeason><dayOfMonth>1</dayOfMonth><locations><GameLocation xsi:type=\"Farm\"><name>Farm</name><animals>\(animals)</animals></GameLocation></locations></SaveGame>".utf8).write(to: urls[0])
        try Data("<Farmer>\(player)</Farmer>".utf8).write(to: urls[1])
        return urls
    }
}
#endif
