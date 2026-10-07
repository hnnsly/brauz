import Foundation

// This fork is Brauz: an app of its own, under its own bundle id, beside
// Search rather than in its place. macOS keeps an app's settings, website
// data and cookies under its bundle id, so with Search's id the two shared
// all of it and wrote over each other.
//
// The first time Brauz runs, it takes a copy of what Search had: settings,
// the session, pins and history, and the sites' cookies and storage, so
// nobody is signed out. Search's own are left exactly as they were. Each is
// copied only while Brauz has nothing of its own in that place, so this
// happens once and never writes over Brauz's own data.
//
// Passwords are in the keychain, which isn't kept by bundle id: Brauz reads
// the same ones, and macOS may ask once whether it may.

enum ForkIdentity {
    static let bundleID = "dev.aabc.brauz"
    /// The data folder's name in Application Support.
    static let folderName = "Brauz"

    private static let searchID = "com.officecommun.search"

    /// Run before the first setting is read and the data folder is opened
    /// (see Store), which is before any page is made and WebKit opens its
    /// stores.
    static let adopted: Void = {
        guard !Store.testing, Bundle.main.bundleIdentifier == bundleID else { return }
        copySettings()
        let library = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library")
        copy(library.appendingPathComponent("Application Support/Search"),
             to: library.appendingPathComponent("Application Support/\(folderName)"))
        // WebKit's stores (each space's sites, extensions' data) and the
        // cookies, both kept by bundle id.
        copy(library.appendingPathComponent("WebKit/\(searchID)"),
             to: library.appendingPathComponent("WebKit/\(bundleID)"))
        copy(library.appendingPathComponent("HTTPStorages/\(searchID)"),
             to: library.appendingPathComponent("HTTPStorages/\(bundleID)"))
        copy(library.appendingPathComponent("HTTPStorages/\(searchID).binarycookies"),
             to: library.appendingPathComponent("HTTPStorages/\(bundleID).binarycookies"))
    }()

    private static func copySettings() {
        let defaults = UserDefaults.standard
        guard defaults.persistentDomain(forName: bundleID)?.isEmpty ?? true,
              let search = defaults.persistentDomain(forName: searchID), !search.isEmpty
        else { return }
        defaults.setPersistentDomain(search, forName: bundleID)
    }

    /// On the same disk, as these always are, APFS clones rather than
    /// copies: hundreds of megabytes in a moment, and no space taken twice.
    private static func copy(_ from: URL, to: URL) {
        let files = FileManager.default
        guard files.fileExists(atPath: from.path), !files.fileExists(atPath: to.path) else { return }
        try? files.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? files.copyItem(at: from, to: to)
    }
}
