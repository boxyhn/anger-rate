import AppKit
import CryptoKit
import IOKit
import SwiftUI
import UserNotifications
import AngerCore

@MainActor final class AppModel: ObservableObject {
    @Published var score: Double = 0
    @Published var events: [ScoredEvent] = []
    @Published var profile: PersonalProfile = .starter
    @Published var draftProfile: PersonalProfile?
    @Published var isMonitoring: Bool
    @Published var status = "세션을 확인하고 있어요"
    @Published var analysisStatus = ""
    @Published var isAnalyzing = false
    @Published var syncPath: String
    @Published var devices: [DeviceSnapshot] = []
    @Published var halfLifeMinutes: Double = 5
    @Published var notificationsEnabled: Bool { didSet { defaults.set(notificationsEnabled, forKey: "notifications") } }
    @Published var temperatureUnit: TemperatureUnit { didSet { defaults.set(temperatureUnit.rawValue, forKey: "temperatureUnit") } }
    @Published var appLanguage: AppLanguage {
        didSet {
            defaults.set(appLanguage.rawValue, forKey: "appLanguage")
            settingsWindow?.title = text("AngerRate · 내 기준", "AngerRate · My Settings")
            refreshStatus()
        }
    }
    @Published var scannedFiles = 0
    @Published var errorMessage: String?
    @Published var selectedProvider = "codex"
    @Published var hasCompletedSetup: Bool
    private let defaults = UserDefaults.standard
    private let scanner = SessionScanner()
    private let calibration = CalibrationService()
    private let queue = DispatchQueue(label: "app.angerrate.session-reader", qos: .utility)
    private let directory: URL
    private let store: EventStore
    private let peerCache: PeerCache
    private let deviceID: String
    private var localEvents: [ScoredEvent] = []
    private var gate: AlertGate
    private var timer: Timer?
    private var pollInFlight = false
    private var settingsWindow: NSWindow?
    private var analysisTask: Task<Void, Never>?
    private let launchTime = Date()
    private var didInitialPoll = false
    private var revision = 0

    init(preview: Bool = false) {
        let d = UserDefaults.standard
        directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("AngerRate", isDirectory: true)
        store = EventStore(directory: directory)
        peerCache = PeerCache(directory: directory.appendingPathComponent("peers"))
        let existingID = Self.machineIdentity() ?? d.string(forKey: "deviceID") ?? UUID().uuidString
        deviceID = existingID
        if !preview { d.set(existingID, forKey: "deviceID") }
        hasCompletedSetup = d.bool(forKey: "setupComplete")
        isMonitoring = d.bool(forKey: "setupComplete") && !d.bool(forKey: "paused")
        syncPath = d.string(forKey: "syncPath") ?? ""
        notificationsEnabled = d.object(forKey: "notifications") as? Bool ?? true
        temperatureUnit = TemperatureUnit(rawValue: d.string(forKey: "temperatureUnit") ?? "") ?? .celsius
        appLanguage = AppLanguage(rawValue: d.string(forKey: "appLanguage") ?? "") ?? .system
        gate = d.data(forKey: "alertGate").flatMap { try? JSONDecoder().decode(AlertGate.self, from: $0) } ?? AlertGate()
        status = AppText(appLanguage)("세션을 확인하고 있어요", "Checking sessions")
        if preview {
            hasCompletedSetup = true
            isMonitoring = true
            let now = Date()
            events = [ScoredEvent(id: "preview-1", timestamp: now.addingTimeInterval(-420), deviceID: "preview", source: "codex", points: 35, reasons: ["직접적인 욕설"], profileID: "starter-v1"), ScoredEvent(id: "preview-2", timestamp: now.addingTimeInterval(-160), deviceID: "preview", source: "claude", points: 30, reasons: ["반복된 불만 표현"], profileID: "starter-v1")]
            score = ScoreEngine.score(events: events, at: now)
            status = text("Codex · Claude Code 감지 중", "Monitoring Codex · Claude Code")
            scannedFiles = 24
            return
        }
        do {
            if let saved = try store.load() {
                // A restored backup must not impersonate another machine.
                localEvents = saved.events.filter { $0.deviceID == existingID }
                profile = Self.personalOnly(saved.profile)
                halfLifeMinutes = profile.halfLifeSeconds / 60
            }
        } catch { errorMessage = text("저장된 상태를 읽지 못했어요. \(error.localizedDescription)", "Could not read the saved state. \(error.localizedDescription)") }
        if let data = try? Data(contentsOf: directory.appendingPathComponent("draft-profile.json")) {
            draftProfile = (try? JSONDecoder().decode(PersonalProfile.self, from: data)).map(Self.personalOnly)
        }
        events = localEvents
        score = ScoreEngine.score(events: events, at: Date(), halfLife: halfLifeMinutes * 60)
        _ = gate.update(score: score, allowAlert: false)
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        poll()
        if !hasCompletedSetup || CommandLine.arguments.contains("--diagnose") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.openSettings()
                if CommandLine.arguments.contains("--diagnose") { self?.analyzeHistory() }
            }
        }
    }

    private func poll() {
        guard !pollInFlight else { return }
        pollInFlight = true
        let profileCopy = profile, enabled = isMonitoring, text = AppText(appLanguage)
        let local = localEvents, path = syncPath, device = deviceID
        let scanner = scanner, store = store, peerCache = peerCache, generation = revision
        let name = Host.current().localizedName ?? "My Mac"
        queue.async { [weak self] in
            let now = Date()
            let messages = scanner.scanNew()
            var own = local.filter { now.timeIntervalSince($0.timestamp) < 86400 }
            if enabled {
                let known = Set(own.map(\.id))
                own += messages.filter { !known.contains($0.id) && $0.timestamp <= now && now.timeIntervalSince($0.timestamp) < 60 }
                    .compactMap { ScoreEngine.evaluate(message: $0, profile: profileCopy, deviceID: device) }
            }
            var snapshot = DeviceSnapshot(deviceID: device, name: name, updatedAt: now, events: own, profile: profileCopy)
            var snapshots = [snapshot]
            var warning: String?
            var resolvedProfile = profileCopy
            let merger = FolderSync(directory: URL(fileURLWithPath: path.isEmpty ? NSTemporaryDirectory() : path))
            if !path.isEmpty {
                do {
                    snapshots = try merger.exchange(local: snapshot)
                    snapshots = [snapshot] + (try peerCache.merge(snapshots, excludingDeviceID: device))
                    if let newest = merger.latestProfile(snapshots: snapshots) { resolvedProfile = newest }
                    warning = merger.warnings.first
                } catch {
                    warning = text("동기화 대기 중: \(error.localizedDescription)", "Waiting to sync: \(error.localizedDescription)")
                    snapshots = [snapshot] + peerCache.load().filter { $0.deviceID != device }
                }
            }
            snapshot.profile = resolvedProfile
            do { try store.save(snapshot) }
            catch { warning = text("상태 저장 실패: \(error.localizedDescription)", "Could not save state: \(error.localizedDescription)") }
            let merged = merger.mergedEvents(snapshots: snapshots)
            let fileCount = scanner.scannedFileCount, scanError = scanner.lastError
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.pollInFlight = false
                guard self.revision == generation else {
                    let ids = Set(self.localEvents.map(\.id))
                    self.localEvents += own.filter { !ids.contains($0.id) }
                    self.poll(); return
                }
                let previousIDs = Set(self.events.map(\.id))
                let freshIDs = Set(merged.filter { !previousIDs.contains($0.id) && $0.timestamp >= self.launchTime }.map(\.id))
                self.localEvents = own
                self.events = merged
                self.devices = snapshots
                self.profile = Self.personalOnly(resolvedProfile)
                self.halfLifeMinutes = resolvedProfile.halfLifeSeconds / 60
                self.scannedFiles = fileCount
                self.score = ScoreEngine.score(events: merged, at: now, halfLife: self.halfLifeMinutes * 60)
                if self.gate.update(events: merged, newEventIDs: freshIDs, at: now, halfLife: self.halfLifeMinutes * 60, allowAlert: self.didInitialPoll && self.isMonitoring, notificationDeviceID: self.deviceID) { self.sendAlert() }
                self.didInitialPoll = true
                if let data = try? JSONEncoder().encode(self.gate) { self.defaults.set(data, forKey: "alertGate") }
                self.status = self.monitoringStatus(fileCount: fileCount)
                if let warning = warning ?? scanError { self.status = warning }
            }
        }
    }

    private static func personalOnly(_ original: PersonalProfile) -> PersonalProfile {
        let builtins = Set(ProfanityLexicon.rules.map { $0.phrase.lowercased() })
        var result = original
        result.rules.removeAll { builtins.contains($0.phrase.lowercased()) || $0.reason.hasPrefix("기본 기준 ·") || $0.reason.hasPrefix("Built-in criterion ·") }
        return result
    }

    private static func machineIdentity() -> String? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard let value = IORegistryEntryCreateCFProperty(service, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String else { return nil }
        return SHA256.hash(data: Data(("AngerRate-device-v1:" + value).utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    func toggleMonitoring() {
        guard hasCompletedSetup else { openSettings(); return }
        isMonitoring.toggle()
        defaults.set(!isMonitoring, forKey: "paused")
        revision += 1
        poll()
    }
    func analyzeHistory() {
        guard !isAnalyzing else { return }
        isAnalyzing = true; errorMessage = nil; draftProfile = nil
        analysisStatus = text("현재·아카이브 전체 세션 파일을 찾고 있어요…", "Finding current and archived session files…")
        let provider = selectedProvider
        let language = appLanguage.resolved
        analysisTask = Task { [weak self] in
            guard let self else { return }
            do {
                let model = self
                let auditTask = Task.detached(priority: .utility) {
                    HistoryAuditor().audit(progress: { done, total in
                        if done % 50 == 0 || done == total {
                            Task { @MainActor in model.reportAuditProgress(done: done, total: total) }
                        }
                    }, isCancelled: { Task.isCancelled })
                }
                let report = await withTaskCancellationHandler {
                    await auditTask.value
                } onCancel: { auditTask.cancel() }
                try Task.checkCancellation()
                guard report.completed else { throw AppError.message(AppText(language: language)("전체 점검이 완료되지 않았어요. 다시 진단해 주세요.", "The full review did not finish. Please try again.")) }
                let messages = report.selectedMessages
                guard !messages.isEmpty else { throw AppError.message(AppText(language: language)("분석할 사용자 메시지를 찾지 못했어요. 기본 한·영 욕설 기준으로 시작할 수 있습니다.", "No user messages were found to analyze. You can start with the built-in Korean and English profanity rules.")) }
                let scope: [String: Any] = [
                    "discoveredFiles": report.discoveredFiles, "readFiles": report.readFiles,
                    "failedFiles": report.failedFiles, "malformedLines": report.malformedLines,
                    "oversizedLines": report.oversizedLines, "userMessages": report.userMessages,
                    "archiveMessages": report.archiveMessages, "uniqueMessages": report.uniqueMessages,
                    "representativeMessages": messages.count, "completed": report.completed,
                    "scope": "All accessible local log files; remote or cloud-only history is not fetched.",
                    "checkedAt": ISO8601DateFormatter().string(from: Date())
                ]
                try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
                let scopeData = try JSONSerialization.data(withJSONObject: scope, options: [.sortedKeys])
                try scopeData.write(to: self.directory.appendingPathComponent("audit-summary.json"), options: .atomic)
                var modelContext = scope
                modelContext["frequentPhrases"] = report.phraseCounts.sorted { $0.value > $1.value }.prefix(100).map { ["phrase": $0.key, "count": $0.value] as [String: Any] }
                let context = String(decoding: try JSONSerialization.data(withJSONObject: modelContext, options: [.sortedKeys]), as: UTF8.self)
                let localized = AppText(language: language)
                self.analysisStatus = localized("\(report.readFiles)개 파일 · 메시지 \(report.userMessages)개(아카이브 \(report.archiveMessages)개)를 점검했어요. 대표 문맥과 통계로 개인 신호를 분석 중이에요.", "Reviewed \(report.readFiles) files and \(report.userMessages) messages (\(report.archiveMessages) archived). Analyzing representative context and statistics for personal signals.")
                let draft = try await self.calibration.analyze(messages: messages, provider: provider, corpusContext: context, language: language)
                try Task.checkCancellation()
                self.draftProfile = draft
                try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
                try JSONEncoder().encode(draft).write(to: self.directory.appendingPathComponent("draft-profile.json"), options: .atomic)
                self.analysisStatus = localized("전체 \(report.readFiles)/\(report.discoveredFiles)파일 · 메시지 \(report.userMessages)개(아카이브 \(report.archiveMessages)개)를 점검했어요. 개인 신호 \(draft.rules.count)개 · 읽기 실패 \(report.failedFiles)파일.", "Reviewed \(report.readFiles)/\(report.discoveredFiles) files and \(report.userMessages) messages (\(report.archiveMessages) archived). Found \(draft.rules.count) personal signals; \(report.failedFiles) files could not be read.")
            } catch is CancellationError { self.analysisStatus = AppText(language: language)("분석을 취소했어요.", "Analysis cancelled.") }
            catch {
                self.errorMessage = (error as? CalibrationError)?.description(language: language) ?? error.localizedDescription
                self.analysisStatus = AppText(language: language)("분석하지 못했어요. 로그인 상태를 확인하거나 다른 도구로 다시 시도해 주세요.", "Analysis failed. Check that you are signed in, or try the other tool.")
            }
            self.isAnalyzing = false
        }
    }
    private func reportAuditProgress(done: Int, total: Int) {
        analysisStatus = text("전체 세션 점검 중 · \(done)/\(total) 파일", "Reviewing all sessions · \(done)/\(total) files")
        let data: [String: Any] = ["readFiles": done, "totalFiles": total, "updatedAt": Date().timeIntervalSince1970]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let json = try? JSONSerialization.data(withJSONObject: data) {
            try? json.write(to: directory.appendingPathComponent("audit-progress.json"), options: .atomic)
        }
    }
    func cancelAnalysis() { analysisTask?.cancel(); calibration.cancel() }
    func applyDraft() {
        guard var draft = draftProfile else { return }
        draft.halfLifeSeconds = halfLifeMinutes * 60
        profile = draft
        saveProfile()
        guard errorMessage == nil else { return }
        draftProfile = nil
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("draft-profile.json"))
        if !hasCompletedSetup { completeSetup() }
    }
    func dismissDraft() {
        draftProfile = nil
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("draft-profile.json"))
    }
    func setHalfLifeMinutes(_ value: Double) {
        halfLifeMinutes = min(15, max(2, value))
        saveProfile()
    }
    func saveProfile() {
        guard profile.rules.count <= 80,
              profile.rules.allSatisfy({ !$0.phrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.phrase.count <= 80 && $0.weight.isFinite && (5...50).contains($0.weight) }),
              Set(profile.rules.map { $0.phrase.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }).count == profile.rules.count else {
            errorMessage = text("개인 표현은 중복 없이 0–80개, 점수는 5–50으로 입력해 주세요.", "Enter 0–80 unique personal phrases with scores from 5–50."); return
        }
        errorMessage = nil
        profile.id = UUID().uuidString
        profile.updatedAt = Date()
        profile.halfLifeSeconds = min(900, max(120, halfLifeMinutes * 60))
        revision += 1
        persistProfile()
    }
    private func persistProfile() {
        let snapshot = DeviceSnapshot(deviceID: deviceID, name: Host.current().localizedName ?? "My Mac", updatedAt: Date(), events: localEvents, profile: profile)
        queue.async { [weak self, store] in
            do { try store.save(snapshot) }
            catch { Task { @MainActor in self?.errorMessage = self?.text("기준을 저장하지 못했어요: \(error.localizedDescription)", "Could not save the rules: \(error.localizedDescription)") } }
        }
        poll()
    }
    func chooseSyncFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.message = text("연결할 Mac에서 같은 iCloud Drive 또는 동기화 폴더를 선택해 주세요. 대화 원문은 공유하지 않아요.", "Choose the same iCloud Drive or sync folder on each Mac you want to connect. Original messages are never shared.")
        if panel.runModal() == .OK, let url = panel.url {
            syncPath = url.appendingPathComponent("AngerRate-Sync", isDirectory: true).path
            defaults.set(syncPath, forKey: "syncPath")
            revision += 1; poll()
        }
    }
    func disconnectSync() {
        // Retract this device's contribution when reachable; other Macs must also disconnect to fully unlink.
        let path = syncPath
        if !path.isEmpty {
            queue.async { [peerCache] in try? peerCache.clear() }
            let file = URL(fileURLWithPath: path).appendingPathComponent("\(deviceID).json")
            queue.async { try? FileManager.default.removeItem(at: file) }
        }
        syncPath = ""; defaults.removeObject(forKey: "syncPath")
        events = localEvents; devices = []; revision += 1; poll()
    }
    func requestNotifications() {
        guard Bundle.main.bundleIdentifier != nil else { errorMessage = text("알림은 패키징된 AngerRate.app에서 사용할 수 있어요.", "Notifications are available in the packaged AngerRate.app."); return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
            Task { @MainActor in
                self?.notificationsEnabled = granted
                if !granted { self?.errorMessage = self?.text("시스템 설정 → 알림 → AngerRate에서 알림을 허용해 주세요.", "Allow notifications for AngerRate in System Settings → Notifications.") }
                if let error { self?.errorMessage = error.localizedDescription }
            }
        }
    }
    private func sendAlert() {
        guard notificationsEnabled, Bundle.main.bundleIdentifier != nil else { return }
        let text = AppText(appLanguage)
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            let content = UNMutableNotificationContent()
            content.title = text("분노 신호가 높아졌어요", "Anger signals are high")
            content.body = text("잠깐 쉬어갈까요?", "Time for a breather?")
            content.sound = .default
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }
    func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 760), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = text("AngerRate · 내 기준", "AngerRate · My Settings")
            window.contentView = NSHostingView(rootView: PreferencesView(model: self))
            window.minSize = NSSize(width: 560, height: 580)
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func completeSetup() {
        hasCompletedSetup = true; isMonitoring = true
        defaults.set(true, forKey: "setupComplete"); defaults.set(false, forKey: "paused")
        revision += 1
        requestNotifications(); poll()
    }
    func resetToStarter() { profile = .starter; saveProfile() }
    func openDataFolder() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directory)
    }

    var localizedText: AppText { AppText(appLanguage) }

    func text(_ korean: String, _ english: String) -> String {
        localizedText(korean, english)
    }

    private func refreshStatus() {
        status = monitoringStatus(fileCount: scannedFiles)
    }

    private func monitoringStatus(fileCount: Int) -> String {
        if !hasCompletedSetup { return text("개인 기준을 설정해 주세요", "Set up your personal rules") }
        if !isMonitoring { return text("감지를 잠시 멈췄어요", "Monitoring is paused") }
        if fileCount == 0 { return text("Codex·Claude 세션을 기다리고 있어요", "Waiting for Codex · Claude sessions") }
        return text("\(fileCount)개 세션 감지 중", "Monitoring \(fileCount) session files")
    }
}
private enum AppError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(value) = self { return value }; return nil }
}
