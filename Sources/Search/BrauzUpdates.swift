import Foundation

// Brauz checks GitHub for newer releases once a day and tells the user when
// one is out. It never downloads or swaps binaries itself.

@MainActor
final class BrauzUpdates: ObservableObject {
    static let shared = BrauzUpdates()

    struct Release: Equatable {
        let version: String
        let build: Int
        let page: URL
    }

    @Published private(set) var newer: Release?
    @Published private(set) var checking = false
    @Published private(set) var lastChecked: Date?

    private let checkedKey = "brauz.updates.checked"
    private let announcedKey = "brauz.updates.announced"
    private var say: ((String) -> Void)?
    private var clock: Timer?

    private init() {
        lastChecked = Store.settings.object(forKey: checkedKey) as? Date
    }

    /// At launch, then every hour. If the last check was more than 20 hours
    /// ago or never, it checks now; the clock checks again once 24 hours pass.
    func start(say: @escaping (String) -> Void) {
        self.say = say
        guard !Store.testing else { return }
        guard clock == nil else { return }
        clock = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkIfDue() }
        }
        clock?.tolerance = 60 * 5

        let interval = lastChecked.map { Date().timeIntervalSince($0) }
        if interval == nil || (interval ?? 0) > 20 * 60 * 60 {
            check(automatic: true)
        }
    }

    /// Every hour: checks again once 24 hours have passed since the last check.
    private func checkIfDue() {
        guard let last = lastChecked else {
            check(automatic: true)
            return
        }
        guard Date().timeIntervalSince(last) >= 24 * 60 * 60 else { return }
        check(automatic: true)
    }

    /// Settings › About or the Search menu: asks GitHub now.
    func checkByHand() {
        if let newer {
            say?("Brauz \(newer.version) is out — download it in Settings › About")
            return
        }
        guard !Store.testing else { return }
        guard !checking else { return }
        say?("Checking for updates…")
        check(automatic: false)
    }

    private func check(automatic: Bool) {
        guard !Store.testing else { return }
        guard !checking else { return }
        checking = true
        Task { [weak self] in
            let result = await Self.fetch()
            guard let self else { return }
            checking = false
            switch result {
            case .failure:
                if !automatic {
                    say?("Couldn't reach GitHub")
                }
            case .success(let release):
                let now = Date()
                lastChecked = now
                Store.settings.set(now, forKey: checkedKey)
                if let release, release.build > Updater.build {
                    newer = release
                    if automatic {
                        let announced = Store.settings.integer(forKey: announcedKey)
                        if announced != release.build {
                            Store.settings.set(release.build, forKey: announcedKey)
                            say?("Brauz \(release.version) is out — download it in Settings › About")
                        }
                    } else {
                        Store.settings.set(release.build, forKey: announcedKey)
                        say?("Brauz \(release.version) is out — download it in Settings › About")
                    }
                } else {
                    newer = nil
                    if !automatic {
                        say?("Brauz is up to date")
                    }
                }
            }
        }
    }

    private struct GitHubRelease: Decodable, Sendable {
        let name: String
        let html_url: URL
    }

    private enum FetchError: Error, Sendable {
        case badURL, badStatus
    }

    private nonisolated static func fetch() async -> Result<Release?, Error> {
        guard !Store.testing else { return .failure(FetchError.badStatus) }
        guard let url = URL(string: "https://api.github.com/repos/hnnsly/Search/releases/latest") else {
            return .failure(FetchError.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Brauz", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            return .failure(error)
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return .failure(FetchError.badStatus)
        }
        let release: GitHubRelease
        do {
            release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        } catch {
            return .failure(error)
        }
        guard let parsed = parse(title: release.name) else {
            return .success(nil)
        }
        return .success(Release(version: parsed.version, build: parsed.build, page: release.html_url))
    }

    /// Releases are named "Brauz 1.0.4 (build 202610071500)". Any other
    /// title format is ignored so drafts or different naming schemes
    /// do not trigger an update notice.
    nonisolated static func parse(title: String) -> (version: String, build: Int)? {
        guard title.hasPrefix("Brauz ") else { return nil }
        guard let buildParenRange = title.range(of: " (build") else { return nil }
        let versionStart = title.index(title.startIndex, offsetBy: "Brauz ".count)
        guard versionStart <= buildParenRange.lowerBound else { return nil }
        let version = String(title[versionStart..<buildParenRange.lowerBound]).trimmingCharacters(in: .whitespaces)
        guard !version.isEmpty else { return nil }
        guard let buildTagRange = title.range(of: "build ", range: buildParenRange.lowerBound..<title.endIndex) else {
            return nil
        }
        let afterBuild = title[buildTagRange.upperBound...]
        let digits = afterBuild.prefix(while: { $0 >= "0" && $0 <= "9" })
        guard digits.count == 12, let build = Int(digits) else { return nil }
        return (version, build)
    }
}
