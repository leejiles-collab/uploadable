import Foundation
import CryptoKit
import Security

/// The meter.
///
/// Fits themselves are free and unlimited — anyone can run any photo against any
/// spec and see the whole Done screen. The result *is* the sales pitch, and
/// hiding it behind a counter would hide the reason to pay. What is metered is
/// getting the file out: saving it to Photos, saving it to Files, sharing it.
///
/// ## Why the same photo cannot cost twice
///
/// Exports are recorded by the SHA-256 of the file that leaves. Saving one
/// result to Photos and then to Files and then sharing it is one export, not
/// three, because it is the same bytes each time. Charging three times for one
/// photo earns a one-star review and deserves to.
///
/// ## Why the Keychain item is scoped
///
/// The count is kept in the App Group and mirrored to the Keychain so that
/// deleting the app does not hand out a fresh allowance. `kSecAttrAccessGroup`
/// is set to the App Group, without which the app and the share extension each
/// write to their own `application-identifier` default group and keep *separate*
/// counts — invisible to one another, with the larger silently winning. That
/// cost a day on Smaller; see SCALLAPP.md.
public actor ExportStore {

    private static let usedKey = "com.fits.exportsUsed"
    private static let hashesKey = "com.fits.exportedHashes"
    private static let keychainAccount = "exportsUsed"

    /// How many hashes to remember. Enough that a person cannot plausibly walk
    /// out of the window in one sitting, small enough to stay a trivial write.
    private static let rememberedHashes = 200

    private let defaults: UserDefaults?
    /// Whether to mirror the count into the Keychain.
    ///
    /// Always true in the app and the extension — the mirror is what stops a
    /// reinstall handing out a fresh allowance. Off in unit tests, and not for
    /// tidiness: an unsigned test binary writing a Keychain item under an access
    /// group it does not hold blocks on a system prompt that never gets
    /// answered, so the whole suite hangs. The scoping that makes the mirror
    /// shared is asserted directly against `query()` instead.
    private let mirrorsToKeychain: Bool

    public init(suiteName: String = BundleConfig.appGroupID, mirrorsToKeychain: Bool = true) {
        self.defaults = UserDefaults(suiteName: suiteName)
        self.mirrorsToKeychain = mirrorsToKeychain
    }

    // MARK: - Counting

    /// Exports spent so far. Reads both stores and trusts the larger.
    public var used: Int {
        let local = defaults?.integer(forKey: Self.usedKey) ?? 0
        guard mirrorsToKeychain else { return local }
        let keychain = Self.readKeychain() ?? 0
        let truth = max(local, keychain)
        if local < truth { defaults?.set(truth, forKey: Self.usedKey) }
        if keychain < truth { Self.writeKeychain(truth) }
        return truth
    }

    public var remaining: Int { max(0, Config.freeExports - used) }
    public var isExhausted: Bool { remaining == 0 }

    // MARK: - Deciding

    /// Whether this file may leave, without changing anything.
    ///
    /// Free when the same bytes have already been exported, so the second and
    /// third destination for one result never cost.
    public func isAllowed(_ url: URL, isPro: Bool) -> Bool {
        if isPro { return true }
        if let hash = Self.hash(of: url), counted().contains(hash) { return true }
        return remaining > 0
    }

    /// Records a successful export. Idempotent per file.
    ///
    /// Called *after* the export lands, not before: a save that fails should not
    /// cost anything. Re-exporting the same bytes adds nothing.
    public func record(_ url: URL) {
        guard let hash = Self.hash(of: url) else { return }
        var seen = counted()
        guard !seen.contains(hash) else { return }

        seen.append(hash)
        if seen.count > Self.rememberedHashes {
            seen.removeFirst(seen.count - Self.rememberedHashes)
        }
        defaults?.set(seen, forKey: Self.hashesKey)

        let next = used + 1
        defaults?.set(next, forKey: Self.usedKey)
        if mirrorsToKeychain { Self.writeKeychain(next) }
    }

    /// Whether this exact file has already been paid for.
    public func isAlreadyExported(_ url: URL) -> Bool {
        guard let hash = Self.hash(of: url) else { return false }
        return counted().contains(hash)
    }

    /// Only for tests and for a debug reset.
    public func reset() {
        defaults?.set(0, forKey: Self.usedKey)
        defaults?.removeObject(forKey: Self.hashesKey)
        if mirrorsToKeychain { Self.writeKeychain(0) }
    }

    private func counted() -> [String] {
        defaults?.stringArray(forKey: Self.hashesKey) ?? []
    }

    // MARK: - Identity

    /// SHA-256 of the file's bytes. Two saves of the same result hash the same;
    /// a different crop, spec or quality does not.
    static func hash(of url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Keychain mirror

    static func query() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: BundleConfig.appGroupID,
            kSecAttrAccount as String: keychainAccount,
            // Without this each target writes to its own default access group
            // and the count is not shared at all. See the type's doc comment.
            kSecAttrAccessGroup as String: BundleConfig.appGroupID
        ]
    }

    static func readKeychain() -> Int? {
        var request = query()
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let text = String(data: data, encoding: .utf8) else { return nil }
        return Int(text)
    }

    static func writeKeychain(_ value: Int) {
        let data = Data(String(value).utf8)
        let status = SecItemUpdate(
            query() as CFDictionary, [kSecValueData as String: data] as CFDictionary
        )
        if status == errSecItemNotFound {
            var insert = query()
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(insert as CFDictionary, nil)
        }
    }
}
