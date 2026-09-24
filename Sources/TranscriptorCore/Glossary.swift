import Foundation

/// User-maintained vocabulary: terms that bias decoding and corrections applied afterwards.
public struct Glossary: Sendable, Equatable {
    public struct Correction: Sendable, Equatable {
        public var wrong: String
        public var right: String
        public init(wrong: String, right: String) {
            self.wrong = wrong
            self.right = right
        }
    }

    public struct ParseError: Sendable, Equatable {
        public var line: Int
        public var message: String
    }

    public static let promptTokenBudget = 200
    public static let promptPrefix = "Clase de medicina. Términos: "

    public static let templateText = """
    # Glosario de Transcriptor
    # Una entrada por línea. Las líneas que empiezan con # son comentarios.
    #
    # 1) Un término por línea ayuda al modelo a escribirlo bien:
    hipokalemia
    hiperkalemia
    enalapril
    espironolactona
    cetoacidosis diabética
    #
    # 2) Una corrección reemplaza lo que el modelo escribe mal por lo correcto:
    hipocalemia => hipokalemia
    hipercalemia => hiperkalemia
    """

    public private(set) var terms: [String] = []
    public private(set) var corrections: [Correction] = []
    public private(set) var parseErrors: [ParseError] = []

    public init(text: String) {
        var seen = Set<String>()
        func addTerm(_ term: String) {
            let key = term.lowercased()
            if seen.insert(key).inserted { terms.append(term) }
        }

        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        for (index, raw) in lines.enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if let range = line.range(of: "=>") {
                let wrong = line[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
                let right = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
                if wrong.isEmpty || right.isEmpty {
                    parseErrors.append(ParseError(line: index + 1, message: "Falta un lado de la corrección (formato: incorrecto => correcto)."))
                    continue
                }
                corrections.append(Correction(wrong: wrong, right: right))
                addTerm(right)
            } else {
                addTerm(line)
            }
        }
    }

    /// Builds the decoding prompt from terms in file order, stopping at the token budget.
    public func promptText(tokenCount: (String) async -> Int) async -> (text: String?, truncated: Bool) {
        guard !terms.isEmpty else { return (nil, false) }
        var included: [String] = []
        for term in terms {
            let candidate = Self.promptPrefix + (included + [term]).joined(separator: ", ") + "."
            if await tokenCount(candidate) > Self.promptTokenBudget { break }
            included.append(term)
        }
        guard !included.isEmpty else { return (nil, true) }
        return (Self.promptPrefix + included.joined(separator: ", ") + ".", included.count < terms.count)
    }

    /// Applies corrections in file order: case-insensitive, whole-word, keeping a leading capital.
    public func applyCorrections(to text: String) -> String {
        var result = text
        for correction in corrections {
            // Lookarounds instead of \b so sources ending in punctuation ("v.o.") still match before a space.
            let escaped = NSRegularExpression.escapedPattern(for: correction.wrong)
            let pattern = "(?<![\\p{L}\\p{N}])" + escaped + "(?![\\p{L}\\p{N}])"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let nsResult = result as NSString
            let matches = regex.matches(in: result, range: NSRange(location: 0, length: nsResult.length))
            var mutable = result
            for match in matches.reversed() {
                let original = nsResult.substring(with: match.range)
                var replacement = correction.right
                if let first = original.first, first.isUppercase {
                    replacement = replacement.prefix(1).uppercased() + replacement.dropFirst()
                }
                mutable = (mutable as NSString).replacingCharacters(in: match.range, with: replacement)
            }
            result = mutable
        }
        return result
    }
}
