import Foundation

/// A deliberately broad, authored baseline of common Korean and English
/// profanity. It improves useful default coverage but is not a mathematical
/// claim that every spelling, dialect, or newly coined expression is included.
public enum ProfanityLexicon {
    public static let rules: [LanguageRule] = entries.map { entry in
        LanguageRule(
            id: "builtin.\(entry.id)",
            phrase: entry.phrase,
            weight: entry.weight,
            reason: entry.reason
        )
    }

    private struct Entry {
        let id: String
        let phrase: String
        let weight: Double
        let reason: String
    }

    private static let entries: [Entry] = [
        // Korean: common spellings, abbreviations, and syllable variants.
        Entry(id: "ko.sibal", phrase: "시발", weight: 30, reason: "공통 욕설"),
        Entry(id: "ko.ssibal", phrase: "씨발", weight: 30, reason: "공통 욕설"),
        Entry(id: "ko.ssipal", phrase: "씨팔", weight: 28, reason: "공통 욕설 변형"),
        Entry(id: "ko.ssibeol", phrase: "씨벌", weight: 28, reason: "공통 욕설 변형"),
        Entry(id: "ko.ssibural", phrase: "씨부랄", weight: 30, reason: "공통 욕설 변형"),
        Entry(id: "ko.sbieup", phrase: "ㅅㅂ", weight: 24, reason: "공통 욕설 축약"),
        Entry(id: "ko.ssb", phrase: "ㅆㅂ", weight: 24, reason: "공통 욕설 축약"),
        Entry(id: "ko.sp", phrase: "ㅅㅍ", weight: 22, reason: "공통 욕설 축약"),
        Entry(id: "ko.jot", phrase: "좆", weight: 32, reason: "강한 공통 욕설"),
        Entry(id: "ko.jotvariant", phrase: "좃", weight: 30, reason: "강한 공통 욕설 변형"),
        Entry(id: "ko.jonna", phrase: "존나", weight: 24, reason: "강한 비속어"),
        Entry(id: "ko.jolla", phrase: "졸라", weight: 18, reason: "비속어 강조"),
        Entry(id: "ko.gaesaekki", phrase: "개새끼", weight: 42, reason: "직접적인 모욕"),
        Entry(id: "ko.gaesaekki2", phrase: "개색끼", weight: 40, reason: "직접적인 모욕 변형"),
        Entry(id: "ko.gaesaekki3", phrase: "개세끼", weight: 40, reason: "직접적인 모욕 변형"),
        Entry(id: "ko.gaesaekki4", phrase: "개쉐끼", weight: 40, reason: "직접적인 모욕 변형"),
        Entry(id: "ko.saekki", phrase: "새끼", weight: 32, reason: "직접적인 모욕"),
        Entry(id: "ko.saekki2", phrase: "색끼", weight: 30, reason: "직접적인 모욕 변형"),
        Entry(id: "ko.ssang", phrase: "썅", weight: 25, reason: "공통 욕설"),
        Entry(id: "ko.ssangnom", phrase: "쌍놈", weight: 38, reason: "직접적인 모욕"),
        Entry(id: "ko.ssangnyeon", phrase: "쌍년", weight: 40, reason: "직접적인 모욕"),
        Entry(id: "ko.byeongsin", phrase: "병신", weight: 40, reason: "직접적인 모욕"),
        Entry(id: "ko.byungsin", phrase: "븅신", weight: 38, reason: "직접적인 모욕 변형"),
        Entry(id: "ko.bingsin", phrase: "빙신", weight: 35, reason: "직접적인 모욕 변형"),
        Entry(id: "ko.deungsin", phrase: "등신", weight: 32, reason: "직접적인 모욕"),
        Entry(id: "ko.meoreori", phrase: "머저리", weight: 30, reason: "직접적인 모욕"),
        Entry(id: "ko.jiral", phrase: "지랄", weight: 28, reason: "공통 욕설"),
        Entry(id: "ko.gaejiral", phrase: "개지랄", weight: 34, reason: "강한 공통 욕설"),
        Entry(id: "ko.yeombyeong", phrase: "염병", weight: 28, reason: "공통 욕설"),
        Entry(id: "ko.gaessori", phrase: "개소리", weight: 28, reason: "강한 비하"),
        Entry(id: "ko.gaegat", phrase: "개같", weight: 30, reason: "강한 비하"),
        Entry(id: "ko.gaepan", phrase: "개판", weight: 20, reason: "거친 비하"),
        Entry(id: "ko.gaebbak", phrase: "개빡", weight: 24, reason: "강한 분노 표현"),
        Entry(id: "ko.bbakchi", phrase: "빡치", weight: 22, reason: "강한 분노 표현"),
        Entry(id: "ko.jotgat", phrase: "좆같", weight: 36, reason: "강한 공통 욕설"),
        Entry(id: "ko.jotkka", phrase: "좆까", weight: 40, reason: "공격적인 욕설"),
        Entry(id: "ko.kkeojyeo", phrase: "꺼져", weight: 26, reason: "공격적인 표현"),
        Entry(id: "ko.dakchyeo", phrase: "닥쳐", weight: 30, reason: "공격적인 표현"),
        Entry(id: "ko.michinnom", phrase: "미친놈", weight: 36, reason: "직접적인 모욕"),
        Entry(id: "ko.michinnyeon", phrase: "미친년", weight: 38, reason: "직접적인 모욕"),
        Entry(id: "ko.ttorai", phrase: "또라이", weight: 32, reason: "직접적인 모욕"),
        Entry(id: "ko.sseuregi", phrase: "쓰레기", weight: 28, reason: "강한 비하"),
        Entry(id: "ko.gaesseuregi", phrase: "개쓰레기", weight: 34, reason: "강한 비하"),
        Entry(id: "ko.horosaekki", phrase: "호로새끼", weight: 46, reason: "직접적인 모욕"),
        Entry(id: "ko.hurejasik", phrase: "후레자식", weight: 42, reason: "직접적인 모욕"),
        Entry(id: "ko.neugeumma", phrase: "느금마", weight: 46, reason: "가족 대상 모욕"),
        Entry(id: "ko.nimi", phrase: "니미", weight: 30, reason: "공통 욕설"),
        Entry(id: "ko.finger", phrase: "ㅗ", weight: 18, reason: "모욕 표현"),

        // English: explicit morphology and common light obfuscations.
        Entry(id: "en.fuck", phrase: "fuck", weight: 30, reason: "Common profanity"),
        Entry(id: "en.fucks", phrase: "fucks", weight: 30, reason: "Common profanity"),
        Entry(id: "en.fucked", phrase: "fucked", weight: 32, reason: "Common profanity"),
        Entry(id: "en.fucking", phrase: "fucking", weight: 32, reason: "Common profanity"),
        Entry(id: "en.fucker", phrase: "fucker", weight: 38, reason: "Direct insult"),
        Entry(id: "en.fuckers", phrase: "fuckers", weight: 38, reason: "Direct insult"),
        Entry(id: "en.fstarck", phrase: "f*ck", weight: 28, reason: "Obfuscated profanity"),
        Entry(id: "en.fstarstarck", phrase: "f**k", weight: 28, reason: "Obfuscated profanity"),
        Entry(id: "en.fdotuck", phrase: "f.u.c.k", weight: 28, reason: "Obfuscated profanity"),
        Entry(id: "en.fspaceuck", phrase: "f u c k", weight: 28, reason: "Obfuscated profanity"),
        Entry(id: "en.fdashuck", phrase: "f-u-c-k", weight: 28, reason: "Obfuscated profanity"),
        Entry(id: "en.motherfucker", phrase: "motherfucker", weight: 46, reason: "Direct insult"),
        Entry(id: "en.motherfuckers", phrase: "motherfuckers", weight: 46, reason: "Direct insult"),
        Entry(id: "en.shit", phrase: "shit", weight: 26, reason: "Common profanity"),
        Entry(id: "en.shits", phrase: "shits", weight: 26, reason: "Common profanity"),
        Entry(id: "en.shitty", phrase: "shitty", weight: 28, reason: "Common profanity"),
        Entry(id: "en.bullshit", phrase: "bullshit", weight: 32, reason: "Strong profanity"),
        Entry(id: "en.bullshitting", phrase: "bullshitting", weight: 32, reason: "Strong profanity"),
        Entry(id: "en.bitch", phrase: "bitch", weight: 38, reason: "Direct insult"),
        Entry(id: "en.bitches", phrase: "bitches", weight: 38, reason: "Direct insult"),
        Entry(id: "en.bastard", phrase: "bastard", weight: 36, reason: "Direct insult"),
        Entry(id: "en.bastards", phrase: "bastards", weight: 36, reason: "Direct insult"),
        Entry(id: "en.asshole", phrase: "asshole", weight: 42, reason: "Direct insult"),
        Entry(id: "en.assholes", phrase: "assholes", weight: 42, reason: "Direct insult"),
        Entry(id: "en.dumbass", phrase: "dumbass", weight: 36, reason: "Direct insult"),
        Entry(id: "en.jackass", phrase: "jackass", weight: 34, reason: "Direct insult"),
        Entry(id: "en.dickhead", phrase: "dickhead", weight: 42, reason: "Direct insult"),
        Entry(id: "en.douchebag", phrase: "douchebag", weight: 38, reason: "Direct insult"),
        Entry(id: "en.cunt", phrase: "cunt", weight: 46, reason: "Severe direct insult"),
        Entry(id: "en.cunts", phrase: "cunts", weight: 46, reason: "Severe direct insult"),
        Entry(id: "en.prick", phrase: "prick", weight: 34, reason: "Direct insult"),
        Entry(id: "en.pricks", phrase: "pricks", weight: 34, reason: "Direct insult"),
        Entry(id: "en.moron", phrase: "moron", weight: 32, reason: "Direct insult"),
        Entry(id: "en.morons", phrase: "morons", weight: 32, reason: "Direct insult"),
        Entry(id: "en.idiot", phrase: "idiot", weight: 30, reason: "Direct insult"),
        Entry(id: "en.idiots", phrase: "idiots", weight: 30, reason: "Direct insult"),
        Entry(id: "en.retard", phrase: "retard", weight: 42, reason: "Ableist direct insult"),
        Entry(id: "en.retarded", phrase: "retarded", weight: 42, reason: "Ableist direct insult"),
        Entry(id: "en.sonsofbitches", phrase: "sons of bitches", weight: 46, reason: "Direct insult"),
        Entry(id: "en.sonofabitch", phrase: "son of a bitch", weight: 44, reason: "Direct insult"),
        Entry(id: "en.pissoff", phrase: "piss off", weight: 28, reason: "Aggressive profanity"),
        Entry(id: "en.screwyou", phrase: "screw you", weight: 24, reason: "Aggressive expression")
    ]
}
