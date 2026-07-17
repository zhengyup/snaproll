import Foundation

enum FilmStockType: String, Codable, Hashable {
    case color
    case blackAndWhite

    var displayName: String {
        switch self {
        case .color:
            return "Color"
        case .blackAndWhite:
            return "Legacy"
        }
    }
}

enum FilmStock: String, CaseIterable, Codable, Hashable, Identifiable {
    case kodakGold200
    case fujifilmSuperia400
    case ilfordHP5Plus

    static var allCases: [FilmStock] {
        [.kodakGold200, .fujifilmSuperia400]
    }

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .kodakGold200:
            return "Warm"
        case .fujifilmSuperia400:
            return "Cool"
        case .ilfordHP5Plus:
            return "Legacy"
        }
    }

    var shortDescription: String {
        switch self {
        case .kodakGold200:
            return "Golden, soft, nostalgic everyday color."
        case .fujifilmSuperia400:
            return "Cooler greens and blues with a clean snapshot feel."
        case .ilfordHP5Plus:
            return "Legacy rendering style for older rolls."
        }
    }

    var type: FilmStockType {
        switch self {
        case .kodakGold200, .fujifilmSuperia400:
            return .color
        case .ilfordHP5Plus:
            return .blackAndWhite
        }
    }

    var typeLabel: String {
        displayName
    }

    var shortBrand: String {
        switch self {
        case .kodakGold200:
            return "WARM"
        case .fujifilmSuperia400:
            return "COOL"
        case .ilfordHP5Plus:
            return "LEGACY"
        }
    }

    var accentHex: String {
        switch self {
        case .kodakGold200:
            return "#F0B90B"
        case .fujifilmSuperia400:
            return "#31A35B"
        case .ilfordHP5Plus:
            return "#C8C8C8"
        }
    }

    var secondaryHex: String {
        switch self {
        case .kodakGold200:
            return "#D3442D"
        case .fujifilmSuperia400:
            return "#1F5C3D"
        case .ilfordHP5Plus:
            return "#444444"
        }
    }
}
