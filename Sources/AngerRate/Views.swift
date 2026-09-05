import AppKit
import Charts
import SwiftUI
import AngerCore

struct MainPanel: View {
    @ObservedObject var model: AppModel

    private var displayedTemperature: String {
        TemperatureDisplay.formatted(score: model.score, unit: model.temperatureUnit)
    }
    private var level: AngerLevel { AngerLevel(score: model.score) }
    private var recentEvents: [ScoredEvent] {
        model.events
            .filter { $0.timestamp >= Date().addingTimeInterval(-30 * 60) }
            .sorted { $0.timestamp > $1.timestamp }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                scoreHeader
                historyChart
                explanation

                if !model.hasCompletedSetup {
                    setupPrompt
                }

                footer
            }
            .padding(20)
        }
        .frame(width: 360, height: 500)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("대화 온도 패널")
    }

    private var scoreHeader: some View {
        VStack(spacing: 5) {
            Text(displayedTemperature)
                .font(.system(size: 58, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(level.color)
                .accessibilityLabel("현재 대화 온도 \(displayedTemperature)")

            Text(level.label)
                .font(.headline)

            Text(level.guidance)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var historyChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("최근 30분")
                .font(.subheadline.weight(.semibold))

            Chart(chartPoints) { point in
                AreaMark(
                    x: .value("시간", point.date),
                    yStart: .value("기준 온도", TemperatureDisplay.range(unit: model.temperatureUnit).lowerBound),
                    yEnd: .value("대화 온도", point.temperature)
                )
                .foregroundStyle(level.color.opacity(0.12))

                LineMark(
                    x: .value("시간", point.date),
                    y: .value("대화 온도", point.temperature)
                )
                .foregroundStyle(level.color)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
            .chartYScale(domain: TemperatureDisplay.range(unit: model.temperatureUnit))
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine()
                    if let temperature = value.as(Double.self) {
                        AxisValueLabel {
                            Text("\(temperature, specifier: "%.0f")\(model.temperatureUnit.symbol)")
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .minute, count: 10)) {
                    AxisValueLabel(format: .dateTime.hour().minute())
                    AxisGridLine()
                }
            }
            .frame(height: 110)
            .accessibilityLabel("최근 30분 대화 온도 그래프")
            .accessibilityValue("현재 \(displayedTemperature), 끓는점 \(TemperatureDisplay.formatted(score: 100, unit: model.temperatureUnit))")
        }
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var explanation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("최근에 올라간 이유")
                .font(.subheadline.weight(.semibold))

            if recentEvents.isEmpty {
                Text("최근 30분 동안 감지된 신호가 없어요.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(recentEvents.prefix(3)) { event in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "arrow.up.right")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text(event.reasons.joined(separator: ", "))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(TemperatureDisplay.formattedRise(points: event.points, unit: model.temperatureUnit))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
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
            Label("내 표현에 맞춰 볼까요?", systemImage: "sparkles")
                .font(.headline)
            Text("이 Mac의 현재·아카이브 세션을 한 번 점검해 개인 기준을 제안합니다.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("첫 진단 시작") {
                model.openSettings()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var footer: some View {
        VStack(spacing: 10) {
            HStack {
                Label(model.status, systemImage: model.isMonitoring ? "waveform" : "pause.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button(model.isMonitoring ? "일시 정지" : "감지 시작") {
                    model.toggleMonitoring()
                }
                .accessibilityHint(model.isMonitoring ? "새 메시지 감지를 잠시 멈춥니다" : "Codex와 Claude Code 메시지 감지를 시작합니다")
            }

            Divider()

            HStack {
                Button("설정…") { model.openSettings() }
                Spacer()
                Button("종료") { model.cancelAnalysis(); NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            }
            .controlSize(.small)
        }
    }

    private var chartPoints: [ScorePoint] {
        let now = Date()
        return stride(from: 30, through: 0, by: -2).map { minutesAgo in
            let date = now.addingTimeInterval(TimeInterval(-minutesAgo * 60))
            let visibleEvents = model.events.filter { $0.timestamp <= date }
            return ScorePoint(
                date: date,
                temperature: TemperatureDisplay.value(
                    score: ScoreEngine.score(
                        events: visibleEvents,
                        at: date,
                        halfLife: model.halfLifeMinutes * 60
                    ),
                    unit: model.temperatureUnit
                )
            )
        }
    }
}

struct PreferencesView: View {
    @ObservedObject var model: AppModel
    @State private var showsBaselineRules = false

    var body: some View {
        TabView {
            diagnosisTab
                .tabItem { Label("첫 진단", systemImage: "sparkles") }
            rulesTab
                .tabItem { Label("개인 기준", systemImage: "list.bullet.rectangle") }
            behaviorTab
                .tabItem { Label("동작", systemImage: "slider.horizontal.3") }
            devicesTab
                .tabItem { Label("기기", systemImage: "laptopcomputer.and.iphone") }
        }
        .padding(16)
        .frame(minWidth: 560, idealWidth: 620, minHeight: 500, idealHeight: 580)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var diagnosisTab: some View {
        Form {
            Section("분석 도구") {
                Picker("사용할 도구", selection: $model.selectedProvider) {
                    Text("Codex").tag("codex")
                    Text("Claude Code").tag("claude")
                }
                .pickerStyle(.segmented)

                Text("이미 로그인된 도구를 사용하며 기존 계정 사용량이 차감될 수 있습니다. 분석할 때 세션에서 추출한 내 메시지가 선택한 도구로 전달되고, 원문은 AngerRate에 저장하거나 기기 간 동기화하지 않습니다.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("이 Mac의 전체 세션 1회 진단") {
                Text("현재 세션과 로컬 아카이브 중 이 Mac에서 접근 가능한 기록을 모두 점검합니다. 대표 문맥과 사용 통계를 CLI로 분석해 기본 욕설 외에 나에게서 분노 신호로 보일 수 있는 표현을 제안합니다.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("다른 Mac이나 클라우드에만 있는 기록은 자동으로 내려받지 않습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if model.isAnalyzing {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        Text(model.analysisStatus)
                        Spacer()
                        Button("취소") { model.cancelAnalysis() }
                    }
                    .accessibilityElement(children: .combine)
                } else {
                    LabeledContent("상태", value: model.analysisStatus)
                    if model.scannedFiles > 0 {
                        LabeledContent("확인한 세션 파일", value: "\(model.scannedFiles)개")
                    }
                    Button(model.hasCompletedSetup ? "전체 세션 다시 진단" : "전체 세션 진단") {
                        model.analyzeHistory()
                    }
                    .buttonStyle(.borderedProminent)
                }

                if let error = model.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                        .accessibilityLabel("오류: \(error)")
                }
            }

            if model.draftProfile != nil {
                Section("제안된 개인 신호") {
                    Text(model.draftProfile?.summary ?? "")
                        .foregroundStyle(.secondary)
                    if model.draftProfile?.rules.isEmpty == true {
                        Text("추가할 개인 신호가 없어요. 한·영 기본 욕설 기준은 그대로 적용됩니다.")
                    } else {
                        Text("기본 욕설 외에 개인 신호 \(model.draftProfile?.rules.count ?? 0)개를 찾았습니다. 적용하기 전에 개인 기준 탭에서 수정할 수 있어요.")
                    }
                    HStack {
                        Button("제안 버리기", role: .destructive) { model.dismissDraft() }
                        Spacer()
                        Button("제안 적용") { model.applyDraft() }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }

            Section {
                Button("기본 기준으로 시작") { model.completeSetup() }
                    .disabled(model.isAnalyzing)
            }
        }
        .formStyle(.grouped)
    }

    private var rulesTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("감지 기준")
                .font(.title2.weight(.semibold))
            Text("흔한 욕설은 모든 사용자에게 적용되고, 첫 진단과 직접 편집으로 찾은 다른 신호만 개인 기준에 추가됩니다.")
                .font(.callout)
                .foregroundStyle(.secondary)

            DisclosureGroup(isExpanded: $showsBaselineRules) {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(ProfanityLexicon.rules) { rule in
                            BaselineRuleRow(rule: rule, unit: model.temperatureUnit)
                            if rule.id != ProfanityLexicon.rules.last?.id {
                                Divider()
                            }
                        }
                    }
                }
                .frame(maxHeight: 180)
                .padding(.top, 6)
            } label: {
                Label("한·영 기본 욕설 \(ProfanityLexicon.rules.count)개 · 항상 적용", systemImage: "checkmark.shield.fill")
                    .font(.headline)
            }
            .padding(12)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityHint("기본 욕설 목록을 펼치거나 접습니다")

            Text("개인 신호")
                .font(.headline)

            if model.draftProfile != nil {
                Label("적용을 기다리는 변경이 있어요.", systemImage: "circle.dashed")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            errorNotice

            List {
                if editableRules.wrappedValue.isEmpty {
                    Text("추가된 개인 신호가 없어요. 기본 욕설 기준은 계속 적용됩니다.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 24)
                } else {
                    ForEach(editableRules) { $rule in
                        RuleEditorRow(rule: $rule, unit: model.temperatureUnit) {
                            removeRule(id: rule.id)
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            HStack {
                Button {
                    addRule()
                } label: {
                    Label("표현 추가", systemImage: "plus")
                }
                Spacer()
                Button("기본 기준으로 복원", role: .destructive) {
                    model.dismissDraft()
                    model.resetToStarter()
                }
                Button("기준 적용") {
                    if model.draftProfile != nil {
                        model.applyDraft()
                    } else {
                        model.saveProfile()
                    }
                }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(4)
    }

    private var behaviorTab: some View {
        Form {
            errorNotice

            Section("시간에 따른 감소") {
                Slider(value: halfLifeBinding, in: 2...15, step: 1) {
                    Text("반감기")
                } minimumValueLabel: {
                    Text("2분")
                } maximumValueLabel: {
                    Text("15분")
                }
                Text("아무 신호가 없으면 약 \(Int(model.halfLifeMinutes))분마다 기준 온도(\(TemperatureDisplay.formatted(score: 0, unit: model.temperatureUnit)))를 넘는 부분이 절반으로 줄어듭니다.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("온도 표시") {
                Picker("단위", selection: $model.temperatureUnit) {
                    ForEach(TemperatureUnit.allCases, id: \.self) { unit in
                        Text("\(unit.label) (\(unit.symbol))").tag(unit)
                    }
                }
                .pickerStyle(.segmented)
                Text("내부 분노 rate 0–100을 \(TemperatureDisplay.formatted(score: 0, unit: model.temperatureUnit))–\(TemperatureDisplay.formatted(score: 100, unit: model.temperatureUnit))의 대화 온도로 표시합니다.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("끓는점 도달 알림") {
                Toggle("알림 사용", isOn: $model.notificationsEnabled)
                Button("알림 권한 확인") { model.requestNotifications() }
                Text("대화 온도가 \(TemperatureDisplay.formatted(score: 100, unit: model.temperatureUnit))에 처음 도달할 때 한 번 알립니다. 충분히 식은 뒤 다시 끓는점에 닿으면 다시 알려요.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("데이터") {
                Button("데이터 폴더 열기") { model.openDataFolder() }
                Text("점수 이벤트와 개인 기준만 저장하며, 메시지 원문은 저장하지 않습니다.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("대화 온도는 언어 신호를 온도에 빗댄 값이며 실제 체온이나 감정·건강 상태의 진단이 아닙니다.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var devicesTab: some View {
        Form {
            Section("선택적 기기 연결") {
                if model.syncPath.isEmpty {
                    Text("이 Mac만으로도 모든 기능을 사용할 수 있습니다. iCloud Drive 같은 동기화 폴더를 고르면 여러 Mac의 점수 이벤트를 합칩니다.")
                        .foregroundStyle(.secondary)
                    Button("동기화 폴더 선택…") { model.chooseSyncFolder() }
                        .buttonStyle(.borderedProminent)
                } else {
                    LabeledContent("동기화 폴더") {
                        Text(model.syncPath)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                    Button("기기 연결 해제", role: .destructive) { model.disconnectSync() }
                }
            }

            if !model.devices.isEmpty {
                Section("연결된 기기") {
                    ForEach(model.devices, id: \.deviceID) { device in
                        HStack {
                            Image(systemName: "laptopcomputer")
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(device.name)
                                Text(device.updatedAt, style: .relative)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("마지막 확인")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }

            Section {
                Text("기기 간 반영 속도는 선택한 폴더 제공자에 따라 달라질 수 있습니다.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
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
        Binding(
            get: { model.halfLifeMinutes },
            set: { model.setHalfLifeMinutes($0) }
        )
    }

    @ViewBuilder
    private var errorNotice: some View {
        if let error = model.errorMessage {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .textSelection(.enabled)
                .accessibilityLabel("오류: \(error)")
        }
    }

    private func addRule() {
        var rules = editableRules.wrappedValue
        rules.append(LanguageRule(phrase: "", weight: 10, reason: "사용자 지정 신호"))
        editableRules.wrappedValue = rules
    }

    private func removeRule(id: String) {
        editableRules.wrappedValue.removeAll { $0.id == id }
    }
}

private struct RuleEditorRow: View {
    @Binding var rule: LanguageRule
    let unit: TemperatureUnit
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle("감지", isOn: $rule.enabled)
                    .labelsHidden()
                    .accessibilityLabel("\(rule.phrase.isEmpty ? "새 표현" : rule.phrase) 감지")
                TextField("표현", text: $rule.phrase)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("감지할 표현")
                Button(role: .destructive, action: remove) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("\(rule.phrase.isEmpty ? "새 표현" : rule.phrase) 삭제")
            }

            HStack(spacing: 12) {
                TextField("판단 이유", text: $rule.reason)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("판단 이유")
                Slider(value: $rule.weight, in: 5...50, step: 1)
                    .frame(width: 130)
                    .accessibilityLabel("대화 온도 상승")
                    .accessibilityValue(TemperatureDisplay.formattedRise(points: rule.weight, unit: unit))
                Text(TemperatureDisplay.formattedRise(points: rule.weight, unit: unit))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 62, alignment: .trailing)
                Text(severityLabel)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 34)
            }
        }
        .padding(.vertical, 5)
    }

    private var severityLabel: String {
        if rule.weight < 15 { return "약함" }
        if rule.weight < 30 { return "중간" }
        return "강함"
    }
}

private struct BaselineRuleRow: View {
    let rule: LanguageRule
    let unit: TemperatureUnit

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(rule.phrase)
                .font(.callout.weight(.medium))
                .frame(width: 110, alignment: .leading)
            Text(rule.reason)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(TemperatureDisplay.formattedRise(points: rule.weight, unit: unit))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(rule.phrase), \(rule.reason), \(TemperatureDisplay.formattedRise(points: rule.weight, unit: unit))")
    }
}

private struct ScorePoint: Identifiable {
    let date: Date
    let temperature: Double
    var id: Date { date }
}

private enum AngerLevel {
    case calm, warm, hot, alert

    init(score: Double) {
        switch score {
        case 100...: self = .alert
        case 70..<100: self = .hot
        case 35..<70: self = .warm
        default: self = .calm
        }
    }

    var label: String {
        switch self {
        case .calm: return "감지된 신호가 적어요"
        case .warm: return "조금 뜨거워졌어요"
        case .hot: return "많이 뜨거워졌어요"
        case .alert: return "잠깐 쉬어갈 때예요"
        }
    }

    var guidance: String {
        switch self {
        case .calm: return "최근 언어에서 거친 신호가 적게 감지됐어요."
        case .warm: return "내 말이 조금 거칠어지고 있음을 알아차려 보세요."
        case .hot: return "답을 보내기 전 잠시 멈춰도 괜찮아요."
        case .alert: return "지금 많이 화난 상태일 수 있어요. 잠깐 식혀 보세요."
        }
    }

    var color: Color {
        switch self {
        case .calm: return .accentColor
        case .warm: return .orange
        case .hot, .alert: return .red
        }
    }
}
