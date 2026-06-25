import Foundation

struct Photo: Identifiable, Hashable, Codable {
    let id: UUID
    let rollID: UUID
    let localPath: String
    let createdAt: Date
    let exposureNumber: Int

    private enum CodingKeys: String, CodingKey {
        case id
        case rollID = "rollId"
        case localPath
        case createdAt
        case exposureNumber
    }

    static let placeholder = Photo(
        id: UUID(),
        rollID: Roll.placeholder.id,
        localPath: "",
        createdAt: .now,
        exposureNumber: 1
    )
}
