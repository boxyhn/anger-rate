import Darwin
import Foundation
import XCTest
@testable import AngerCore

final class HistoryAuditMemoryTests: XCTestCase {
    func testLargeHistoryStaysWithinMemoryBudgetOnBackgroundThread() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // Stream a 256 MiB synthetic log to disk without retaining the fixture in memory.
        let file = root.appendingPathComponent("large.jsonl")
        XCTAssertTrue(FileManager.default.createFile(atPath: file.path, contents: nil))
        let handle = try FileHandle(forWritingTo: file)
        try autoreleasepool {
            let marker = Data("{\"timestamp\":\"2026-01-01T00:00:00Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"user_message\",\"message\":\"memory test marker\"}}\n".utf8)
            var padding = try JSONSerialization.data(withJSONObject: [
                "type": "response_item",
                "payload": ["type": "message", "role": "assistant", "content": [
                    ["type": "output_text", "text": String(repeating: "x", count: 128 * 1024)]
                ]]
            ])
            padding.append(0x0A)
            try handle.write(contentsOf: marker)
            for _ in 0..<2048 { try handle.write(contentsOf: padding) }
            try handle.write(contentsOf: marker)
        }
        try handle.close()

        let finished = expectation(description: "Background history audit")
        DispatchQueue.global(qos: .utility).async {
            // Match the long-lived detached task used by the app: temporary
            // Foundation objects must be drained inside the audit, not by XCTest.
            autoreleasepool {
                do {
                    let baseline = try Self.footprint()
                    let budget: UInt64 = 96 * 1024 * 1024
                    let memory = MemoryBudgetProbe(baseline: baseline, budget: budget)
                    let report = HistoryAuditor(roots: [root]).audit(isCancelled: {
                        memory.exceeded()
                    })
                    XCTAssertNil(memory.error)
                    XCTAssertLessThan(memory.peakGrowth, budget,
                                      "History audit retained temporary allocations: \(memory.peakGrowth) bytes")
                    XCTAssertTrue(report.completed, "Audit must finish without exceeding its memory budget")
                    XCTAssertEqual(report.readFiles, 1)
                    XCTAssertEqual(report.userMessages, 2)
                    XCTAssertEqual(report.uniqueMessages, 1)
                    XCTAssertEqual(report.selectedMessages.first?.text, "memory test marker")
                } catch {
                    XCTFail("Could not measure process memory: \(error)")
                }
            }
            finished.fulfill()
        }
        wait(for: [finished], timeout: 60)
    }

    fileprivate static func footprint() throws -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            throw NSError(domain: "MachTaskInfo", code: Int(result))
        }
        return info.phys_footprint
    }
}

// Accessed synchronously by the audit on one background thread.
private final class MemoryBudgetProbe: @unchecked Sendable {
    let baseline: UInt64
    let budget: UInt64
    var peakGrowth: UInt64 = 0
    var error: Error?

    init(baseline: UInt64, budget: UInt64) {
        self.baseline = baseline
        self.budget = budget
    }

    func exceeded() -> Bool {
        do {
            let current = try HistoryAuditMemoryTests.footprint()
            peakGrowth = max(peakGrowth, current > baseline ? current - baseline : 0)
            // Stop the old implementation before it can exhaust CI memory.
            return peakGrowth >= budget
        } catch {
            self.error = error
            return true
        }
    }
}
