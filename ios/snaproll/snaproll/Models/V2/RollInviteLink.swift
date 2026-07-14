import Foundation

struct RollInviteLink: Identifiable, Sendable, Equatable {
    let token: String

    var id: String { token }

    init?(token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        self.token = trimmed
    }

    var url: URL {
        url(httpsDomain: AppConfig.V2.inviteHTTPSDomain)
    }

    func url(httpsDomain: String?) -> URL {
        if let domain = httpsDomain,
           !domain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let encodedToken = token.addingPercentEncoding(withAllowedCharacters: Self.pathTokenAllowedCharacters),
           let url = URL(string: "https://\(domain)/join/\(encodedToken)") {
            return url
        }

        var components = URLComponents()
        components.scheme = AppConfig.V2.inviteURLScheme
        components.host = "join"
        components.queryItems = [URLQueryItem(name: "token", value: token)]
        return components.url ?? URL(string: "\(AppConfig.V2.inviteURLScheme)://join")!
    }

    static func parse(_ url: URL) -> RollInviteLink? {
        parse(url, httpsDomain: AppConfig.V2.inviteHTTPSDomain)
    }

    static func parse(_ url: URL, httpsDomain: String?) -> RollInviteLink? {
        if let customSchemeInvite = parseCustomScheme(url) {
            return customSchemeInvite
        }

        if let httpsInvite = parseHTTPS(url, httpsDomain: httpsDomain) {
            return httpsInvite
        }

        return nil
    }

    private static func parseCustomScheme(_ url: URL) -> RollInviteLink? {
        guard url.scheme?.lowercased() == AppConfig.V2.inviteURLScheme.lowercased(),
              url.host?.lowercased() == "join" else {
            return nil
        }

        guard let token = tokenFromQuery(url) else {
            return nil
        }

        return RollInviteLink(token: token)
    }

    private static func parseHTTPS(_ url: URL, httpsDomain: String?) -> RollInviteLink? {
        guard url.scheme?.lowercased() == "https",
              let configuredDomain = httpsDomain?.lowercased(),
              url.host?.lowercased() == configuredDomain else {
            return nil
        }

        if let token = tokenFromPath(url) {
            return RollInviteLink(token: token)
        }

        guard let token = tokenFromQuery(url) else {
            return nil
        }

        return RollInviteLink(token: token)
    }

    private static func tokenFromPath(_ url: URL) -> String? {
        guard let percentEncodedPath = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath else {
            return nil
        }

        let components = percentEncodedPath
            .split(separator: "/")
            .map(String.init)
        guard components.count == 2,
              components[0].lowercased() == "join" else {
            return nil
        }

        return components[1].removingPercentEncoding ?? components[1]
    }

    private static func tokenFromQuery(_ url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "token" })?
            .value
    }

    private static var pathTokenAllowedCharacters: CharacterSet {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return allowed
    }
}
