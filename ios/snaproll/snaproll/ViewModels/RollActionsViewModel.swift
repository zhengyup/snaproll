import Combine
import Foundation

@MainActor
final class RollActionsViewModel: ObservableObject {
    @Published private(set) var isPerformingExport = false
    @Published var feedbackNotice: UserFeedbackNotice?
    @Published var shareSheetPayload: ShareSheetPayload?

    private let exportService: ExportService

    init(exportService: ExportService? = nil) {
        self.exportService = exportService ?? ExportService()
    }

    func exportRoll(_ roll: Roll) {
        guard roll.isRevealed else {
            feedbackNotice = UserFeedbackNotice(
                title: "Export Unavailable",
                message: "Reveal this roll before exporting its memories."
            )
            return
        }

        isPerformingExport = true

        Task {
            defer {
                isPerformingExport = false
            }

            do {
                let summary = try await exportService.exportRenderedRollToLibrary(for: roll)
                feedbackNotice = UserFeedbackNotice(
                    title: "Export Finished",
                    message: "\(summary.exportedCount) exported\n\(summary.failedCount) failed"
                )
            } catch {
                feedbackNotice = UserFeedbackNotice(
                    title: "Export Failed",
                    message: error.localizedDescription
                )
            }
        }
    }

    func shareRoll(_ roll: Roll) {
        guard roll.isRevealed else {
            feedbackNotice = UserFeedbackNotice(
                title: "Share Unavailable",
                message: "Reveal this roll before sharing its memories."
            )
            return
        }

        do {
            let shareItems = try exportService.shareItemsForRenderedRoll(roll)
            shareSheetPayload = ShareSheetPayload(items: shareItems)
        } catch {
            feedbackNotice = UserFeedbackNotice(
                title: "Share Failed",
                message: error.localizedDescription
            )
        }
    }
}
