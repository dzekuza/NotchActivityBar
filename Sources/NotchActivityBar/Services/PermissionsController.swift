import AppKit
import AVFoundation
import CoreGraphics
import Foundation
import Observation
import Speech

/// Single source of truth for the TCC permissions the recording pipeline needs,
/// plus the plumbing to *re-read* them.
///
/// Before this existed, every permission was only ever sampled at the moment a
/// recording started (`AVCaptureDevice.authorizationStatus` inside
/// `MeetingRecorderController.startRecording`, `SFSpeechRecognizer.requestAuthorization`
/// inside `AppleSpeechTranscriber.connect`) and Screen Recording was never
/// checked at all. Nothing in the app ever showed the user what was granted, and
/// nothing re-checked after they changed a switch in System Settings — so a
/// stale/denied grant looked exactly like a silent failure to record.
@MainActor
@Observable
final class PermissionsController {
    enum Status: Equatable {
        case granted
        case denied
        case notDetermined

        var isGranted: Bool { self == .granted }
    }

    enum Kind: String, CaseIterable, Identifiable {
        case microphone
        case speechRecognition
        case screenRecording

        var id: String { rawValue }

        var title: String {
            switch self {
            case .microphone: "Microphone"
            case .speechRecognition: "Speech Recognition"
            case .screenRecording: "Screen Recording"
            }
        }

        var detail: String {
            switch self {
            case .microphone: "Records your side of a call."
            case .speechRecognition: "Transcribes on-device with Apple Speech."
            case .screenRecording: "Captures system audio — the other participants."
            }
        }

        /// Anchor understood by the Privacy & Security preference pane.
        var settingsAnchor: String {
            switch self {
            case .microphone: "Privacy_Microphone"
            case .speechRecognition: "Privacy_SpeechRecognition"
            case .screenRecording: "Privacy_ScreenCapture"
            }
        }
    }

    private(set) var microphone: Status = .notDetermined
    private(set) var speechRecognition: Status = .notDetermined
    private(set) var screenRecording: Status = .notDetermined

    /// macOS binds a Screen Recording grant to the process that was running when
    /// the grant was made: a process that launched unauthorized keeps getting
    /// denied by ScreenCaptureKit even after the user flips the switch, until it
    /// is relaunched. (This is why the system's own alert offers "Quit & Reopen".)
    /// When we observe the grant appearing mid-session, the running process is
    /// still stuck, so tell the user rather than letting them retry forever.
    private(set) var screenRecordingNeedsRelaunch = false

    private let screenRecordingGrantedAtLaunch: Bool
    private var hasRequestedScreenRecording = false

    /// Observers are intentionally never torn down — this object lives for the
    /// whole process lifetime, and a `deinit` on a `@MainActor` class can't
    /// safely touch main-actor state anyway.
    private var observers: [any NSObjectProtocol] = []

    init() {
        screenRecordingGrantedAtLaunch = CGPreflightScreenCaptureAccess()
        refresh()
        observeReturnFromSystemSettings()
    }

    func status(for kind: Kind) -> Status {
        switch kind {
        case .microphone: microphone
        case .speechRecognition: speechRecognition
        case .screenRecording: screenRecording
        }
    }

    /// Every permission that must be granted before a meeting can be recorded
    /// with both sides of the conversation captured.
    var blockingIssues: [Kind] {
        Kind.allCases.filter { !status(for: $0).isGranted }
    }

    /// Re-reads every status from the system. Called on app activation, on wake,
    /// whenever the Settings tab appears, and before each recording starts, so
    /// nothing here is ever older than the user's last trip to System Settings.
    ///
    /// Assignments are guarded on change: `@Observable` notifies on every write
    /// regardless of value, and this runs on each app switch — writing
    /// unconditionally would invalidate the settings view a few times a minute
    /// for nothing.
    func refresh() {
        let mic = Self.captureStatus(for: .audio)
        if mic != microphone { microphone = mic }

        let speech = Self.speechStatus()
        if speech != speechRecognition { speechRecognition = speech }

        let screenGranted = CGPreflightScreenCaptureAccess()
        // CoreGraphics can't distinguish "never asked" from "asked and refused",
        // so fall back to whether *we* have driven a request this session.
        let screen: Status = screenGranted ? .granted : (hasRequestedScreenRecording ? .denied : .notDetermined)
        if screen != screenRecording { screenRecording = screen }

        let needsRelaunch = screenGranted && !screenRecordingGrantedAtLaunch
        if needsRelaunch != screenRecordingNeedsRelaunch { screenRecordingNeedsRelaunch = needsRelaunch }
    }

    // MARK: - Requesting

    /// Drives the whole grant flow for one permission: prompt when the system
    /// will still prompt, otherwise hand the user off to System Settings (macOS
    /// only ever prompts once per app — after a denial the request call returns
    /// `false` immediately without showing anything).
    func request(_ kind: Kind) {
        switch kind {
        case .microphone: requestMicrophone()
        case .speechRecognition: requestSpeechRecognition()
        case .screenRecording: requestScreenRecording()
        }
    }

    func openSystemSettings(for kind: Kind) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(kind.settingsAnchor)") else { return }
        NSWorkspace.shared.open(url)
    }

    private func requestMicrophone() {
        guard microphone == .notDetermined else {
            openSystemSettings(for: .microphone)
            return
        }
        Task { @MainActor in
            _ = await PermissionPrompt.around { await AVCaptureDevice.requestAccess(for: .audio) }
            self.refresh()
        }
    }

    private func requestSpeechRecognition() {
        guard speechRecognition == .notDetermined else {
            openSystemSettings(for: .speechRecognition)
            return
        }
        PermissionPrompt.activate()
        // Speech invokes this handler off the main thread despite being written
        // inside a `@MainActor` type, so it must be explicitly `@Sendable` —
        // without that Swift infers main-actor isolation and traps at runtime.
        SFSpeechRecognizer.requestAuthorization { @Sendable [weak self] _ in
            Task { @MainActor in
                PermissionPrompt.restore()
                self?.refresh()
            }
        }
    }

    private func requestScreenRecording() {
        guard screenRecording != .granted else { return }
        hasRequestedScreenRecording = true

        PermissionPrompt.activate()
        let granted = CGRequestScreenCaptureAccess()
        PermissionPrompt.restore()

        if !granted {
            // Either the user just declined, or macOS never prompted because a
            // decision is already on record. Either way System Settings is the
            // only remaining path.
            openSystemSettings(for: .screenRecording)
        }
        refresh()
    }

    // MARK: - Staying fresh

    /// Grants made in System Settings don't notify us, so the app would keep
    /// showing (and acting on) whatever it read last. Re-reading whenever the
    /// frontmost app changes covers the case that actually matters: the user
    /// flipping a switch in System Settings and coming back.
    private func observeReturnFromSystemSettings() {
        let workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        let wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        observers = [workspaceObserver, wakeObserver]
    }

    // MARK: - Raw status reads

    private static func captureStatus(for mediaType: AVMediaType) -> Status {
        switch AVCaptureDevice.authorizationStatus(for: mediaType) {
        case .authorized: .granted
        case .notDetermined: .notDetermined
        case .denied, .restricted: .denied
        @unknown default: .denied
        }
    }

    private static func speechStatus() -> Status {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: .granted
        case .notDetermined: .notDetermined
        case .denied, .restricted: .denied
        @unknown default: .denied
        }
    }
}
