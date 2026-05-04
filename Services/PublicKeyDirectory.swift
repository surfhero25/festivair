import Foundation

/// In-memory cache of `userId → DER-encoded P-256 public key`, persisted to UserDefaults.
///
/// Trust model is **trust-on-first-use (TOFU)**: the first valid keyed envelope we see from a given
/// userId binds that key forever (until the directory is cleared). Subsequent envelopes claiming
/// the same userId with a different public key are rejected at verify time.
///
/// Known limitations (acceptable for this beta, fix in a follow-up):
///   - An attacker who joins the squad before the legitimate user can pre-poison the directory.
///   - We rely on every V2Envelope carrying its sender's public key (`senderPublicKey`) — older
///     builds without that field can't bootstrap into the directory and their messages are dropped.
///
/// Future hardening path: bind userIds to public keys via CloudKit user records (anchored to Apple ID).
@MainActor
final class PublicKeyDirectory {

    static let shared = PublicKeyDirectory()

    private let userDefaultsKey = "FestivAir.PublicKeyDirectory.v1"
    private var cache: [String: Data] = [:]

    private init() {
        // Load persisted directory at startup. Stored as `[userId: base64-encoded-pubkey]`.
        if let raw = UserDefaults.standard.dictionary(forKey: userDefaultsKey) as? [String: String] {
            for (uid, b64) in raw {
                if let data = Data(base64Encoded: b64) {
                    cache[uid] = data
                }
            }
        }
    }

    /// Returns the cached public key for `userId`, or nil if unseen.
    func publicKey(for userId: String) -> Data? {
        cache[userId]
    }

    /// Records a userId → public key binding. First-write wins; conflicting writes are rejected
    /// and surfaced via the return value (the caller should treat the conflicting envelope as hostile).
    @discardableResult
    func record(userId: String, publicKey: Data) -> Bool {
        if let existing = cache[userId] {
            return existing == publicKey
        }
        cache[userId] = publicKey
        persist()
        return true
    }

    /// Wipes the directory. Used for account-reset flows; never call on routine sign-out.
    func clear() {
        cache.removeAll()
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }

    private func persist() {
        let serialized = cache.mapValues { $0.base64EncodedString() }
        UserDefaults.standard.set(serialized, forKey: userDefaultsKey)
    }
}
