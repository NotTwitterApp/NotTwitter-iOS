import Foundation

// Keep language matching independent of UI/model availability for focused tests.
enum NFBTranslationPolicy {
    static func baseLanguage(_ identifier: String) -> String {
        let base = identifier.replacingOccurrences(of: "_", with: "-").split(separator: "-").first.map(String.init)?.lowercased() ?? ""
        return ["iw": "he", "in": "id", "ji": "yi", "nb": "no", "nn": "no" ][base] ?? base
    }

    static func isForeign(_ source: String, preferred: [String]) -> Bool {
        let language = baseLanguage(source)
        return !language.isEmpty && language != "und" && !preferred.contains { baseLanguage($0) == language }
    }

    static func detectionText(_ text: String) -> String {
        // URLs, handles and tags aren't evidence of the prose's language.
        text.replacingOccurrences(of: #"https?://\S+|www\.\S+|[@#][\p{L}\p{N}_.-]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
