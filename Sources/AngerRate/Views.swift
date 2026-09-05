import AppKit
import Charts
import SwiftUI
import AngerCore

struct MainPanel: View {
    @ObservedObject var model: AppModel

    private var text: AppText { model.localizedText }
    private var level: AngerLevel { AngerLevel(score: model.score) }
    private var recentEvents: [ScoredEvent] {
        model.events.filter { $0.timestamp >= Date().addingTimeInterval(-30 * 60) }.sorted { $0.timestamp > $1.timestamp }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                scoreHeader
                historyChart
                explanation
                if !model.hasCompletedSetup { setupPrompt }
                footer
            }
            .padding(20)
        }
        .frame(width: 360, height: 500)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.locale, text.language.locale)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(text("분노 신호 패널", "Anger signal panel"))
    }

    private var scoreHeader: some View {
        VStack(spacing: 6) {
            FlameView(score: model.score, isAnimating: model.isMonitoring)
                .frame(width: 64, height: 80)
                .accessibilityLabel(text("현재 분노 점수 \(Int(model.score.rounded()))점", "Current anger score: \(Int(model.score.rounded())) out of 100"))
            Text(level.label(text)).font(.headline)
            Text(level.guidance(text))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private var historyChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text("최근 30분", "Last 30 minutes")).font(.subheadline.weight(.semibold))
            Chart(chartPoints) { point in
                AreaMark(
                    x: .value(text("시간", "Time"), point.date),
                    yStart: .value(text("기준", "Baseline"), 0),
                    yEnd: .value(text("분노 점수", "Anger score"), point.score)
                )
                .foregroundStyle(.primary.opacity(0.08))
                LineMark(
                    x: .value(text("시간", "Time"), point.date),
                    y: .value(text("분노 점수", "Anger score"), point.score)
                )
                .foregroundStyle(.primary)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
            .chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(values: [0, 50, 100]) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let score = value.as(Int.self) { Text("\(score)") }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .minute, count: 10)) {
                    AxisValueLabel(format: .dateTime.hour().minute().locale(text.language.locale))
                    AxisGridLine()
                }
            }
            .frame(height: 110)
            .accessibilityLabel(text("최근 30분 분노 점수 그래프", "Anger score chart for the last 30 minutes"))
            .accessibilityValue(text("현재 \(Int(model.score.rounded()))점", "Current score: \(Int(model.score.rounded())) out of 100"))
        }
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text("최근에 올라간 이유", "Why it rose recently")).font(.subheadline.weight(.semibold))
            if recentEvents.isEmpty {
                Text(text("최근 30분 동안 감지된 신호가 없어요.", "No signals were detected in the last 30 minutes."))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(recentEvents.prefix(3)) { event in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "arrow.up.right").foregroundStyle(.secondary).accessibilityHidden(true)
                        Text(event.reasons.map(text.reason).joined(separator: ", ")).lineLimit(1)
                        Spacer(minLength: 4)
                        Text("+\(Int(event.points.rounded()))").monospacedDigit().foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private var setupPrompt: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(text("내 표현에 맞춰 볼까요?", "Make it personal?"), systemImage: "sparkles").font(.headline)
            Text(text("이 Mac의 현재·아카이브 세션을 한 번 점검해 개인 기준을 제안합니다.", "Review current and archived sessions on this Mac once to suggest personal rules."))
                .font(.callout).foregroundStyle(.secondary)
            Button(text("첫 진단 시작", "Start Initial Review")) { model.openSettings() }.buttonStyle(.borderedProminent)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var footer: some View {
        VStack(spacing: 10) {
            HStack {
                Label(model.status, systemImage: model.isMonitoring ? "waveform" : "pause.circle")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Button(model.isMonitoring ? text("일시 정지", "Pause") : text("감지 시작", "Resume")) { model.toggleMonitoring() }
                    .accessibilityHint(model.isMonitoring
                        ? text("새 메시지 감지를 잠시 멈춥니다", "Pauses detection of new messages")
                        : text("Codex와 Claude Code 메시지 감지를 시작합니다", "Starts detecting Codex and Claude Code messages"))
            }
            Divider()
            HStack {
                Button(text("설정…", "Settings…")) { model.openSettings() }
                Spacer()
                Button(text("종료", "Quit")) { model.cancelAnalysis(); NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
            }
            .controlSize(.small)
        }
    }

    private var chartPoints: [ScorePoint] {
        let now = Date()
        return stride(from: 30, through: 0, by: -2).map { minutesAgo in
            let date = now.addingTimeInterval(TimeInterval(-minutesAgo * 60))
            return ScorePoint(
                date: date,
                score: ScoreEngine.score(events: model.events.filter { $0.timestamp <= date }, at: date, halfLife: model.halfLifeMinutes * 60)
            )
        }
    }
}

struct PreferencesView: View {
    @ObservedObject var model: AppModel
    @State private var showsBaselineRules = false
    private var text: AppText { model.localizedText }

    var body: some View {
        TabView {
            diagnosisTab.tabItem { Label(text("첫 진단", "Initial Review"), systemImage: "sparkles") }
            rulesTab.tabItem { Label(text("개인 기준", "Personal Rules"), systemImage: "list.bullet.rectangle") }
            behaviorTab.tabItem { Label(text("동작", "Behavior"), systemImage: "slider.horizontal.3") }
            devicesTab.tabItem { Label(text("기기", "Devices"), systemImage: "laptopcomputer.and.iphone") }
        }
        .padding(16)
        .frame(minWidth: 560, idealWidth: 620, minHeight: 500, idealHeight: 580)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.locale, text.language.locale)
    }

    private var diagnosisTab: some View {
        Form {
            Section(text("분석 도구", "Analysis Tool")) {
                Picker(text("사용할 도구", "Tool"), selection: $model.selectedProvider) {
                    Text("Codex").tag("codex")
                    Text("Claude Code").tag("claude")
                }
                .pickerStyle(.segmented)
                Text(text(
                    "이미 로그인된 도구를 사용하며 기존 계정 사용량이 차감될 수 있습니다. 분석할 때 세션에서 추출한 내 메시지가 선택한 도구로 전달되고, 원문은 AngerRate에 저장하거나 기기 간 동기화하지 않습니다.",
                    "AngerRate uses the tool you are already signed into, which may count against your account usage. Extracted messages are sent to the selected tool only for analysis. AngerRate never stores or syncs the original text."
                )).font(.callout).foregroundStyle(.secondary)
            }

            Section(text("이 Mac의 전체 세션 1회 진단", "One-Time Review of All Sessions on This Mac")) {
                Text(text(
                    "현재 세션과 로컬 아카이브 중 이 Mac에서 접근 가능한 기록을 모두 점검합니다. 대표 문맥과 사용 통계를 CLI로 분석해 기본 욕설 외에 나에게서 분노 신호로 보일 수 있는 표현을 제안합니다.",
                    "Reviews every accessible current and locally archived session on this Mac. Representative context and usage statistics are analyzed through the CLI to suggest personal anger signals beyond built-in profanity."
                )).font(.callout).foregroundStyle(.secondary)
                Text(text("다른 Mac이나 클라우드에만 있는 기록은 자동으로 내려받지 않습니다.", "Sessions available only on another Mac or in the cloud are not downloaded automatically."))
                    .font(.caption).foregroundStyle(.secondary)

                if model.isAnalyzing {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text(model.analysisStatus)
                        Spacer()
                        Button(text("취소", "Cancel")) { model.cancelAnalysis() }
                    }.accessibilityElement(children: .combine)
                } else {
                    LabeledContent(text("상태", "Status"), value: model.analysisStatus)
                    if model.scannedFiles > 0 {
                        LabeledContent(text("확인한 세션 파일", "Session Files Checked"), value: text("\(model.scannedFiles)개", "\(model.scannedFiles)"))
                    }
                    Button(model.hasCompletedSetup ? text("전체 세션 다시 진단", "Review All Sessions Again") : text("전체 세션 진단", "Review All Sessions")) { model.analyzeHistory() }
                        .buttonStyle(.borderedProminent)
                }

                if let error = model.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red).textSelection(.enabled)
                        .accessibilityLabel(text("오류: \(error)", "Error: \(error)"))
                }
            }

            if model.draftProfile != nil {
                Section(text("제안된 개인 신호", "Suggested Personal Signals")) {
                    Text(model.draftProfile?.summary ?? "").foregroundStyle(.secondary)
                    if model.draftProfile?.rules.isEmpty == true {
                        Text(text("추가할 개인 신호가 없어요. 한·영 기본 욕설 기준은 그대로 적용됩니다.", "No additional personal signals were found. The built-in Korean and English profanity rules remain active."))
                    } else {
                        let count = model.draftProfile?.rules.count ?? 0
                        Text(text("기본 욕설 외에 개인 신호 \(count)개를 찾았습니다. 적용하기 전에 개인 기준 탭에서 수정할 수 있어요.", "Found \(count) personal signals beyond built-in profanity. You can edit them in Personal Rules before applying."))
                    }
                    HStack {
                        Button(text("제안 버리기", "Discard Suggestions"), role: .destructive) { model.dismissDraft() }
                        Spacer()
                        Button(text("제안 적용", "Apply Suggestions")) { model.applyDraft() }.buttonStyle(.borderedProminent)
                    }
                }
            }

            Section {
                Button(text("기본 기준으로 시작", "Start with Built-In Rules")) { model.completeSetup() }.disabled(model.isAnalyzing)
            }
        }
        .formStyle(.grouped)
    }

    private var rulesTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(text("감지 기준", "Detection Rules")).font(.title2.weight(.semibold))
            Text(text(
                "흔한 욕설은 모든 사용자에게 적용되고, 첫 진단과 직접 편집으로 찾은 다른 신호만 개인 기준에 추가됩니다.",
                "Common profanity applies to everyone. Only other signals found in the initial review or added by you become personal rules."
            )).font(.callout).foregroundStyle(.secondary)

            DisclosureGroup(isExpanded: $showsBaselineRules) {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(ProfanityLexicon.rules) { rule in
                            BaselineRuleRow(rule: rule, text: text)
                            if rule.id != ProfanityLexicon.rules.last?.id { Divider() }
                        }
                    }
                }.frame(maxHeight: 180).padding(.top, 6)
            } label: {
                Label(text("한·영 기본 욕설 \(ProfanityLexicon.rules.count)개 · 항상 적용", "\(ProfanityLexicon.rules.count) built-in Korean and English profanity rules · always active"), systemImage: "checkmark.shield.fill")
                    .font(.headline)
            }
            .padding(12)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityHint(text("기본 욕설 목록을 펼치거나 접습니다", "Expands or collapses the built-in profanity list"))

            Text(text("개인 신호", "Personal Signals")).font(.headline)
            if model.draftProfile != nil {
                Label(text("적용을 기다리는 변경이 있어요.", "Changes are waiting to be applied."), systemImage: "circle.dashed")
                    .font(.callout).foregroundStyle(.secondary)
            }
            errorNotice

            List {
                if editableRules.wrappedValue.isEmpty {
                    Text(text("추가된 개인 신호가 없어요. 기본 욕설 기준은 계속 적용됩니다.", "No personal signals have been added. Built-in profanity rules remain active."))
                        .foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 24)
                } else {
                    ForEach(editableRules) { $rule in
                        RuleEditorRow(rule: $rule, text: text) { removeRule(id: rule.id) }
                    }
                }
            }.clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            HStack {
                Button(action: addRule) { Label(text("표현 추가", "Add Phrase"), systemImage: "plus") }
                Spacer()
                Button(text("기본 기준으로 복원", "Restore Defaults"), role: .destructive) { model.dismissDraft(); model.resetToStarter() }
                Button(text("기준 적용", "Apply Rules")) {
                    if model.draftProfile != nil { model.applyDraft() } else { model.saveProfile() }
                }.buttonStyle(.borderedProminent)
            }
        }
        .padding(4)
    }

    private var behaviorTab: some View {
        Form {
            errorNotice
            Section(text("언어", "Language")) {
                Picker(text("앱 언어", "App Language"), selection: $model.appLanguage) {
                    ForEach(AppLanguage.allCases, id: \.self) { language in
                        Text(text.preferenceName(language)).tag(language)
                    }
                }
                .pickerStyle(.segmented)
                Text(text("시스템 설정은 macOS의 선호 언어가 한국어면 한국어를, 그 외에는 영어를 사용합니다.", "System Setting uses Korean when it is your preferred macOS language, and English otherwise."))
                    .font(.callout).foregroundStyle(.secondary)
            }

            Section(text("시간에 따른 감소", "Cooling Over Time")) {
                Slider(value: halfLifeBinding, in: 2...15, step: 1) { Text(text("반감기", "Half-life")) } minimumValueLabel: {
                    Text(text("2분", "2 min"))
                } maximumValueLabel: {
                    Text(text("15분", "15 min"))
                }
                Text(text("새 신호가 없으면 약 \(Int(model.halfLifeMinutes))분마다 분노 점수가 절반으로 줄고 불꽃이 잦아듭니다.", "With no new signals, the anger score halves about every \(Int(model.halfLifeMinutes)) minutes and the flame settles down."))
                    .font(.callout).foregroundStyle(.secondary)
            }

            Section(text("높은 분노 신호 알림", "High Anger Signal Alert")) {
                Toggle(text("알림 사용", "Enable Notifications"), isOn: $model.notificationsEnabled)
                Button(text("알림 권한 확인", "Check Notification Permission")) { model.requestNotifications() }
                Text(text("분노 점수가 처음 100에 도달할 때 한 번 알립니다. 충분히 잦아든 뒤 다시 100에 닿으면 다시 알려요.", "You are notified once when the anger score first reaches 100. The alert can fire again after the score settles sufficiently and returns to 100."))
                    .font(.callout).foregroundStyle(.secondary)
            }

            Section(text("데이터", "Data")) {
                Button(text("데이터 폴더 열기", "Open Data Folder")) { model.openDataFolder() }
                Text(text("점수 이벤트와 개인 기준만 저장하며, 메시지 원문은 저장하지 않습니다.", "Only score events and personal rules are stored. Original messages are not saved."))
                    .font(.callout).foregroundStyle(.secondary)
                Text(text("분노 점수는 언어 신호를 알아차리기 위한 추정치이며 감정·건강 상태의 진단이 아닙니다.", "The anger score is an estimate for noticing language signals, not a diagnosis of your emotions or health."))
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var devicesTab: some View {
        Form {
            Section(text("선택적 기기 연결", "Optional Device Sync")) {
                if model.syncPath.isEmpty {
                    Text(text("이 Mac만으로도 모든 기능을 사용할 수 있습니다. iCloud Drive 같은 동기화 폴더를 고르면 여러 Mac의 점수 이벤트를 합칩니다.", "Everything works on this Mac alone. Choose a sync folder such as iCloud Drive to combine score events from multiple Macs."))
                        .foregroundStyle(.secondary)
                    Button(text("동기화 폴더 선택…", "Choose Sync Folder…")) { model.chooseSyncFolder() }.buttonStyle(.borderedProminent)
                } else {
                    LabeledContent(text("동기화 폴더", "Sync Folder")) {
                        Text(model.syncPath).lineLimit(2).truncationMode(.middle).textSelection(.enabled)
                    }
                    Button(text("기기 연결 해제", "Disconnect Devices"), role: .destructive) { model.disconnectSync() }
                }
            }

            if !model.devices.isEmpty {
                Section(text("연결된 기기", "Connected Devices")) {
                    ForEach(model.devices, id: \.deviceID) { device in
                        HStack {
                            Image(systemName: "laptopcomputer").accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(device.name)
                                Text(device.updatedAt, style: .relative).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(text("마지막 확인", "Last seen")).font(.caption).foregroundStyle(.secondary)
                        }.accessibilityElement(children: .combine)
                    }
                }
            }

            Section {
                Text(text("기기 간 반영 속도는 선택한 폴더 제공자에 따라 달라질 수 있습니다.", "Sync speed depends on the selected folder provider."))
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var editableRules: Binding<[LanguageRule]> {
        Binding(
            get: { model.draftProfile?.rules ?? model.profile.rules },
            set: { newRules in
                var profile = model.draftProfile ?? model.profile
                profile.rules = newRules
                profile.updatedAt = Date()
                model.draftProfile = profile
            }
        )
    }

    private var halfLifeBinding: Binding<Double> {
        Binding(get: { model.halfLifeMinutes }, set: { model.setHalfLifeMinutes($0) })
    }

    @ViewBuilder private var errorNotice: some View {
        if let error = model.errorMessage {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red).textSelection(.enabled)
                .accessibilityLabel(text("오류: \(error)", "Error: \(error)"))
        }
    }

    private func addRule() {
        var rules = editableRules.wrappedValue
        rules.append(LanguageRule(phrase: "", weight: 10, reason: text("사용자 지정 신호", "Custom signal")))
        editableRules.wrappedValue = rules
    }

    private func removeRule(id: String) { editableRules.wrappedValue.removeAll { $0.id == id } }
}

private struct RuleEditorRow: View {
    @Binding var rule: LanguageRule
    let text: AppText
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle(text("감지", "Detect"), isOn: $rule.enabled).labelsHidden()
                    .accessibilityLabel(text("\(rule.phrase.isEmpty ? "새 표현" : rule.phrase) 감지", "Detect \(rule.phrase.isEmpty ? "new phrase" : rule.phrase)"))
                TextField(text("표현", "Phrase"), text: $rule.phrase).textFieldStyle(.roundedBorder)
                    .accessibilityLabel(text("감지할 표현", "Phrase to detect"))
                Button(role: .destructive, action: remove) { Image(systemName: "trash") }.buttonStyle(.borderless)
                    .accessibilityLabel(text("\(rule.phrase.isEmpty ? "새 표현" : rule.phrase) 삭제", "Delete \(rule.phrase.isEmpty ? "new phrase" : rule.phrase)"))
            }
            HStack(spacing: 12) {
                TextField(text("판단 이유", "Reason"), text: $rule.reason).textFieldStyle(.roundedBorder)
                    .accessibilityLabel(text("판단 이유", "Detection reason"))
                Slider(value: $rule.weight, in: 5...50, step: 1).frame(width: 130)
                    .accessibilityLabel(text("분노 점수 상승", "Anger score increase")).accessibilityValue("+\(Int(rule.weight.rounded()))")
                Text("+\(Int(rule.weight.rounded()))").font(.callout.monospacedDigit()).foregroundStyle(.secondary).frame(width: 42, alignment: .trailing)
                Text(severityLabel).font(.caption.weight(.medium)).foregroundStyle(.secondary).frame(width: text.language == .korean ? 34 : 52)
            }
        }
        .padding(.vertical, 5)
    }

    private var severityLabel: String {
        if rule.weight < 15 { return text("약함", "Low") }
        if rule.weight < 30 { return text("중간", "Medium") }
        return text("강함", "High")
    }
}

private struct BaselineRuleRow: View {
    let rule: LanguageRule
    let text: AppText

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(rule.phrase).font(.callout.weight(.medium)).frame(width: 110, alignment: .leading)
            Text(text.reason(rule.reason)).font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text("+\(Int(rule.weight.rounded()))").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(rule.phrase), \(text.reason(rule.reason)), +\(Int(rule.weight.rounded()))")
    }
}

private struct ScorePoint: Identifiable {
    let date: Date
    let score: Double
    var id: Date { date }
}

private enum AngerLevel {
    case calm, growing, blazing, alert

    init(score: Double) {
        switch score {
        case 100...: self = .alert
        case 66..<100: self = .blazing
        case 33..<66: self = .growing
        default: self = .calm
        }
    }

    func label(_ text: AppText) -> String {
        switch self {
        case .calm: return text("잔잔한 촛불", "Quiet candle")
        case .growing: return text("불이 피어나고 있어요", "The flame is growing")
        case .blazing: return text("불이 빠르게 타오르고 있어요", "The flame is blazing")
        case .alert: return text("잠깐 쉬어갈 때예요", "Time for a breather?")
        }
    }

    func guidance(_ text: AppText) -> String {
        switch self {
        case .calm: return text("열이 오르는 순간을 알아차리고, 잠시 숨을 고르세요.", "Notice the heat. Take a moment.")
        case .growing: return text("내 말이 조금 거칠어지고 있음을 알아차려 보세요.", "Notice that your words may be getting a little sharper.")
        case .blazing: return text("답을 보내기 전 잠시 멈춰도 괜찮아요.", "It is okay to pause before sending the next reply.")
        case .alert: return text("지금 많이 화난 상태일 수 있어요. 잠깐 식혀 보세요.", "You may be very angry right now. Give yourself a moment to cool down.")
        }
    }
}
