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
    public static let starter = PersonalProfile(id: "starter-v1", updatedAt: Date(timeIntervalSince1970: 0), summary: "기본 기준입니다. 과거 세션을 분석해 나에게 맞춰 보세요.", rules: [LanguageRule(id:"r1",phrase:"시발",weight:30,reason:"직접적인 욕설"),LanguageRule(id:"r2",phrase:"씨발",weight:30,reason:"직접적인 욕설"),LanguageRule(id:"r3",phrase:"병신",weight:40,reason:"직접적인 모욕"),LanguageRule(id:"r4",phrase:"개쓰레기",weight:30,reason:"강한 비하"),LanguageRule(id:"r5",phrase:"몇 번을 말",weight:8,reason:"반복된 불만"),LanguageRule(id:"r6",phrase:"빨리 끝내",weight:5,reason:"가벼운 재촉"),LanguageRule(id:"r7",phrase:"fuck",weight:25,reason:"직접적인 욕설"),LanguageRule(id:"r8",phrase:"ㅅㅂ",weight:25,reason:"욕설 축약"),LanguageRule(id:"r9",phrase:"개새끼",weight:40,reason:"직접적인 모욕")])
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
