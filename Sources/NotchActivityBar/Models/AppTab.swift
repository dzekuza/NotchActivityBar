enum AppTab: String, CaseIterable, Identifiable {
    case clipboard = "Clipboard"
    case notes = "Notes"
    case meetings = "Meetings"
    case screenshots = "Screenshots"
    case settings = "Settings"

    var id: String { rawValue }
}
