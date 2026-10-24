import XCTest
import WebKit
@testable import Search

final class BasicAuthTests: XCTestCase {
    override class func setUp() {
        setenv("SEARCH_PROBE", "basic-auth-\(getpid())", 1)
        super.setUp()
    }

    override func setUp() {
        super.setUp()
        BasicAuth.store = KeychainBasicAuthStore()
        BasicAuth.clearAllForTesting()
    }

    override func tearDown() {
        BasicAuth.clearAllForTesting()
        BasicAuth.store = KeychainBasicAuthStore()
        super.tearDown()
    }

    // MARK: - Protection Space Matching and Storage

    func testCredentialLookupMatchesProtectionSpaceExact() {
        let space = URLProtectionSpace(
            host: "secure.example.com",
            port: 443,
            protocol: "https",
            realm: "Admin Area",
            authenticationMethod: NSURLAuthenticationMethodHTTPBasic
        )

        // Before saving, lookup returns nil
        XCTAssertNil(BasicAuth.credential(for: space))

        // Save credential
        let saved = BasicAuth.save(space: space, user: "admin", password: "secret123")
        XCTAssertTrue(saved)

        // Exact match succeeds
        let found = BasicAuth.credential(for: space)
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.user, "admin")
        XCTAssertEqual(found?.password, "secret123")

        // Different realm fails
        let diffRealm = URLProtectionSpace(
            host: "secure.example.com",
            port: 443,
            protocol: "https",
            realm: "User Area",
            authenticationMethod: NSURLAuthenticationMethodHTTPBasic
        )
        XCTAssertNil(BasicAuth.credential(for: diffRealm))

        // Different port fails
        let diffPort = URLProtectionSpace(
            host: "secure.example.com",
            port: 8443,
            protocol: "https",
            realm: "Admin Area",
            authenticationMethod: NSURLAuthenticationMethodHTTPBasic
        )
        XCTAssertNil(BasicAuth.credential(for: diffPort))

        // Different host fails
        let diffHost = URLProtectionSpace(
            host: "other.example.com",
            port: 443,
            protocol: "https",
            realm: "Admin Area",
            authenticationMethod: NSURLAuthenticationMethodHTTPBasic
        )
        XCTAssertNil(BasicAuth.credential(for: diffHost))

        // Different method fails
        let diffMethod = URLProtectionSpace(
            host: "secure.example.com",
            port: 443,
            protocol: "https",
            realm: "Admin Area",
            authenticationMethod: NSURLAuthenticationMethodHTTPDigest
        )
        XCTAssertNil(BasicAuth.credential(for: diffMethod))
    }

    // MARK: - Staged Credential Lifecycle (Acceptance vs Rejection)

    func testStagedCredentialSavedOnlyAfterAcceptedMainFrameResponse() {
        let webView = WKWebView()
        let space = URLProtectionSpace(
            host: "router.local",
            port: 80,
            protocol: "http",
            realm: "Router Config",
            authenticationMethod: NSURLAuthenticationMethodHTTPBasic
        )

        // User submits credentials with remember = true
        BasicAuth.stage(for: webView, space: space, user: "admin", password: "password1")

        // Before response, nothing is saved to the vault
        XCTAssertNil(BasicAuth.credential(for: space))

        // Main-frame response with 200 OK arrives
        BasicAuth.responseReceived(for: webView, statusCode: 200, isMainFrame: true)

        // Now it must be saved in the vault
        let saved = BasicAuth.credential(for: space)
        XCTAssertNotNil(saved)
        XCTAssertEqual(saved?.user, "admin")
        XCTAssertEqual(saved?.password, "password1")
    }

    func testStagedCredentialRejectedOn401Response() {
        let webView = WKWebView()
        let space = URLProtectionSpace(
            host: "router.local",
            port: 80,
            protocol: "http",
            realm: "Router Config",
            authenticationMethod: NSURLAuthenticationMethodHTTPBasic
        )

        BasicAuth.stage(for: webView, space: space, user: "admin", password: "wrongpassword")
        XCTAssertNil(BasicAuth.credential(for: space))

        // Server responds with 401 Unauthorized
        BasicAuth.responseReceived(for: webView, statusCode: 401, isMainFrame: true)

        // Rejected password is never saved
        XCTAssertNil(BasicAuth.credential(for: space))
    }

    func testStagedCredentialRejectedOnSubsequentChallengeFailure() {
        let webView = WKWebView()
        let space = URLProtectionSpace(
            host: "router.local",
            port: 80,
            protocol: "http",
            realm: "Router Config",
            authenticationMethod: NSURLAuthenticationMethodHTTPBasic
        )

        BasicAuth.stage(for: webView, space: space, user: "admin", password: "wrongpassword")

        // Challenge returns with previous failure > 0 (server asked again)
        BasicAuth.challengeFailed(for: webView, space: space)

        // Even if later a non-401 somehow arrives, the failed credential was dropped
        BasicAuth.responseReceived(for: webView, statusCode: 200, isMainFrame: true)
        XCTAssertNil(BasicAuth.credential(for: space))
    }

    func testUncheckedRememberDoesNotSaveEvenWhenAccepted() {
        let webView = WKWebView()
        let space = URLProtectionSpace(
            host: "router.local",
            port: 80,
            protocol: "http",
            realm: "Router Config",
            authenticationMethod: NSURLAuthenticationMethodHTTPBasic
        )

        // User unchecked "Remember in Brauz" (remember: false)
        BasicAuth.stage(for: webView, space: space, user: "admin", password: "password1", remember: false)

        // Response 200 OK
        BasicAuth.responseReceived(for: webView, statusCode: 200, isMainFrame: true)

        // Not saved
        XCTAssertNil(BasicAuth.credential(for: space))
    }

    // MARK: - Vault Integration and Settings Passwords

    func testSavedSignInShowsInVaultAllAndCanBeRemoved() {
        let space = URLProtectionSpace(
            host: "intranet.company.com",
            port: 443,
            protocol: "https",
            realm: "Corporate",
            authenticationMethod: NSURLAuthenticationMethodHTTPBasic
        )

        BasicAuth.save(space: space, user: "corpuser", password: "corppassword")

        // Vault.all() includes this credential
        let all = Vault.all()
        let found = all.first { $0.host == "intranet.company.com" && $0.user == "corpuser" }
        XCTAssertNotNil(found)
        XCTAssertTrue(found?.isSignIn == true)

        // Removing via Vault.forget removes it
        let forgotten = Vault.forget(host: "intranet.company.com", user: "corpuser", isSignIn: true)
        XCTAssertTrue(forgotten)

        let afterForget = Vault.all().first { $0.host == "intranet.company.com" && $0.user == "corpuser" }
        XCTAssertNil(afterForget)
        XCTAssertNil(BasicAuth.credential(for: space))
    }

    func testSignInEntryDistinguishableFromFormLoginForSameHost() throws {
        let host = "shared.example.com"

        // Save a regular form login
        Vault.save(host: host, user: "user1", password: "formpassword")

        // Save a Basic Auth sign-in for the same host
        let space = URLProtectionSpace(
            host: host,
            port: 443,
            protocol: "https",
            realm: "Protected Area",
            authenticationMethod: NSURLAuthenticationMethodHTTPBasic
        )
        BasicAuth.save(space: space, user: "user1", password: "basicpassword")

        let all = Vault.all().filter { $0.host == host }
        XCTAssertEqual(all.count, 2)

        let formEntry = all.first { !$0.isSignIn }
        let signInEntry = all.first { $0.isSignIn }

        XCTAssertNotNil(formEntry)
        XCTAssertNotNil(signInEntry)
        XCTAssertNotEqual(formEntry?.id, signInEntry?.id)

        // Form autofill Vault.logins(for:) only returns form logins
        let formLogins = Vault.logins(for: host)
        XCTAssertEqual(formLogins.count, 1)
        XCTAssertEqual(formLogins.first?.password, "formpassword")

        // Basic auth lookup returns basic password
        let basicCred = BasicAuth.credential(for: space)
        XCTAssertEqual(basicCred?.password, "basicpassword")

        // Removing the basic auth sign-in preserves the form login
        Vault.forget(host: host, user: "user1", isSignIn: true)
        let remaining = Vault.all().filter { $0.host == host }
        XCTAssertEqual(remaining.count, 1)
        let kept = try XCTUnwrap(remaining.first)
        XCTAssertFalse(kept.isSignIn)
        XCTAssertEqual(Vault.secret(of: kept), "formpassword")
    }

    func testSubresourceNon401DoesNotAcceptStagedCredential() {
        let webView = WKWebView()
        let space = URLProtectionSpace(
            host: "router.local",
            port: 80,
            protocol: "http",
            realm: "Router Config",
            authenticationMethod: NSURLAuthenticationMethodHTTPBasic
        )

        BasicAuth.stage(for: webView, space: space, user: "admin", password: "password1")

        // Subresource response (isMainFrame: false) with 200 OK
        BasicAuth.responseReceived(for: webView, statusCode: 200, isMainFrame: false)

        // Still not saved! Must wait for main frame response
        XCTAssertNil(BasicAuth.credential(for: space))

        // Main frame response arrives
        BasicAuth.responseReceived(for: webView, statusCode: 200, isMainFrame: true)

        // Now saved
        XCTAssertNotNil(BasicAuth.credential(for: space))
    }

    func testMostRecentlySavedCredentialIsReturnedForSpace() {
        let space = URLProtectionSpace(
            host: "multi.example.com",
            port: 443,
            protocol: "https",
            realm: "Shared Area",
            authenticationMethod: NSURLAuthenticationMethodHTTPBasic
        )

        BasicAuth.save(space: space, user: "userA", password: "passA")
        // Save userB later
        BasicAuth.save(space: space, user: "userB", password: "passB")

        let cred = BasicAuth.credential(for: space)
        XCTAssertEqual(cred?.user, "userB")
        XCTAssertEqual(cred?.password, "passB")
    }

    func testNavigationFailureClearsStagedCredential() {
        let webView = WKWebView()
        let space = URLProtectionSpace(
            host: "router.local",
            port: 80,
            protocol: "http",
            realm: "Router Config",
            authenticationMethod: NSURLAuthenticationMethodHTTPBasic
        )

        BasicAuth.stage(for: webView, space: space, user: "admin", password: "password1")

        BasicAuth.navigationFailed(for: webView)

        // Even if later a 200 arrives, staged was cleared
        BasicAuth.responseReceived(for: webView, statusCode: 200, isMainFrame: true)
        XCTAssertNil(BasicAuth.credential(for: space))
    }

    // MARK: - Keychain Roundtrip and Query Safety (errSecParam avoidance)

    func testKeychainRoundTripSaveLookupSecretForget() {
        let space = URLProtectionSpace(
            host: "keychain-roundtrip.example.com",
            port: 443,
            protocol: "https",
            realm: "SecureRealm",
            authenticationMethod: NSURLAuthenticationMethodHTTPBasic
        )

        // 1. Save directly to Keychain
        let saved = BasicAuth.save(space: space, user: "kcuser", password: "kcpassword")
        XCTAssertTrue(saved)

        // 2. Clear store reference to ensure no in-memory cache is used
        BasicAuth.store = KeychainBasicAuthStore()

        // 3. New lookup querying Keychain: attributes first, then secret with MatchLimitOne
        let cred = BasicAuth.credential(for: space)
        XCTAssertNotNil(cred, "Lookup must succeed from Keychain without errSecParam")
        XCTAssertEqual(cred?.user, "kcuser")
        XCTAssertEqual(cred?.password, "kcpassword")

        // 4. Read secret via BasicAuth.secret and Vault.secret
        let secret = BasicAuth.secret(host: "keychain-roundtrip.example.com", user: "kcuser", port: 443, realm: "SecureRealm")
        XCTAssertEqual(secret, "kcpassword")

        let vaultSecret = Vault.secret(host: "keychain-roundtrip.example.com", user: "kcuser", isSignIn: true, port: 443, realm: "SecureRealm")
        XCTAssertEqual(vaultSecret, "kcpassword")

        // 5. Forget credential
        let forgotten = BasicAuth.forget(host: "keychain-roundtrip.example.com", user: "kcuser", port: 443, realm: "SecureRealm")
        XCTAssertTrue(forgotten)

        // 6. After forget, credential is gone
        BasicAuth.store = KeychainBasicAuthStore()
        XCTAssertNil(BasicAuth.credential(for: space))
    }

    // MARK: - Collision Avoidance (Port and Realm in Kept.id and targeted removal)

    func testSignInsOnSameHostWithDifferentPortOrRealmDoNotCollideAndRemovingOneKeepsOther() throws {
        let spaceA = URLProtectionSpace(
            host: "multiservice.local",
            port: 8080,
            protocol: "http",
            realm: "WebAdmin",
            authenticationMethod: NSURLAuthenticationMethodHTTPBasic
        )
        let spaceB = URLProtectionSpace(
            host: "multiservice.local",
            port: 9090,
            protocol: "http",
            realm: "ApiGateway",
            authenticationMethod: NSURLAuthenticationMethodHTTPBasic
        )

        // Save two sign-ins on the same host for the same username with different port/realm
        XCTAssertTrue(BasicAuth.save(space: spaceA, user: "admin", password: "adminpass"))
        XCTAssertTrue(BasicAuth.save(space: spaceB, user: "admin", password: "apipass"))

        // Both credentials can be retrieved
        XCTAssertEqual(BasicAuth.credential(for: spaceA)?.password, "adminpass")
        XCTAssertEqual(BasicAuth.credential(for: spaceB)?.password, "apipass")

        // Vault.all() must list both without collision
        let items = Vault.all().filter { $0.host == "multiservice.local" }
        XCTAssertEqual(items.count, 2, "Both sign-ins must be listed without ID collision")

        let itemA = items.first { $0.port == 8080 }
        let itemB = items.first { $0.port == 9090 }
        XCTAssertNotNil(itemA)
        XCTAssertNotNil(itemB)
        XCTAssertNotEqual(itemA?.id, itemB?.id, "Kept.id must differ when port/realm differ")
        XCTAssertEqual(itemA?.realm, "WebAdmin")
        XCTAssertEqual(itemB?.realm, "ApiGateway")

        // Removing itemA must remove only itemA and keep itemB
        let forgotten = Vault.forget(try XCTUnwrap(itemA))
        XCTAssertTrue(forgotten)

        let remaining = Vault.all().filter { $0.host == "multiservice.local" }
        XCTAssertEqual(remaining.count, 1, "Only itemA should have been removed")
        XCTAssertEqual(remaining.first?.port, 9090)
        XCTAssertEqual(remaining.first?.realm, "ApiGateway")
        XCTAssertEqual(Vault.secret(of: try XCTUnwrap(remaining.first)), "apipass")

        // Space A is forgotten, Space B remains
        XCTAssertNil(BasicAuth.credential(for: spaceA))
        XCTAssertEqual(BasicAuth.credential(for: spaceB)?.password, "apipass")
    }

    // MARK: - Host Case Normalization

    func testHostCaseNormalizationPreventsDuplicateListing() {
        let space = URLProtectionSpace(
            host: "InTrAnEt.ExAmPlE.cOm",
            port: 443,
            protocol: "https",
            realm: "Corp",
            authenticationMethod: NSURLAuthenticationMethodHTTPBasic
        )

        XCTAssertTrue(BasicAuth.save(space: space, user: "alice", password: "alicepassword"))

        // Lookup with lowercase host succeeds
        let lowerSpace = URLProtectionSpace(
            host: "intranet.example.com",
            port: 443,
            protocol: "https",
            realm: "Corp",
            authenticationMethod: NSURLAuthenticationMethodHTTPBasic
        )
        XCTAssertEqual(BasicAuth.credential(for: lowerSpace)?.password, "alicepassword")

        // Lookup with uppercase host succeeds
        let upperSpace = URLProtectionSpace(
            host: "INTRANET.EXAMPLE.COM",
            port: 443,
            protocol: "https",
            realm: "Corp",
            authenticationMethod: NSURLAuthenticationMethodHTTPBasic
        )
        XCTAssertEqual(BasicAuth.credential(for: upperSpace)?.password, "alicepassword")

        // Vault.all() normalizes host and lists entry exactly once
        let items = Vault.all().filter { $0.host == "intranet.example.com" }
        XCTAssertEqual(items.count, 1, "Host must be normalized to lowercase so item never lists twice")
        XCTAssertEqual(items.first?.host, "intranet.example.com")

        // Forget with different casing succeeds
        XCTAssertTrue(Vault.forget(host: "INTRANET.EXAMPLE.COM", user: "alice", isSignIn: true, port: 443, realm: "Corp"))
        XCTAssertNil(BasicAuth.credential(for: lowerSpace))
    }

    // MARK: - Injectable Memory Store

    func testInjectableMemoryStoreWorksIndependently() {
        let memoryStore = MemoryBasicAuthStore()
        BasicAuth.store = memoryStore

        let space = URLProtectionSpace(
            host: "memory.local",
            port: 80,
            protocol: "http",
            realm: "MemRealm",
            authenticationMethod: NSURLAuthenticationMethodHTTPBasic
        )

        XCTAssertTrue(BasicAuth.save(space: space, user: "memuser", password: "mempass"))
        XCTAssertEqual(BasicAuth.credential(for: space)?.password, "mempass")
        XCTAssertEqual(BasicAuth.secret(host: "memory.local", user: "memuser", port: 80, realm: "MemRealm"), "mempass")

        let kept = BasicAuth.allKept()
        XCTAssertEqual(kept.count, 1)
        XCTAssertEqual(kept.first?.host, "memory.local")
        XCTAssertEqual(kept.first?.user, "memuser")

        XCTAssertTrue(BasicAuth.forget(host: "memory.local", user: "memuser", port: 80, realm: "MemRealm"))
        XCTAssertNil(BasicAuth.credential(for: space))
        XCTAssertTrue(BasicAuth.allKept().isEmpty)
    }

    // MARK: - Form Login and Basic Auth Coexistence

    func testSaveSignInFirstThenFormLoginBothSurviveWithOwnPasswords() {
        let host = "coexist.example.com"
        let user = "shareduser"
        let signInPassword = "signin_secret_pw"
        let formPassword = "form_secret_pw"

        let space = URLProtectionSpace(
            host: host,
            port: 443,
            protocol: "https",
            realm: "AuthZone",
            authenticationMethod: NSURLAuthenticationMethodHTTPBasic
        )

        defer {
            Vault.forget(host: host, user: user, isSignIn: false)
            Vault.forget(host: host, user: user, isSignIn: true, port: 443, realm: "AuthZone")
        }

        // 1. Save sign-in first
        XCTAssertTrue(BasicAuth.save(space: space, user: user, password: signInPassword))

        // 2. Save form login second for the same host and user
        XCTAssertTrue(Vault.save(host: host, user: user, password: formPassword))

        // 3. Both must survive with their own passwords
        let basicCred = BasicAuth.credential(for: space)
        XCTAssertEqual(basicCred?.password, signInPassword, "Sign-in credential must survive with its own password")

        let basicSecret = BasicAuth.secret(host: host, user: user, port: 443, realm: "AuthZone")
        XCTAssertEqual(basicSecret, signInPassword)

        let formSecret = Vault.secret(host: host, user: user, isSignIn: false)
        XCTAssertEqual(formSecret, formPassword, "Form login must survive with its own password")

        // 4. Vault.all() must list both entries without ID collision
        let items = Vault.all().filter { $0.host == host && $0.user == user }
        XCTAssertEqual(items.count, 2, "Both sign-in and form login must exist in Vault.all()")

        let formItem = items.first { !$0.isSignIn }
        let signInItem = items.first { $0.isSignIn }
        XCTAssertNotNil(formItem)
        XCTAssertNotNil(signInItem)
        XCTAssertEqual(Vault.secret(of: formItem!), formPassword)
        XCTAssertEqual(Vault.secret(of: signInItem!), signInPassword)

        // 5. Vault.logins(for:) for web page autofill only returns the form login
        let formLogins = Vault.logins(for: host)
        XCTAssertEqual(formLogins.count, 1)
        XCTAssertEqual(formLogins.first?.password, formPassword)
    }

    // MARK: - Nil Port and Realm Secret Keychain Query

    func testBasicAuthSecretWithNilPortAndRealmReadsFromKeychain() {
        let host = "nilparams.example.com"
        let user = "niluser"
        let password = "nilpassword"

        let space = URLProtectionSpace(
            host: host,
            port: 443,
            protocol: "https",
            realm: "NilRealm",
            authenticationMethod: NSURLAuthenticationMethodHTTPBasic
        )

        defer {
            BasicAuth.forget(host: host, user: user, port: 443, realm: "NilRealm")
        }

        XCTAssertTrue(BasicAuth.save(space: space, user: user, password: password))

        // Ensure KeychainBasicAuthStore is used (not MemoryBasicAuthStore)
        BasicAuth.store = KeychainBasicAuthStore()

        // Read secret with port and realm nil: must go through Keychain path and succeed
        let secret = BasicAuth.secret(host: host, user: user, port: nil, realm: nil)
        XCTAssertEqual(secret, password, "BasicAuth.secret with nil port and realm must read secret from Keychain")
    }
}
