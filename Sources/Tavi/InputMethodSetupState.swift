enum InputMethodSetupState: Equatable {
    case moveToApplications
    case notInstalled
    case updateAvailable
    case working(String)
    case needsSelection
    case ready
    case failed(String)
}
