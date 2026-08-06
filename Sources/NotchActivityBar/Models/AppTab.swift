enum AppTab: String, CaseIterable, Identifiable {
    case clipboard = "Clipboard"
    case meetings = "Meetings"
    case music = "Music"
    case timer = "Timer"
    case screenshots = "Screenshots"
    case settings = "Settings"

    var id: String { rawValue }
}
