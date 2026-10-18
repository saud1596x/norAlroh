import Foundation

enum MushafAudioTime {
    static func text(_ seconds: TimeInterval) -> String {
        let whole = seconds.isFinite ? Int(max(0, min(seconds, Double(Int.max / 2)))) : 0
        return "\(whole / 60):" + String(format: "%02d", whole % 60)
    }
    static func date(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "ar_SA")
        formatter.calendar = Calendar(identifier: .gregorian); formatter.timeZone = .current
        formatter.dateFormat = "d MMMM yyyy · HH:mm"
        return formatter.string(from: date).map { character in
            character.wholeNumberValue.map(String.init) ?? String(character)
        }.joined()
    }
}
