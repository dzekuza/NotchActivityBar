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
        case camera

        var id: String { rawValue }

        /// The grants a meeting recording actually depends on. Camera is listed
        /// in the UI too (Privacy Guard needs it) but never blocks recording.
        static let recording: [Kind] = [.microphone, .speechRecognition, .screenRecording]

        var title: String {
            switch self {
            case .microphone: "Microphone"
            case .speechRecognition: "Speech Recognition"
            case .screenRecording: "Screen Recording"
            case .camera: "Camera"
            }
        }

        var detail: String {
            switch self {
            case .microphone: "Records your side of a call."
            case .speechRecognition: "Transcribes on-device with Apple Speech."
            case .screenRecording: "Captures system audio — the other participants."
            case .camera: "Lets Privacy Guard lock the camera."
            }
        }

        /// Anchor understood by the Privacy & Security preference pane.
        var settingsAnchor: String {
            switch self {
            case .microphone: "Privacy_Microphone"
            case .speechRecognition: "Privacy_SpeechRecognition"
            case .screenRecording: "Privacy_ScreenCapture"
            case .camera: "Privacy_Camera"
            }
        }

        /// Service name `tccutil` uses for this permission.
        var tccService: String {
            switch self {
            case .microphone: "Microphone"
            case .speechRecognition: "SpeechRecognition"
            case .screenRecording: "ScreenCapture"
            case .camera: "Camera"
            }
        }
    }

    private(set) var microphone: Status = .notDetermined
    private(set) var speechRecognition: Status = .notDetermined
    private(set) var screenRecording: Status = .notDetermined
    private(set) var camera: Status = .notDetermined

    /// Set when a `tccutil` reset couldn't be run, so the UI can fall back to
    /// telling the user the exact command instead of failing silently.
    private(set) var resetFailure: String?

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
        case .camera: camera
        }
    }

    /// Every permission that must be granted before a meeting can be recorded
    /// with both sides of the conversation captured.
    var blockingIssues: [Kind] {
        Kind.recording.filter { !status(for: $0).isGranted }
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

        let cam = Self.captureStatus(for: .video)
        if cam != camera { camera = cam }

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
        case .microphone: requestCaptureAccess(for: .audio, kind: .microphone)
        case .camera: requestCaptureAccess(for: .video, kind: .camera)
        case .speechRecognition: requestSpeechRecognition()
        case .screenRecording: requestScreenRecording()
        }
    }

    /// Clears the recorded TCC decision for one permission, so macOS will show
    /// its native prompt again next time we ask.
    ///
    /// This is the only way back once a decision exists: macOS prompts exactly
    /// once per app per service, and from then on `requestAccess` returns the
    /// stored answer immediately without showing anything. Toggling the switch
    /// in System Settings works too, but a grant that was never recorded (the
    /// app was denied before it ever appeared in the list) leaves nothing to
    /// toggle — hence the reset.
    func reset(_ kind: Kind) {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let service = kind.tccService
        resetFailure = nil

        Task { @MainActor in
            let succeeded = await Task.detached {
                Self.runTCCUtilReset(service: service, bundleID: bundleID)
            }.value

            guard succeeded else {
                self.resetFailure = "Couldn't reset \(kind.title) automatically. In Terminal, run: tccutil reset \(service) \(bundleID)"
                return
            }

            // The decision is gone, so this session's "we already asked" memory
            // has to go with it or the UI would keep reporting denied.
            if kind == .screenRecording { self.hasRequestedScreenRecording = false }
            self.refresh()

            // Screen Recording can't re-prompt usefully in an already-running
            // process, so leave that one to the Relaunch affordance.
            if kind != .screenRecording { self.request(kind) }
        }
    }

    private nonisolated static func runTCCUtilReset(service: String, bundleID: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", service, bundleID]
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            NSLog("PermissionsController: tccutil reset \(service) failed — \(error.localizedDescription)")
            return false
        }
    }

    func openSystemSettings(for kind: Kind) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(kind.settingsAnchor)") else { return }
        NSWorkspace.shared.open(url)
    }

    private func requestCaptureAccess(for mediaType: AVMediaType, kind: Kind) {
        guard status(for: kind) == .notDetermined else {
            openSystemSettings(for: kind)
            return
        }
        Task { @MainActor in
            _ = await PermissionPrompt.around { await AVCaptureDevice.requestAccess(for: mediaType) }
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
