enum AppTab: String, CaseIterable, Identifiable {
    case clipboard = "Clipboard"
    case music = "Music"
    case timer = "Timer"
    case screenshots = "Screenshots"

    var id: String { rawValue }
}
