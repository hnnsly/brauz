import Foundation

// Brauz: an app under its own bundle id, beside Search rather than in its
// place. Settings, website data and cookies are kept under its bundle id.

enum ForkIdentity {
    static let bundleID = "dev.aabc.brauz"
    /// The data folder's name in Application Support.
    static let folderName = "Brauz"
}
