enum AppTab: String, CaseIterable, Identifiable {
    case clipboard = "Clipboard"
    case meetings = "Meetings"
    case notes = "Notes"
    case screenshots = "Screenshots"
    case settings = "Settings"

    var id: String { rawValue }
}
