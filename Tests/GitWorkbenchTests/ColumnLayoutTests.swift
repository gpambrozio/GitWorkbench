import XCTest
@testable import GitWorkbench

final class ColumnLayoutTests: XCTestCase {

    /// A reference-backed `WorkbenchLayoutStore` so a second `ColumnLayout` sees the first's writes.
    private final class MemoryStore: @unchecked Sendable {
        var data: [String: [String: CGFloat]] = [:]
        var asLayoutStore: WorkbenchLayoutStore {
            WorkbenchLayoutStore(load: { [self] key in data[key] },
                                 save: { [self] key, widths in data[key] = widths })
        }
    }

    private func config(key: String?, store: WorkbenchLayoutStore?) -> WorkbenchConfiguration {
        var c = WorkbenchConfiguration()
        c.persistenceKey = key
        c.layoutStore = store
        return c
    }

    func test_persistsAndRestoresWhenStoreProvided() {
        let mem = MemoryStore()
        let a = ColumnLayout(configuration: config(key: "repo1", store: mem.asLayoutStore))
        a.railWidth = 300
        a.changesListWidth = 420

        let b = ColumnLayout(configuration: config(key: "repo1", store: mem.asLayoutStore))
        XCTAssertEqual(b.railWidth, 300)
        XCTAssertEqual(b.changesListWidth, 420)
    }

    func test_noPersistenceWithoutStore() {
        let a = ColumnLayout(configuration: config(key: "repo1", store: nil))
        a.railWidth = 300

        let b = ColumnLayout(configuration: config(key: "repo1", store: nil))
        XCTAssertEqual(b.railWidth, WorkbenchConfiguration().layout.railWidth)   // default; nothing stored
    }

    func test_separateKeysDoNotShare() {
        let mem = MemoryStore()
        let a = ColumnLayout(configuration: config(key: "paneA", store: mem.asLayoutStore))
        a.railWidth = 300

        let b = ColumnLayout(configuration: config(key: "paneB", store: mem.asLayoutStore))
        XCTAssertEqual(b.railWidth, WorkbenchConfiguration().layout.railWidth)   // different key → default
    }

    func test_restoreClampsOutOfRangeValue() {
        let mem = MemoryStore()
        mem.data["repo1"] = ["rail": 9999]
        let a = ColumnLayout(configuration: config(key: "repo1", store: mem.asLayoutStore))
        XCTAssertLessThanOrEqual(a.railWidth, a.railRange.upperBound)
        XCTAssertGreaterThanOrEqual(a.railWidth, a.railRange.lowerBound)
    }
}
