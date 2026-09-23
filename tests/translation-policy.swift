import Foundation

@main struct TranslationPolicyTests {
    static func main() {
        assert(!NFBTranslationPolicy.isForeign("en-GB", preferred: ["en-US"]))
        assert(!NFBTranslationPolicy.isForeign("es", preferred: ["en-US", "es-MX"]))
        assert(!NFBTranslationPolicy.isForeign("zh-Hant", preferred: ["zh-Hans-CN"]))
        assert(!NFBTranslationPolicy.isForeign("iw", preferred: ["he-IL"]))
        assert(!NFBTranslationPolicy.isForeign("nb-NO", preferred: ["nn"]))
        assert(NFBTranslationPolicy.isForeign("ja", preferred: ["en-US"]))
        assert(NFBTranslationPolicy.isForeign("es", preferred: ["en-US"]))
        assert(!NFBTranslationPolicy.isForeign("und", preferred: ["en-US"]))
        assert(!NFBTranslationPolicy.isForeign("", preferred: ["en-US"]))
        assert(NFBTranslationPolicy.detectionText("https://example.com @alice.bsky.social #topic").isEmpty)
        assert(NFBTranslationPolicy.detectionText("こんにちは https://example.com @alice.bsky.social") == "こんにちは")
        assert(NFBTranslationPolicy.detectionText("مرحبا بالعالم") == "مرحبا بالعالم")
        assert(NFBTranslationPolicy.baseLanguage("pt_BR") == "pt")
        print("PASS: preferred-language matching, multilingual preferences, script/region variants, language aliases, unknown languages and URL/handle/tag filtering")
    }
}
