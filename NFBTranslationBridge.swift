import UIKit
import SwiftUI
import NaturalLanguage
import Translation

@available(iOS 18.0, *)
private struct NFBTranslationTaskView: View {
    let text: String
    let source: String
    let target: String
    let completion: (String?, NSError?) -> Void

    var body: some View {
        Color.clear
            .translationTask(source: Locale.Language(identifier: source), target: Locale.Language(identifier: target)) { session in
                do {
                    // Apple's session presents the language download consent if needed.
                    try await session.prepareTranslation()
                    try Task.checkCancellation()
                    let response = try await session.translate(text)
                    try Task.checkCancellation()
                    await MainActor.run { completion(response.targetText, nil) }
                } catch {
                    await MainActor.run { completion(nil, error as NSError) }
                }
            }
    }
}

@objc(NFBTranslationBridge)
final class NFBTranslationBridge: NSObject {
    @objc static var available: Bool {
        if #available(iOS 18.0, *) { return true }
        return false
    }

    @objc(candidateForText:languages:completion:)
    static func candidate(text: String, languages: [String], completion: @escaping (String?, String?) -> Void) {
        guard #available(iOS 18.0, *) else { completion(nil, nil); return }
        let preferred = Locale.preferredLanguages
        Task.detached {
            let prose = NFBTranslationPolicy.detectionText(text)
            guard prose.unicodeScalars.contains(where: CharacterSet.letters.contains) else {
                await MainActor.run { completion(nil, nil) }; return
            }
            let recognizer = NLLanguageRecognizer()
            recognizer.processString(prose)
            let hypotheses = recognizer.languageHypotheses(withMaximum: 1)
            let detected = recognizer.dominantLanguage
            // Actual prose wins over a stale author language tag. For short,
            // uncertain text a single declared language is a useful fallback.
            let source: String?
            if let detected, (hypotheses[detected] ?? 0) >= 0.6 {
                source = detected.rawValue
            } else {
                source = languages.count == 1 ? languages.first : nil
            }
            guard let source, NFBTranslationPolicy.isForeign(source, preferred: preferred), let target = preferred.first else {
                await MainActor.run { completion(nil, nil) }; return
            }
            let status = await LanguageAvailability().status(from: Locale.Language(identifier: source), to: Locale.Language(identifier: target))
            await MainActor.run {
                completion(status == .unsupported ? nil : source, status == .unsupported ? nil : target)
            }
        }
    }

    @MainActor @objc(controllerForText:source:target:completion:)
    static func controller(text: String, source: String, target: String, completion: @escaping (String?, NSError?) -> Void) -> UIViewController? {
        guard #available(iOS 18.0, *) else { return nil }
        let host = UIHostingController(rootView: NFBTranslationTaskView(text: text, source: source, target: target, completion: completion))
        host.view.backgroundColor = .clear
        return host
    }
}
