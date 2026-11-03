import Foundation

/// Tokenising for recall and duplicate detection.
public enum Text {
    static let stop: Set<String> = Set("a an the and or of to for in on at by with from is are be it this that my me i we you your so do get go as if into up out".split(separator: " ").map(String.init))

    public static func stem(_ w: String) -> String {
        if w.count > 5 && w.hasSuffix("ing") { return String(w.dropLast(3)) }
        if w.count > 4 && w.hasSuffix("ies") { return String(w.dropLast(3)) + "y" }
        if w.count > 4 && w.hasSuffix("ed") { return String(w.dropLast(2)) }
        if w.count > 3 && w.hasSuffix("s") && !w.hasSuffix("ss") { return String(w.dropLast(1)) }
        return w
    }

    public static func tokens(_ text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { !stop.contains($0) && ($0.count > 1 || $0.contains(where: \.isNumber)) }
            .map(stem)
    }

    public static func titleKey(_ title: String) -> String { Set(tokens(title)).sorted().joined(separator: " ") }

    public static func jaccard(_ a: [String], _ b: [String]) -> Double {
        let A = Set(a), B = Set(b)
        guard !A.isEmpty, !B.isEmpty else { return 0 }
        return Double(A.intersection(B).count) / Double(A.union(B).count)
    }
}
