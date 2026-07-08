import Combine
import Foundation

final class DevelopmentAuthIdentityStore: DevelopmentAuthIdentityProviding, @unchecked Sendable {
    let initialIdentity: DevelopmentAuthIdentity

    private let defaults: UserDefaults
    private let defaultsKey = "snaproll.v2.development-auth.selected-identity"
    private let queue = DispatchQueue(label: "snaproll.v2.development-auth.identity-store")
    private var currentIdentity: DevelopmentAuthIdentity

    init(
        defaults: UserDefaults = .standard,
        defaultIdentity: DevelopmentAuthIdentity
    ) {
        self.defaults = defaults

        if let rawValue = defaults.string(forKey: defaultsKey),
           let persistedIdentity = DevelopmentAuthIdentity(rawValue: rawValue) {
            self.initialIdentity = persistedIdentity
        } else {
            self.initialIdentity = defaultIdentity
        }

        self.currentIdentity = initialIdentity
    }

    func selectedIdentity() async -> DevelopmentAuthIdentity {
        queue.sync { currentIdentity }
    }

    func setSelectedIdentity(_ identity: DevelopmentAuthIdentity) {
        queue.sync {
            currentIdentity = identity
            defaults.set(identity.rawValue, forKey: defaultsKey)
        }
    }
}

@MainActor
final class DevelopmentAuthSettings: ObservableObject {
    @Published private(set) var selectedIdentity: DevelopmentAuthIdentity

    private let identityStore: DevelopmentAuthIdentityStore

    init(identityStore: DevelopmentAuthIdentityStore) {
        self.identityStore = identityStore
        self.selectedIdentity = identityStore.initialIdentity
    }

    func selectIdentity(_ identity: DevelopmentAuthIdentity) async {
        selectedIdentity = identity
        identityStore.setSelectedIdentity(identity)
    }
}
