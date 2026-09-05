import Foundation

public enum AppLanguage: String, CaseIterable, Codable, Sendable {
    case system
    case korean
    case english

    public var resolved: SupportedLanguage {
        switch self {
        case .korean: return .korean
        case .english: return .english
        case .system:
            return Locale.preferredLanguages.first?.lowercased().hasPrefix("ko") == true ? .korean : .english
        }
    }
}

public enum SupportedLanguage: String, Codable, Sendable {
    case korean = "ko"
    case english = "en"

    public var locale: Locale { Locale(identifier: rawValue) }
}

public struct AppText: Sendable {
    public let language: SupportedLanguage

    public init(_ preference: AppLanguage = .system) {
        language = preference.resolved
    }

    public init(language: SupportedLanguage) {
        self.language = language
    }

    public func callAsFunction(_ korean: String, _ english: String) -> String {
        language == .korean ? korean : english
    }

    public func reason(_ reason: String) -> String {
        switch language {
        case .english: return Self.englishReasonTranslations[reason] ?? reason
        case .korean: return Self.koreanReasonTranslations[reason] ?? reason
        }
    }

    public var languageName: String {
        self("한국어", "English")
    }

    public func preferenceName(_ preference: AppLanguage) -> String {
        switch preference {
        case .system: return self("시스템 설정", "System Default")
        case .korean: return self("한국어", "Korean")
        case .english: return "English"
        }
    }

    private static let englishReasonTranslations: [String: String] = [
        "공통 욕설": "Common profanity",
        "공통 욕설 변형": "Profanity variant",
        "공통 욕설 축약": "Abbreviated profanity",
        "강한 공통 욕설": "Strong profanity",
        "강한 공통 욕설 변형": "Strong profanity variant",
        "강한 비속어": "Strong vulgar language",
        "비속어 강조": "Vulgar intensifier",
        "직접적인 모욕": "Direct insult",
        "직접적인 모욕 변형": "Direct insult variant",
        "강한 비하": "Strong derogatory language",
        "거친 비하": "Harsh derogatory language",
        "강한 분노 표현": "Strong anger expression",
        "공격적인 욕설": "Aggressive profanity",
        "공격적인 표현": "Aggressive expression",
        "가족 대상 모욕": "Family-directed insult",
        "모욕 표현": "Insulting expression",
        "영어 욕설": "English profanity",
        "강한 영어 욕설": "Strong English profanity",
        "영어 모욕": "English insult",
        "강한 영어 모욕": "Strong English insult",
        "영어 비하": "English derogatory language",
        "강한 영어 비하": "Strong English derogatory language",
        "사용자 지정 신호": "Custom signal",
        "직접적인 욕설": "Direct profanity",
        "반복된 불만 표현": "Repeated frustration"
    ]

    private static let koreanReasonTranslations: [String: String] = [
        "Common profanity": "공통 욕설",
        "Strong profanity": "강한 공통 욕설",
        "Obfuscated profanity": "가려 쓴 욕설",
        "Direct insult": "직접적인 모욕",
        "Severe direct insult": "매우 강한 직접적 모욕",
        "Ableist direct insult": "장애 비하 모욕",
        "Aggressive profanity": "공격적인 욕설",
        "Aggressive expression": "공격적인 표현",
        "Custom signal": "사용자 지정 신호"
    ]
}
