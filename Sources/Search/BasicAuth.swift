import Foundation
import WebKit
import Security

/// Protocol for BasicAuth credential persistence.
///
/// Implementations must be Sendable and thread-safe.
protocol BasicAuthStore: AnyObject, Sendable {
    func credential(for space: URLProtectionSpace) -> (user: String, password: String)?
    func save(space: URLProtectionSpace, user: String, password: String) -> Bool
    func forget(host: String, user: String, port: Int?, realm: String?) -> Bool
    func secret(host: String, user: String, port: Int?, realm: String?) -> String?
    func allKept() -> [Kept]
    func clearAll()
}

/// In-memory implementation of BasicAuthStore for tests and fast rehearsals.
final class MemoryBasicAuthStore: BasicAuthStore, @unchecked Sendable {
    private struct Entry {
        var user: String
        var password: String
        var used: Date
        var isClear: Bool
    }

    private let lock = NSLock()
    private var entries: [BasicAuth.SpaceKey: [Entry]] = [:]

    init() {}

    func credential(for space: URLProtectionSpace) -> (user: String, password: String)? {
        let key = BasicAuth.SpaceKey(space: space)
        return lock.withLock {
            guard let match = entries[key]?.sorted(by: { $0.used > $1.used }).first else { return nil }
            return (match.user, match.password)
        }
    }

    @discardableResult
    func save(space: URLProtectionSpace, user: String, password: String) -> Bool {
        guard !space.host.isEmpty, !user.isEmpty, !password.isEmpty else { return false }
        let key = BasicAuth.SpaceKey(space: space)
        let entry = Entry(
            user: user,
            password: password,
            used: Date(),
            isClear: !space.receivesCredentialSecurely
        )
        lock.withLock {
            var list = entries[key] ?? []
            list.removeAll { $0.user == user }
            list.insert(entry, at: 0)
            entries[key] = list
        }
        return true
    }

    @discardableResult
    func forget(host: String, user: String, port: Int?, realm: String?) -> Bool {
        let lower = host.lowercased()
        return lock.withLock {
            var deleted = false
            for (key, list) in entries {
                guard key.host == lower else { continue }
                if let port, key.port != port { continue }
                if let realm, key.realm != realm { continue }

                let filtered = list.filter { $0.user != user }
                if filtered.count != list.count {
                    deleted = true
                    if filtered.isEmpty {
                        entries.removeValue(forKey: key)
                    } else {
                        entries[key] = filtered
                    }
                }
            }
            return deleted
        }
    }

    func secret(host: String, user: String, port: Int?, realm: String?) -> String? {
        let lower = host.lowercased()
        return lock.withLock {
            for (key, list) in entries {
                guard key.host == lower else { continue }
                if let port, key.port != port { continue }
                if let realm, key.realm != realm { continue }
                if let item = list.first(where: { $0.user == user }) {
                    return item.password
                }
            }
            return nil
        }
    }

    func allKept() -> [Kept] {
        return lock.withLock {
            var result: [Kept] = []
            for (key, list) in entries {
                for item in list {
                    result.append(Kept(
                        host: key.host,
                        user: item.user,
                        used: item.used,
                        clear: item.isClear,
                        isSignIn: true,
                        port: key.port,
                        realm: key.realm
                    ))
                }
            }
            return result
        }
    }

    func clearAll() {
        lock.withLock {
            entries.removeAll()
        }
    }
}

/// Default Keychain-backed implementation of BasicAuthStore.
final class KeychainBasicAuthStore: BasicAuthStore, @unchecked Sendable {
    init() {}

    func credential(for space: URLProtectionSpace) -> (user: String, password: String)? {
        let key = BasicAuth.SpaceKey(space: space)
        let authType = BasicAuth.secAuthType(for: space.authenticationMethod)

        // Query attributes with kSecMatchLimitAll (never combine with kSecReturnData)
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: key.host,
            kSecAttrLabel as String: Vault.label,
            kSecAttrPort as String: key.port,
            kSecAttrSecurityDomain as String: key.realm,
            kSecAttrAuthenticationType as String: authType,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]

        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        guard status == errSecSuccess, let rows = out as? [[String: Any]] else {
            return nil
        }

        let sortedRows = rows.sorted { r1, r2 in
            let u1 = (r1[kSecAttrComment as String] as? String).flatMap(Double.init) ?? 0
            let u2 = (r2[kSecAttrComment as String] as? String).flatMap(Double.init) ?? 0
            return u1 > u2
        }

        for row in sortedRows {
            guard let user = row[kSecAttrAccount as String] as? String else { continue }
            let secretQuery: [String: Any] = [
                kSecClass as String: kSecClassInternetPassword,
                kSecAttrLabel as String: Vault.label,
                kSecAttrServer as String: key.host,
                kSecAttrAccount as String: user,
                kSecAttrPort as String: key.port,
                kSecAttrSecurityDomain as String: key.realm,
                kSecAttrAuthenticationType as String: authType,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ]
            var dataRef: CFTypeRef?
            if SecItemCopyMatching(secretQuery as CFDictionary, &dataRef) == errSecSuccess,
               let data = dataRef as? Data,
               let password = String(data: data, encoding: .utf8) {
                return (user, password)
            }
        }
        return nil
    }

    @discardableResult
    func save(space: URLProtectionSpace, user: String, password: String) -> Bool {
        guard !space.host.isEmpty, !user.isEmpty, !password.isEmpty,
              let data = password.data(using: .utf8)
        else { return false }

        let key = BasicAuth.SpaceKey(space: space)
        let authType = BasicAuth.secAuthType(for: space.authenticationMethod)
        let isSecure = space.receivesCredentialSecurely
        let now = Date()

        let identity: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: key.host,
            kSecAttrAccount as String: user,
            kSecAttrLabel as String: Vault.label,
            kSecAttrPort as String: key.port,
            kSecAttrSecurityDomain as String: key.realm,
            kSecAttrAuthenticationType as String: authType,
        ]

        let fields: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrProtocol as String: isSecure ? kSecAttrProtocolHTTPS : kSecAttrProtocolHTTP,
            kSecAttrComment as String: String(now.timeIntervalSince1970),
        ]

        let status = SecItemUpdate(identity as CFDictionary, fields as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }

        var fresh = identity.merging(fields) { _, new in new }
        fresh[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        let addStatus = SecItemAdd(fresh as CFDictionary, nil)
        return addStatus == errSecSuccess
    }

    @discardableResult
    func forget(host: String, user: String, port: Int?, realm: String?) -> Bool {
        let normalizedHost = host.lowercased()

        if let port, let realm {
            let deleteQuery: [String: Any] = [
                kSecClass as String: kSecClassInternetPassword,
                kSecAttrServer as String: normalizedHost,
                kSecAttrAccount as String: user,
                kSecAttrLabel as String: Vault.label,
                kSecAttrPort as String: port,
                kSecAttrSecurityDomain as String: realm,
            ]
            return SecItemDelete(deleteQuery as CFDictionary) == errSecSuccess
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: normalizedHost,
            kSecAttrAccount as String: user,
            kSecAttrLabel as String: Vault.label,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]

        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        var deletedAny = false
        if status == errSecSuccess, let rows = out as? [[String: Any]] {
            for row in rows {
                let authType = row[kSecAttrAuthenticationType as String] as? String
                if authType != nil && authType != (kSecAttrAuthenticationTypeHTMLForm as String) {
                    var deleteQuery: [String: Any] = [
                        kSecClass as String: kSecClassInternetPassword,
                        kSecAttrServer as String: normalizedHost,
                        kSecAttrAccount as String: user,
                        kSecAttrLabel as String: Vault.label,
                    ]
                    if let p = row[kSecAttrPort as String] { deleteQuery[kSecAttrPort as String] = p }
                    if let d = row[kSecAttrSecurityDomain as String] { deleteQuery[kSecAttrSecurityDomain as String] = d }
                    if let t = authType { deleteQuery[kSecAttrAuthenticationType as String] = t }
                    if SecItemDelete(deleteQuery as CFDictionary) == errSecSuccess {
                        deletedAny = true
                    }
                }
            }
        }
        return deletedAny
    }

    func secret(host: String, user: String, port: Int?, realm: String?) -> String? {
        let normalizedHost = host.lowercased()

        if let port, let realm {
            let query: [String: Any] = [
                kSecClass as String: kSecClassInternetPassword,
                kSecAttrServer as String: normalizedHost,
                kSecAttrAccount as String: user,
                kSecAttrLabel as String: Vault.label,
                kSecAttrPort as String: port,
                kSecAttrSecurityDomain as String: realm,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ]
            var out: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &out)
            if status == errSecSuccess, let data = out as? Data {
                return String(data: data, encoding: .utf8)
            }
            return nil
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: normalizedHost,
            kSecAttrAccount as String: user,
            kSecAttrLabel as String: Vault.label,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]

        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        guard status == errSecSuccess, let rows = out as? [[String: Any]] else { return nil }

        let nonFormRows = rows.filter { row in
            let authType = row[kSecAttrAuthenticationType as String] as? String
            return authType != nil && authType != (kSecAttrAuthenticationTypeHTMLForm as String)
        }.sorted { r1, r2 in
            let u1 = (r1[kSecAttrComment as String] as? String).flatMap(Double.init) ?? 0
            let u2 = (r2[kSecAttrComment as String] as? String).flatMap(Double.init) ?? 0
            return u1 > u2
        }

        for row in nonFormRows {
            var secretQuery: [String: Any] = [
                kSecClass as String: kSecClassInternetPassword,
                kSecAttrServer as String: normalizedHost,
                kSecAttrAccount as String: user,
                kSecAttrLabel as String: Vault.label,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ]
            if let p = row[kSecAttrPort as String] { secretQuery[kSecAttrPort as String] = p }
            if let d = row[kSecAttrSecurityDomain as String] { secretQuery[kSecAttrSecurityDomain as String] = d }
            if let t = row[kSecAttrAuthenticationType as String] { secretQuery[kSecAttrAuthenticationType as String] = t }

            var dataRef: CFTypeRef?
            if SecItemCopyMatching(secretQuery as CFDictionary, &dataRef) == errSecSuccess,
               let data = dataRef as? Data,
               let password = String(data: data, encoding: .utf8) {
                return password
            }
        }
        return nil
    }

    func allKept() -> [Kept] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrLabel as String: Vault.label,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        guard status == errSecSuccess, let rows = out as? [[String: Any]] else { return [] }

        return rows.compactMap { row in
            let authType = row[kSecAttrAuthenticationType as String] as? String
            guard authType != nil && authType != (kSecAttrAuthenticationTypeHTMLForm as String),
                  let rawHost = row[kSecAttrServer as String] as? String
            else { return nil }
            let host = rawHost.lowercased()
            let user = row[kSecAttrAccount as String] as? String ?? ""
            let used = (row[kSecAttrComment as String] as? String).flatMap(Double.init).map(Date.init(timeIntervalSince1970:))
            let port = (row[kSecAttrPort as String] as? Int) ?? 0
            let realm = (row[kSecAttrSecurityDomain as String] as? String) ?? ""
            let isClear = (row[kSecAttrProtocol as String] as? String) == (kSecAttrProtocolHTTP as String)
            return Kept(host: host, user: user, used: used, clear: isClear, isSignIn: true, port: port, realm: realm)
        }
    }

    func clearAll() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrLabel as String: Vault.label,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var out: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let rows = out as? [[String: Any]] {
            for row in rows {
                let authType = row[kSecAttrAuthenticationType as String] as? String
                if authType != nil && authType != (kSecAttrAuthenticationTypeHTMLForm as String) {
                    var deleteQuery: [String: Any] = [
                        kSecClass as String: kSecClassInternetPassword,
                        kSecAttrLabel as String: Vault.label,
                    ]
                    if let server = row[kSecAttrServer as String] { deleteQuery[kSecAttrServer as String] = server }
                    if let account = row[kSecAttrAccount as String] { deleteQuery[kSecAttrAccount as String] = account }
                    if let port = row[kSecAttrPort as String] { deleteQuery[kSecAttrPort as String] = port }
                    if let domain = row[kSecAttrSecurityDomain as String] { deleteQuery[kSecAttrSecurityDomain as String] = domain }
                    if let type = authType { deleteQuery[kSecAttrAuthenticationType as String] = type }
                    SecItemDelete(deleteQuery as CFDictionary)
                }
            }
        }
    }
}

/// HTTP Basic, Digest, and NTLM Authentication credential management.
///
/// Holds credentials saved by protection space (host, port, realm, method),
/// presents saved credentials when challenged, and stages new submissions
/// until accepted by the site (non-401 response).
enum BasicAuth {
    struct SpaceKey: Hashable, Equatable {
        let host: String
        let port: Int
        let realm: String
        let method: String

        init(host: String, port: Int, realm: String?, method: String) {
            self.host = host.lowercased()
            self.port = port
            self.realm = realm ?? ""
            self.method = method
        }

        init(space: URLProtectionSpace) {
            let defaultPort = space.receivesCredentialSecurely ? 443 : 80
            let port = space.port != 0 ? space.port : defaultPort
            self.init(
                host: space.host,
                port: port,
                realm: space.realm,
                method: space.authenticationMethod
            )
        }
    }

    struct Staged {
        let space: URLProtectionSpace
        let user: String
        let password: String
        let remember: Bool
        let stagedAt = Date()
    }

    /// Credentials pending site acceptance, keyed by webView.
    private static var pending: [ObjectIdentifier: Staged] = [:]

    /// Injectable backend store. Defaults to KeychainBasicAuthStore.
    nonisolated(unsafe) static var store: any BasicAuthStore = KeychainBasicAuthStore()

    // MARK: - Protection Space and Keychain mapping

    static func secAuthType(for method: String) -> String {
        switch method {
        case NSURLAuthenticationMethodHTTPBasic:
            return kSecAttrAuthenticationTypeHTTPBasic as String
        case NSURLAuthenticationMethodHTTPDigest:
            return kSecAttrAuthenticationTypeHTTPDigest as String
        case NSURLAuthenticationMethodNTLM:
            return kSecAttrAuthenticationTypeNTLM as String
        default:
            return kSecAttrAuthenticationTypeDefault as String
        }
    }

    // MARK: - Lookup

    static func credential(for space: URLProtectionSpace) -> (user: String, password: String)? {
        store.credential(for: space)
    }

    // MARK: - Saving

    @discardableResult
    static func save(space: URLProtectionSpace, user: String, password: String) -> Bool {
        store.save(space: space, user: user, password: password)
    }

    // MARK: - Removing

    @discardableResult
    static func forget(host: String, user: String, port: Int? = nil, realm: String? = nil) -> Bool {
        store.forget(host: host, user: user, port: port, realm: realm)
    }

    static func secret(host: String, user: String, port: Int? = nil, realm: String? = nil) -> String? {
        store.secret(host: host, user: user, port: port, realm: realm)
    }

    static func allKept() -> [Kept] {
        store.allKept()
    }

    // MARK: - Staging & Acceptance Lifecycle

    static func stage(
        for webView: WKWebView,
        space: URLProtectionSpace,
        user: String,
        password: String,
        remember: Bool = true
    ) {
        pending[ObjectIdentifier(webView)] = Staged(
            space: space,
            user: user,
            password: password,
            remember: remember
        )
    }

    static func responseReceived(for webView: WKWebView, statusCode: Int, isMainFrame: Bool) {
        guard let staged = pending[ObjectIdentifier(webView)] else { return }
        guard isMainFrame else { return }

        if statusCode == 401 {
            // Rejected by the site: never save
            pending.removeValue(forKey: ObjectIdentifier(webView))
            return
        }

        pending.removeValue(forKey: ObjectIdentifier(webView))
        if staged.remember {
            save(space: staged.space, user: staged.user, password: staged.password)
        }
    }

    static func challengeFailed(for webView: WKWebView, space: URLProtectionSpace) {
        // Site repeated the challenge or reported failure count > 0: drop staged
        pending.removeValue(forKey: ObjectIdentifier(webView))
    }

    static func cancel(for webView: WKWebView) {
        pending.removeValue(forKey: ObjectIdentifier(webView))
    }

    static func navigationFailed(for webView: WKWebView) {
        pending.removeValue(forKey: ObjectIdentifier(webView))
    }

    static func clearAllForTesting() {
        pending.removeAll()
        store.clearAll()
    }
}
