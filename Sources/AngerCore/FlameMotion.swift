import Foundation

public enum FlameMotion {
    public static func level(_ score: Double) -> Int { score < 33 ? 0 : score < 66 ? 1 : 2 }
    public static func frequency(_ score: Double) -> Double {
        let value = min(100, max(0, score))
        let stops: [(Double, Double)] = [(0, 0.42), (33, 0.8), (66, 1.4), (85, 2.1), (100, 3.2)]
        for index in 1..<stops.count where value <= stops[index].0 {
            let (a, x) = stops[index - 1], (b, y) = stops[index]
            return x + (y - x) * (value - a) / (b - a)
        }
        return 3.2
    }
}
