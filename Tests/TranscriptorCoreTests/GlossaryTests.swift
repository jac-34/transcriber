import Testing
@testable import TranscriptorCore

@Suite struct GlossaryTests {
    @Test func parsesTermsCorrectionsCommentsAndBlankLines() {
        let g = Glossary(text: """
        # fármacos
        enalapril

        hipocalemia => hipokalemia
        Espironolactona
        """)
        #expect(g.terms == ["enalapril", "hipokalemia", "Espironolactona"])
        #expect(g.corrections == [Glossary.Correction(wrong: "hipocalemia", right: "hipokalemia")])
        #expect(g.parseErrors.isEmpty)
    }

    @Test func toleratesWindowsLineEndingsTrailingSpacesAndDuplicateCasing() {
        let g = Glossary(text: "enalapril  \r\nENALAPRIL\r\n  hipokalemia \r\n")
        #expect(g.terms == ["enalapril", "hipokalemia"])
    }

    @Test func reportsMalformedCorrectionsWithLineNumbers() {
        let g = Glossary(text: "ok\n => hipokalemia\nhipocalemia => \nbien")
        #expect(g.parseErrors.map(\.line) == [2, 3])
        #expect(g.terms == ["ok", "bien"])
    }

    @Test func promptIsNilWhenNoTerms() async {
        let g = Glossary(text: "# nada\n")
        let result = await g.promptText { $0.split(separator: " ").count }
        #expect(result.text == nil)
        #expect(result.truncated == false)
    }

    @Test func promptIncludesAllTermsWhenTheyFit() async {
        let g = Glossary(text: "hipokalemia\nenalapril")
        let result = await g.promptText { $0.split(separator: " ").count }
        #expect(result.text == "Clase de medicina. Términos: hipokalemia, enalapril.")
        #expect(result.truncated == false)
    }

    @Test func promptTruncatesInFileOrderWhenOverBudget() async {
        let terms = (1...300).map { "termino\($0)" }.joined(separator: "\n")
        let g = Glossary(text: terms)
        // One token per whitespace-separated word: prefix is 4 words, so ~196 terms fit.
        let result = await g.promptText { $0.split(separator: " ").count }
        #expect(result.truncated == true)
        let text = result.text!
        #expect(text.contains("termino1,"))
        #expect(!text.contains("termino300"))
        #expect(text.split(separator: " ").count <= Glossary.promptTokenBudget)
    }

    @Test func correctionsAreCaseInsensitiveWholeWordAndKeepCapitalization() {
        let g = Glossary(text: "hipocalemia => hipokalemia")
        let out = g.applyCorrections(to: "Hipocalemia severa. La hipocalemia y la pseudohipocalemia.")
        #expect(out == "Hipokalemia severa. La hipokalemia y la pseudohipocalemia.")
    }

    @Test func correctionsEscapeRegexMetacharactersAndHandleMultiWordSources() {
        let g = Glossary(text: "v.o. => vía oral\nen alaprilo => enalapril o")
        let out = g.applyCorrections(to: "Dar v.o. cada 8 horas con en alaprilo espironolactona. Sin vxox aquí.")
        #expect(out == "Dar vía oral cada 8 horas con enalapril o espironolactona. Sin vxox aquí.")
    }

    @Test func correctionsApplyInFileOrder() {
        let g = Glossary(text: "a1 => b1\nb1 => c1")
        #expect(g.applyCorrections(to: "a1 y b1") == "c1 y c1")
    }

    @Test func templateParsesCleanly() {
        let g = Glossary(text: Glossary.templateText)
        #expect(g.parseErrors.isEmpty)
        #expect(!g.terms.isEmpty)
    }
}
