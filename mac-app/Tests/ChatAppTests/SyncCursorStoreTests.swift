import XCTest
@testable import ChatApp

final class SyncCursorStoreTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("sync-cursor-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        temporaryDirectory = nil
    }

    func testUnknownUserDefaultsToZero() {
        let store = SyncCursorStore(directory: temporaryDirectory)

        XCTAssertEqual(store.load(userId: "missing-user"), 0)
    }

    func testRoundTripsLastInboxSeqPerUserId() throws {
        let store = SyncCursorStore(directory: temporaryDirectory)

        try store.save(userId: "user-a", seq: 12)
        try store.save(userId: "user-b", seq: 34)

        let relaunchedStore = SyncCursorStore(directory: temporaryDirectory)
        XCTAssertEqual(relaunchedStore.load(userId: "user-a"), 12)
        XCTAssertEqual(relaunchedStore.load(userId: "user-b"), 34)
        XCTAssertEqual(relaunchedStore.load(userId: "user-c"), 0)
    }
}
