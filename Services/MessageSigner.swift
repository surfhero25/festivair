import Foundation
import CryptoKit
import Security

// MARK: - MessageSigner

/// Provides P-256 ECDSA message signing using the Secure Enclave (device) or
/// CryptoKit software keys (Simulator). Keys persist in Keychain across launches.
///
/// Used to authenticate every mesh message — critical for SOS integrity.
final class MessageSigner: MessageSignerProtocol {

    // MARK: - Types

    enum SignerError: Error, LocalizedError {
        case keyGenerationFailed
        case keychainSaveFailed(OSStatus)
        case keychainLoadFailed(OSStatus)
        case signingFailed(Error)

        var errorDescription: String? {
            switch self {
            case .keyGenerationFailed:
                return "Failed to generate signing key"
            case .keychainSaveFailed(let status):
                return "Keychain save failed: \(status)"
            case .keychainLoadFailed(let status):
                return "Keychain load failed: \(status)"
            case .signingFailed(let error):
                return "Signing failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Constants

    private static let keychainService = "com.festivair.signing-key"
    private static let keychainAccount = "p256-private-key"

    // MARK: - Key Storage

    /// The underlying key — either Secure Enclave or software P-256.
    private enum PrivateKeyHolder {
        case secureEnclave(SecureEnclave.P256.Signing.PrivateKey)
        case software(P256.Signing.PrivateKey)

        func sign(_ data: Data) throws -> Data {
            switch self {
            case .secureEnclave(let key):
                return try key.signature(for: data).derRepresentation
            case .software(let key):
                return try key.signature(for: data).derRepresentation
            }
        }

        var publicKey: P256.Signing.PublicKey {
            switch self {
            case .secureEnclave(let key):
                return key.publicKey
            case .software(let key):
                return key.publicKey
            }
        }
    }

    private let key: PrivateKeyHolder

    // MARK: - Init

    /// Loads or generates the signing key. Call once at app launch.
    init() throws {
        if let existingKey = try Self.loadKeyFromKeychain() {
            self.key = existingKey
        } else {
            let newKey = try Self.generateAndStoreKey()
            self.key = newKey
        }
    }

    // MARK: - Public Interface

    /// The public key in DER (X.509 SubjectPublicKeyInfo) format.
    /// Share this with peers so they can verify signatures.
    var publicKeyData: Data {
        key.publicKey.derRepresentation
    }

    /// Signs data with the private key. Returns DER-encoded ECDSA signature.
    func sign(_ data: Data) throws -> Data {
        do {
            return try key.sign(data)
        } catch {
            throw SignerError.signingFailed(error)
        }
    }

    /// Verifies an ECDSA signature against data and a DER-encoded public key.
    /// Returns `false` for any error — invalid signatures are expected in mesh networking.
    static func verify(signature: Data, data: Data, publicKey: Data) -> Bool {
        guard let pubKey = try? P256.Signing.PublicKey(derRepresentation: publicKey),
              let ecdsaSignature = try? P256.Signing.ECDSASignature(derRepresentation: signature) else {
            return false
        }
        return pubKey.isValidSignature(ecdsaSignature, for: data)
    }

    /// Removes the signing key from Keychain. Use for testing or account reset.
    func deleteKey() {
        Self.deleteKeyFromKeychain()
    }

    // MARK: - Secure Enclave Detection

    private static var isSecureEnclaveAvailable: Bool {
        SecureEnclave.isAvailable
    }

    // MARK: - Key Generation

    private static func generateAndStoreKey() throws -> PrivateKeyHolder {
        if isSecureEnclaveAvailable {
            do {
                let key = try SecureEnclave.P256.Signing.PrivateKey()
                try saveToKeychain(data: key.dataRepresentation)
                return .secureEnclave(key)
            } catch {
                throw SignerError.keyGenerationFailed
            }
        } else {
            let key = P256.Signing.PrivateKey()
            do {
                try saveToKeychain(data: key.rawRepresentation)
            } catch {
                throw error
            }
            return .software(key)
        }
    }

    // MARK: - Key Loading

    private static func loadKeyFromKeychain() throws -> PrivateKeyHolder? {
        guard let data = loadFromKeychain() else {
            return nil
        }

        if isSecureEnclaveAvailable {
            // Secure Enclave keys are reconstructed from dataRepresentation
            do {
                let key = try SecureEnclave.P256.Signing.PrivateKey(
                    dataRepresentation: data
                )
                return .secureEnclave(key)
            } catch {
                // Stored key is corrupt or from a different device — delete and return nil
                // so a fresh key is generated.
                deleteKeyFromKeychain()
                return nil
            }
        } else {
            // Software key from rawRepresentation
            do {
                let key = try P256.Signing.PrivateKey(rawRepresentation: data)
                return .software(key)
            } catch {
                deleteKeyFromKeychain()
                return nil
            }
        }
    }

    // MARK: - Keychain Operations

    private static func saveToKeychain(data: Data) throws {
        // Delete any existing item first
        deleteKeyFromKeychain()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SignerError.keychainSaveFailed(status)
        }
    }

    private static func loadFromKeychain() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            return nil
        }

        return result as? Data
    }

    private static func deleteKeyFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]

        SecItemDelete(query as CFDictionary)
    }
}
