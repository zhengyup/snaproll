import Foundation

struct V2SupabaseConfiguration: Sendable {
    let url: URL
    let anonKey: String

    nonisolated static func load(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> V2SupabaseConfiguration {
        let urlString = environment["SNAPROLL_SUPABASE_URL"]
            ?? (bundle.object(forInfoDictionaryKey: "SNAPROLL_SUPABASE_URL") as? String)
            ?? ""
        let anonKey = environment["SNAPROLL_SUPABASE_ANON_KEY"]
            ?? (bundle.object(forInfoDictionaryKey: "SNAPROLL_SUPABASE_ANON_KEY") as? String)
            ?? ""

        let trimmedURLString = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAnonKey = anonKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedURLString.isEmpty else {
            throw V2RepositoryError.notConfigured(
                "Snaproll V2 Supabase URL is missing. Set SNAPROLL_SUPABASE_URL in build settings or the scheme environment."
            )
        }

        guard let url = URL(string: trimmedURLString) else {
            throw V2RepositoryError.notConfigured(
                "Snaproll V2 Supabase URL is invalid."
            )
        }

        guard !trimmedAnonKey.isEmpty else {
            throw V2RepositoryError.notConfigured(
                "Snaproll V2 Supabase anon key is missing. Set SNAPROLL_SUPABASE_ANON_KEY in build settings or the scheme environment."
            )
        }

        return V2SupabaseConfiguration(url: url, anonKey: trimmedAnonKey)
    }

    nonisolated static func loadDefault() throws -> V2SupabaseConfiguration {
        try load()
    }
}
