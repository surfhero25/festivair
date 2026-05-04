import Foundation
import CryptoKit

/// Per-squad symmetric encryption keyed by the squad's 6-digit join code.
///
/// Threat model: anyone who knows the join code (squad members) can decrypt; anyone who doesn't,
/// can't read the underlying chat or location data — even if they hold a CloudKit dump of the public DB.
///
/// Cipher: AES-256-GCM via CryptoKit. Key is derived from the join code with HKDF-SHA256 using a fixed
/// app-wide salt. AES-GCM is authenticated, so any tampering with ciphertext is detected at decrypt time.
///
/// Wire format (base64-decoded): `[1-byte version=1][nonce ‖ ciphertext ‖ tag]` where the tail is the
/// `combined` form emitted by `AES.GCM.SealedBox.combined`. The `v1:` ASCII prefix on the base64 string
/// signals "this is encrypted" so decoders can fall through to plaintext for legacy records during the
/// transition.
enum SquadCrypto {

    /// Fixed salt (32 bytes) — bundled with the app, not a secret. Mixing in a constant prevents the same
    /// join code being recognised across unrelated key derivations elsewhere.
    private static let kdfSalt = Data("FestivAir.SquadCrypto.HKDF.v1".utf8)
    private static let kdfInfo = Data("squad-payload-key".utf8)
    private static let envelopeVersion: UInt8 = 1
    private static let prefix = "v1:"

    enum CryptoError: Error {
        case emptyJoinCode
        case decryptionFailed
        case malformedCiphertext
    }

    /// Derive the per-squad symmetric key from a join code. Idempotent: same join code → same key.
    /// Trims whitespace and uppercases — matches how join codes are normalized at squad join time.
    static func key(for joinCode: String) throws -> SymmetricKey {
        let normalized = joinCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalized.isEmpty else { throw CryptoError.emptyJoinCode }
        let inputKeyMaterial = SymmetricKey(data: Data(normalized.utf8))
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: inputKeyMaterial,
            salt: kdfSalt,
            info: kdfInfo,
            outputByteCount: 32
        )
    }

    /// Encrypts a UTF-8 string with the squad key and returns a `v1:`-prefixed base64 envelope.
    static func encrypt(_ plaintext: String, joinCode: String) throws -> String {
        let key = try key(for: joinCode)
        let sealed = try AES.GCM.seal(Data(plaintext.utf8), using: key)
        guard let combined = sealed.combined else { throw CryptoError.decryptionFailed }
        var envelope = Data([envelopeVersion])
        envelope.append(combined)
        return prefix + envelope.base64EncodedString()
    }

    /// Decrypts a `v1:`-prefixed base64 envelope produced by `encrypt(_:joinCode:)`.
    /// Returns the plaintext UTF-8 string. Throws `CryptoError.decryptionFailed` for tamper / wrong key.
    static func decrypt(_ ciphertext: String, joinCode: String) throws -> String {
        guard ciphertext.hasPrefix(prefix) else { throw CryptoError.malformedCiphertext }
        let body = String(ciphertext.dropFirst(prefix.count))
        guard let envelope = Data(base64Encoded: body), envelope.count > 1 else {
            throw CryptoError.malformedCiphertext
        }
        let version = envelope[envelope.startIndex]
        guard version == envelopeVersion else { throw CryptoError.malformedCiphertext }
        let combined = envelope.dropFirst()
        let key = try key(for: joinCode)
        do {
            let box = try AES.GCM.SealedBox(combined: combined)
            let plaintextData = try AES.GCM.open(box, using: key)
            guard let text = String(data: plaintextData, encoding: .utf8) else {
                throw CryptoError.decryptionFailed
            }
            return text
        } catch {
            throw CryptoError.decryptionFailed
        }
    }

    /// True if the string carries the v1 envelope prefix. Use to decide whether to attempt decryption
    /// or treat the value as plaintext (for legacy CloudKit records written before this build).
    static func isEncrypted(_ value: String) -> Bool {
        value.hasPrefix(prefix)
    }
}
