import Foundation

enum FilmStockType: String, Codable, Hashable {
    case color
    case blackAndWhite

    var displayName: String {
        switch self {
        case .color:
            return "Color"
        case .blackAndWhite:
            return "Black & White"
        }
    }
}

enum FilmStock: String, CaseIterable, Codable, Hashable, Identifiable {
    case kodakGold200
    case fujifilmSuperia400
    case ilfordHP5Plus

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .kodakGold200:
            return "Kodak Gold 200"
        case .fujifilmSuperia400:
            return "Fujifilm Superia 400"
        case .ilfordHP5Plus:
            return "Ilford HP5 Plus"
        }
    }

    var shortDescription: String {
        switch self {
        case .kodakGold200:
            return "Warm, golden, nostalgic everyday color."
        case .fujifilmSuperia400:
            return "Cooler greens and blues, casual outdoor snapshot feel."
        case .ilfordHP5Plus:
            return "Black-and-white, contrasty, documentary feel."
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
        type.displayName
    }

    var shortBrand: String {
        switch self {
        case .kodakGold200:
            return "KODAK"
        case .fujifilmSuperia400:
            return "FUJI"
        case .ilfordHP5Plus:
            return "ILFORD"
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
