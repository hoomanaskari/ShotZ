import CoreGraphics
import Foundation
import Testing
@testable import AnnotationKit

struct PersistenceTests {
    @Test func writesVersionAndRoundTripsEveryShape() throws {
        let doc = ShowcaseTests.showcaseDocument()
        let data = try doc.jsonData()
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["version"] as? Int == AnnotationDocument.formatVersion)
        #expect(try JSONDecoder().decode(AnnotationDocument.self, from: data) == doc)
        let url = FileManager.default.temporaryDirectory.appending(path: "shotz-doc-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) } // best-effort cleanup of a temp file
        try doc.save(to: url)
        #expect(try AnnotationDocument.load(from: url) == doc)
    }

    @Test func tolerantDecoding() throws {
        // An old/foreign document: no version, no scale, one object of an unknown kind,
        // one with a style missing most fields and an unknown enum value.
        let json = """
        {"baseImageURL":"file:///tmp/a.png","pixelSize":[100,50],
         "objects":[
           {"id":"7D0F5C2E-8E64-4C76-9E1B-3E5E0A7C1A11","shape":{"hologram":{"_0":1}},"style":{}},
           {"id":"7D0F5C2E-8E64-4C76-9E1B-3E5E0A7C1A12","shape":{"line":{"start":[0,0],"end":[10,10]}},
            "style":{"lineWidth":7,"dash":"wiggly"}},
           {"id":"7D0F5C2E-8E64-4C76-9E1B-3E5E0A7C1A13","shape":{"counter":{"_0":{"center":[5,5]}}}}
         ],
         "background":{"padding":0.1,"shadow":"dramatic"},
         "futureField":true, "version":99}
        """
        let doc = try JSONDecoder().decode(AnnotationDocument.self, from: Data(json.utf8))
        #expect(doc.scale == 1)
        #expect(doc.objects.count == 2)
        #expect(doc.objects[0].style.lineWidth == 7)
        #expect(doc.objects[0].style.dash == .solid)
        #expect(doc.objects[0].style.color == ObjectStyle.default.color)
        #expect(doc.objects[1].shape == .counter(CounterGeometry(center: CGPoint(x: 5, y: 5), value: 1)))
        #expect(doc.background?.padding == 0.1)
        #expect(doc.background?.shadow == .soft)
    }

    @Test func missingRequiredFieldsStillFail() {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(AnnotationDocument.self, from: Data(#"{"objects":[]}"#.utf8))
        }
    }
}
