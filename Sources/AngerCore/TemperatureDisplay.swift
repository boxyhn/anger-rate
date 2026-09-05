import Foundation

public enum TemperatureUnit: String, CaseIterable, Codable, Sendable {
    case celsius
    case fahrenheit

    public var symbol: String {
        switch self {
        case .celsius: return "°C"
        case .fahrenheit: return "°F"
        }
    }

    public var label: String {
        switch self {
        case .celsius: return "섭씨"
        case .fahrenheit: return "화씨"
        }
    }
}

/// Maps the internal 0...100 language-signal score to a thermometer metaphor.
/// This is a display-only conversion: alert and decay logic continue to use the
/// original score.
public enum TemperatureDisplay {
    public static let baselineCelsius = 36.5
    public static let boilingCelsius = 100.0

    public static func value(score: Double, unit: TemperatureUnit) -> Double {
        let normalizedScore = score.isFinite ? min(100, max(0, score)) : 0
        let celsius = baselineCelsius
            + (boilingCelsius - baselineCelsius) * normalizedScore / 100
        switch unit {
        case .celsius: return celsius
        case .fahrenheit: return celsius * 9 / 5 + 32
        }
    }

    public static func range(unit: TemperatureUnit) -> ClosedRange<Double> {
        value(score: 0, unit: unit)...value(score: 100, unit: unit)
    }

    public static func formatted(score: Double, unit: TemperatureUnit) -> String {
        var temperature = value(score: score, unit: unit)
        if score.isFinite, score < 100 {
            temperature = min(temperature, value(score: 100, unit: unit) - 0.1)
        }
        return formattedValue(temperature, unit: unit)
    }

    public static func formattedRise(points: Double, unit: TemperatureUnit) -> String {
        let celsiusRise = max(0, points) * (boilingCelsius - baselineCelsius) / 100
        let rise = unit == .celsius ? celsiusRise : celsiusRise * 9 / 5
        return "+\(number(rise))\(unit.symbol)"
    }

    private static func formattedValue(_ value: Double, unit: TemperatureUnit) -> String {
        "\(number(value))\(unit.symbol)"
    }

    private static func number(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return String(Int(rounded))
        }
        return String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), rounded)
    }
}
