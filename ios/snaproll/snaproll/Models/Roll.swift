import Foundation

enum RollStatus: String, Codable, Hashable {
    case inProgress
    case completed
    case revealed
}

struct Roll: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var film: FilmStock
    var shotLimit: Int
    var exposuresUsed: Int
    var status: RollStatus
    var createdAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case film
        case shotLimit
        case exposuresUsed
        case status
        case createdAt
    }

    init(
        id: UUID,
        name: String,
        film: FilmStock = .kodakGold200,
        shotLimit: Int,
        exposuresUsed: Int = 0,
        status: RollStatus = .inProgress,
        createdAt: Date
    ) {
        self.id = id
        self.name = name
        self.film = film
        self.shotLimit = shotLimit
        self.exposuresUsed = min(max(exposuresUsed, 0), shotLimit)
        if self.exposuresUsed >= shotLimit {
            self.status = status == .revealed ? .revealed : .completed
        } else {
            self.status = .inProgress
        }
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        film = try container.decodeIfPresent(FilmStock.self, forKey: .film) ?? .kodakGold200
        shotLimit = try container.decode(Int.self, forKey: .shotLimit)
        let decodedExposuresUsed = try container.decodeIfPresent(Int.self, forKey: .exposuresUsed) ?? 0
        exposuresUsed = min(max(decodedExposuresUsed, 0), shotLimit)
        let decodedStatus = try container.decodeIfPresent(RollStatus.self, forKey: .status) ?? .inProgress
        if exposuresUsed >= shotLimit {
            status = decodedStatus == .revealed ? .revealed : .completed
        } else {
            status = .inProgress
        }
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }

    var exposuresRemaining: Int {
        max(0, shotLimit - exposuresUsed)
    }

    var capturedMemories: Int {
        exposuresUsed
    }

    var progressValue: Double {
        guard shotLimit > 0 else { return 0 }
        return Double(capturedMemories) / Double(shotLimit)
    }

    var captureProgressText: String {
        "\(capturedMemories) / \(shotLimit)"
    }

    var completionStatusTitle: String {
        if isRevealed {
            return "Ready to revisit"
        }

        return isFinished ? "Ready to reveal" : "Unlocks when full"
    }

    var completionStatusDetail: String {
        if isRevealed {
            return "Your roll has been opened and is ready to revisit."
        }

        return isFinished ? "Every exposure has been used. Reveal the roll when you're ready." : "\(exposuresRemaining) exposures left to finish this roll."
    }

    var footerStatusText: String {
        switch status {
        case .inProgress:
            return "In progress"
        case .completed:
            return "Ready to reveal"
        case .revealed:
            return "Revealed"
        }
    }

    var isFinished: Bool {
        isCompleted || isRevealed
    }

    var isCompleted: Bool {
        status == .completed || (status != .revealed && exposuresRemaining == 0)
    }

    var isRevealed: Bool {
        status == .revealed
    }

    func registeringCapture() -> Roll {
        let nextExposureCount = min(shotLimit, exposuresUsed + 1)

        return Roll(
            id: id,
            name: name,
            film: film,
            shotLimit: shotLimit,
            exposuresUsed: nextExposureCount,
            status: nextExposureCount >= shotLimit ? .completed : .inProgress,
            createdAt: createdAt
        )
    }

    func markingRevealed() -> Roll {
        Roll(
            id: id,
            name: name,
            film: film,
            shotLimit: shotLimit,
            exposuresUsed: exposuresUsed,
            status: .revealed,
            createdAt: createdAt
        )
    }

    static let placeholder = Roll(
        id: UUID(),
        name: "Summer Walks",
        film: .kodakGold200,
        shotLimit: 24,
        exposuresUsed: 12,
        createdAt: .now
    )
}
