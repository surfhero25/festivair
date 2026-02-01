import Foundation
import AuthenticationServices

/// Handles Sign in with Apple authentication
@MainActor
final class AppleAuthService: NSObject, ObservableObject {

    // MARK: - Published State
    @Published var isAuthenticated = false
    @Published var userIdentifier: String?
    @Published var fullName: PersonNameComponents?
    @Published var email: String?
    @Published var error: Error?

    // MARK: - Private
    private var authContinuation: CheckedContinuation<ASAuthorization, Error>?

    // MARK: - Init
    override init() {
        super.init()
        // Check if we have a stored Apple ID
        checkExistingCredential()
    }

    // MARK: - Public API

    /// Check if user is already signed in with Apple
    func checkExistingCredential() {
        guard let userIdentifier = KeychainHelper.load(.appleUserIdentifier) else {
            print("[AppleAuth] No stored Apple ID")
            return
        }

        // Verify the credential is still valid
        let provider = ASAuthorizationAppleIDProvider()
        provider.getCredentialState(forUserID: userIdentifier) { [weak self] state, error in
            Task { @MainActor in
                switch state {
                case .authorized:
                    print("[AppleAuth] Existing credential is valid")
                    self?.userIdentifier = userIdentifier
                    self?.isAuthenticated = true
                case .revoked, .notFound:
                    print("[AppleAuth] Credential revoked or not found, clearing")
                    self?.clearCredentials()
                case .transferred:
                    print("[AppleAuth] Credential transferred to another device")
                @unknown default:
                    break
                }
            }
        }
    }

    /// Initiate Sign in with Apple flow
    func signIn() async throws -> (userIdentifier: String, fullName: PersonNameComponents?, email: String?) {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]

        let authorization = try await performRequest(request)

        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            throw AppleAuthError.invalidCredential
        }

        // Store the user identifier in Keychain (persists across reinstalls)
        KeychainHelper.save(credential.user, for: .appleUserIdentifier)

        // Email is only provided on first sign in
        if let email = credential.email {
            KeychainHelper.save(email, for: .appleEmail)
        }

        // Update state
        self.userIdentifier = credential.user
        self.fullName = credential.fullName
        self.email = credential.email ?? KeychainHelper.load(.appleEmail)
        self.isAuthenticated = true

        print("[AppleAuth] Sign in successful - userId: \(credential.user)")

        return (credential.user, credential.fullName, self.email)
    }

    /// Sign out (clears local credentials)
    func signOut() {
        clearCredentials()
    }

    // MARK: - Private

    private func performRequest(_ request: ASAuthorizationAppleIDRequest) async throws -> ASAuthorization {
        return try await withCheckedThrowingContinuation { continuation in
            self.authContinuation = continuation

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    private func clearCredentials() {
        KeychainHelper.delete(.appleUserIdentifier)
        KeychainHelper.delete(.appleEmail)
        userIdentifier = nil
        fullName = nil
        email = nil
        isAuthenticated = false
    }
}

// MARK: - ASAuthorizationControllerDelegate
extension AppleAuthService: ASAuthorizationControllerDelegate {

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        Task { @MainActor in
            authContinuation?.resume(returning: authorization)
            authContinuation = nil
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        Task { @MainActor in
            authContinuation?.resume(throwing: error)
            authContinuation = nil
        }
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding
extension AppleAuthService: ASAuthorizationControllerPresentationContextProviding {

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        // Use MainActor.assumeIsolated since this is always called on main thread by Apple's framework
        return MainActor.assumeIsolated {
            guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = scene.windows.first else {
                return UIWindow()
            }
            return window
        }
    }
}

// MARK: - Errors
enum AppleAuthError: LocalizedError {
    case invalidCredential
    case cancelled
    case unknown

    var errorDescription: String? {
        switch self {
        case .invalidCredential:
            return "Invalid credential received from Apple"
        case .cancelled:
            return "Sign in was cancelled"
        case .unknown:
            return "An unknown error occurred"
        }
    }
}
