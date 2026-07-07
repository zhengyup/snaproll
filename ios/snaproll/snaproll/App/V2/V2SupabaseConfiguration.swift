import Foundation

struct V2SupabaseConfiguration: Sendable {
    let url: URL
    let publishableKey: String

    nonisolated static func load(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> V2SupabaseConfiguration {
        let dotenv = DotenvConfigurationLoader.load(from: bundle)
        let urlString = environment["SNAPROLL_SUPABASE_URL"]
            ?? (bundle.object(forInfoDictionaryKey: "SNAPROLL_SUPABASE_URL") as? String)
            ?? dotenv["SNAPROLL_SUPABASE_URL"]
            ?? ""
        let publishableKey = environment["SNAPROLL_SUPABASE_PUBLISHABLE_KEY"]
            ?? (bundle.object(forInfoDictionaryKey: "SNAPROLL_SUPABASE_PUBLISHABLE_KEY") as? String)
            ?? dotenv["SNAPROLL_SUPABASE_PUBLISHABLE_KEY"]
            ?? environment["SNAPROLL_SUPABASE_ANON_KEY"]
            ?? (bundle.object(forInfoDictionaryKey: "SNAPROLL_SUPABASE_ANON_KEY") as? String)
            ?? dotenv["SNAPROLL_SUPABASE_ANON_KEY"]
            ?? ""

        let trimmedURLString = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPublishableKey = publishableKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedURLString.isEmpty else {
            throw V2RepositoryError.notConfigured(
                "Snaproll V2 Supabase URL is missing. Set SNAPROLL_SUPABASE_URL in build settings, the scheme environment, or .env."
            )
        }

        guard let url = URL(string: trimmedURLString) else {
            throw V2RepositoryError.notConfigured(
                "Snaproll V2 Supabase URL is invalid."
            )
        }

        guard !trimmedPublishableKey.isEmpty else {
            throw V2RepositoryError.notConfigured(
                "Snaproll V2 Supabase publishable key is missing. Set SNAPROLL_SUPABASE_PUBLISHABLE_KEY in build settings, the scheme environment, or .env."
            )
        }

        return V2SupabaseConfiguration(url: url, publishableKey: trimmedPublishableKey)
    }

    nonisolated static func loadDefault() throws -> V2SupabaseConfiguration {
        try load()
    }
}

private enum DotenvConfigurationLoader {
    static func load(from bundle: Bundle) -> [String: String] {
        let candidateURLs: [URL?] = [
            bundle.url(forResource: ".env", withExtension: nil),
            bundle.url(forResource: "development", withExtension: "env"),
        ]

        for candidateURL in candidateURLs {
            guard
                let url = candidateURL,
                let contents = try? String(contentsOf: url, encoding: .utf8)
            else {
                continue
            }

            return parse(contents: contents)
        }

        return [:]
    }

    private static func parse(contents: String) -> [String: String] {
        contents
            .split(whereSeparator: \.isNewline)
            .reduce(into: [String: String]()) { partialResult, rawLine in
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

                guard !line.isEmpty, !line.hasPrefix("#"), let separatorIndex = line.firstIndex(of: "=") else {
                    return
                }

                let key = String(line[..<separatorIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
                var value = String(line[line.index(after: separatorIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)

                if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                    value.removeFirst()
                    value.removeLast()
                }

                if !key.isEmpty {
                    partialResult[key] = value
                }
            }
    }
}
