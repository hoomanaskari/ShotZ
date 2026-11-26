import Testing
@testable import CaptureKit
import ShotzCore

struct CaptureOutcomeTests {
    @Test func classification() {
        let yes = { true }, no = { false }
        #expect(CaptureOutcome.classify(status: 0, stderr: "", fileExists: true, hasPermission: yes) == .image)
        #expect(CaptureOutcome.classify(status: 0, stderr: "", fileExists: true, hasPermission: no) == .failure(.permissionDenied))
        #expect(CaptureOutcome.classify(status: 1, stderr: "", fileExists: false, hasPermission: yes) == .cancelled)
        #expect(CaptureOutcome.classify(status: 0, stderr: "", fileExists: false, hasPermission: no) == .cancelled)
        #expect(CaptureOutcome.classify(status: 1, stderr: "screencapture: cannot run two interactive screen captures at a time", fileExists: false, hasPermission: yes) == .failure(.busy))
        #expect(CaptureOutcome.classify(status: 1, stderr: "boom", fileExists: false, hasPermission: yes) == .failure(.failed("boom")))
        #expect(CaptureOutcome.classify(status: 1, stderr: "boom", fileExists: false, hasPermission: no) == .failure(.permissionDenied))
    }

    @Test func kinds() {
        #expect(CaptureOutcome.kind(for: .fullscreen, hasAlpha: true) == .fullscreen)
        #expect(CaptureOutcome.kind(for: .window, hasAlpha: false) == .window)
        #expect(CaptureOutcome.kind(for: .area, hasAlpha: false) == .area)
        #expect(CaptureOutcome.kind(for: .area, hasAlpha: true) == .window)
        #expect(CaptureOutcome.kind(for: .allInOne, hasAlpha: true) == .window)
    }
}
