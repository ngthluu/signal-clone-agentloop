import CryptoKit
import Foundation
import XCTest
@testable import ChatApp

final class AttachmentDescriptorTests: XCTestCase {
    func testDescriptorRoundTripsAndUsesSnakeCaseKeys() throws {
        let fileKey = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0).base64EncodedString() }
        let filenameSentinel = "DM_ATTACHMENT_FILENAME_SENTINEL_report.pdf"
        let descriptor = AttachmentDescriptor(
            attachmentId: "att-123",
            fileKey: fileKey,
            filename: filenameSentinel,
            mime: "application/pdf",
            size: 42
        )

        let encoded = try descriptor.encodedJSON()
        let decoded = try XCTUnwrap(AttachmentDescriptor.decode(encoded))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        XCTAssertEqual(decoded, descriptor)
        XCTAssertEqual(object["chatapp"] as? String, "attachment")
        XCTAssertEqual(object["v"] as? Int, 1)
        XCTAssertEqual(object["attachment_id"] as? String, "att-123")
        XCTAssertEqual(object["file_key"] as? String, fileKey)
        XCTAssertEqual(object["filename"] as? String, filenameSentinel)
        XCTAssertEqual(object["mime"] as? String, "application/pdf")
        XCTAssertEqual(object["size"] as? Int, 42)
    }

    func testPlainTextIsNotMisdetected() {
        XCTAssertNil(AttachmentDescriptor.decode(Data("hello ordinary text".utf8)))
    }

    func testJSONWithoutAttachmentMarkerIsNotMisdetected() {
        let json = Data(#"{"attachment_id":"att-123","file_key":"key","filename":"x","mime":"text/plain","size":1}"#.utf8)

        XCTAssertNil(AttachmentDescriptor.decode(json))
    }

    func testJSONWithWrongMarkerIsNotMisdetected() {
        let json = Data(#"{"chatapp":"message","v":1,"attachment_id":"att-123","file_key":"key","filename":"x","mime":"text/plain","size":1}"#.utf8)

        XCTAssertNil(AttachmentDescriptor.decode(json))
    }
}
