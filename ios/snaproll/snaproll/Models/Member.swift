import Foundation

struct Member: Identifiable, Hashable {
    let id: UUID
    var displayName: String
    var shotsUsed: Int

    static let placeholder = Member(
        id: UUID(),
        displayName: "You",
        shotsUsed: 0
    )
}
