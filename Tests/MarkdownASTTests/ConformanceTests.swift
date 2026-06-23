import Testing
import Foundation
@testable import MarkdownAST

struct SpecCase: Decodable {
    let markdown: String
    let html: String
    let example: Int
    let section: String
}

func loadSpecCases() -> [SpecCase] {
    guard let url = Bundle.module.url(forResource: "commonmark-spec", withExtension: "json"),
          let data = try? Data(contentsOf: url) else { return [] }
    return (try? JSONDecoder().decode([SpecCase].self, from: data)) ?? []
}

func conformanceActual(_ markdown: String) -> String {
    normalizeHTML(astToHTML(MarkdownParser.parse(markdown)))
}

@Suite("CommonMark conformance (diagnostic)")
struct ConformanceDiagnostic {
    @Test("report pass rate by section")
    func report() {
        let cases = loadSpecCases()
        var bySection: [String: (pass: Int, total: Int)] = [:]
        var totalPass = 0
        for c in cases {
            let ok = conformanceActual(c.markdown) == normalizeHTML(c.html)
            if ok { totalPass += 1 }
            var e = bySection[c.section] ?? (0, 0)
            e.total += 1
            if ok { e.pass += 1 }
            bySection[c.section] = e
        }
        print("CONFORMANCE-TOTAL \(totalPass)/\(cases.count)")
        for (section, r) in bySection.sorted(by: { $0.key < $1.key }) {
            print("CONFORMANCE-SECTION \(r.pass)/\(r.total) \(section)")
        }
        #expect(!cases.isEmpty)
    }
}
