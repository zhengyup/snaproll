import Foundation

struct ShareSheetPayload: Identifiable {
    let id = UUID()
    let items: [Any]
}

struct UserFeedbackNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
