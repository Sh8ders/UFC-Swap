import Foundation

@MainActor
final class ActionFeedbackStore: ObservableObject {
    @Published private(set) var latestMessage = "Ready"
    @Published private(set) var latestIsError = false

    func post(_ message: String, isError: Bool = false) {
        latestMessage = message
        latestIsError = isError
        AppLogger.startup(message)
    }
}
