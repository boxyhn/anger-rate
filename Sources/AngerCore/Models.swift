import Foundation

public struct SessionMessage: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var timestamp: Date
    public var source: String
    public var text: String
    public init(id: String, timestamp: Date, source: String, text: String) { self.id = id; self.timestamp = timestamp; self.source = source; self.text = text }
}
public struct LanguageRule: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var phrase: String
    public var weight: Double
    public var reason: String
    public var enabled: Bool
    public init(id: String = UUID().uuidString, phrase: String, weight: Double, reason: String, enabled: Bool = true) { self.id = id; self.phrase = phrase; self.weight = weight; self.reason = reason; self.enabled = enabled }
}
public struct PersonalProfile: Codable, Equatable, Sendable {
    public var id: String
    public var updatedAt: Date
    public var summary: String
    public var rules: [LanguageRule]
    public var halfLifeSeconds: Double
    public init(id: String = UUID().uuidString, updatedAt: Date = Date(), summary: String, rules: [LanguageRule], halfLifeSeconds: Double = 300) { self.id = id; self.updatedAt = updatedAt; self.summary = summary; self.rules = rules; self.halfLifeSeconds = halfLifeSeconds }
    public static let starter = PersonalProfile(id: "starter-v2", updatedAt: Date(timeIntervalSince1970: 0), summary: "공통 한국어·영어 욕설은 기본 감지됩니다. 개인 기준에는 나만의 다른 분노 신호를 추가하세요.", rules: [])
}
public struct ScoredEvent: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var timestamp: Date
    public var deviceID: String
    public var source: String
    public var points: Double
    public var reasons: [String]
    public var profileID: String
    public init(id: String, timestamp: Date, deviceID: String, source: String, points: Double, reasons: [String], profileID: String) { self.id=id; self.timestamp=timestamp; self.deviceID=deviceID; self.source=source; self.points=points; self.reasons=reasons; self.profileID=profileID }
}
