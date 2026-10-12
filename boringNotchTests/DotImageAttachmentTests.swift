// SPDX-License-Identifier: GPL-3.0-only
import XCTest
import AppKit
import ImageIO
import UniformTypeIdentifiers
@testable import boringNotch

final class DotImageAttachmentTests: XCTestCase {
    private func png(width: Int, height: Int) throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.systemBlue.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyPNGDictionary: [kCGImagePropertyPNGDescription: "private metadata marker"]] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }

    func testImportDownsamplesFlattensAndStripsMetadata() throws {
        let source = try png(width: 2_000, height: 1_000)
        XCTAssertNotNil(source.range(of: Data("private metadata marker".utf8)))
        let attachment = try DotImageAttachment.importData(source)
        XCTAssertEqual(attachment.mimeType, "image/jpeg")
        XCTAssertLessThanOrEqual(max(attachment.width, attachment.height), 1_600)
        XCTAssertLessThanOrEqual(attachment.data.count, DotChatLimits.imageBytes)
        XCTAssertTrue(attachment.isValid)
        XCTAssertNil(attachment.data.range(of: Data("private metadata marker".utf8)))
        let encoded = try JSONEncoder().encode(attachment)
        XCTAssertEqual(try JSONDecoder().decode(DotImageAttachment.self, from: encoded), attachment)
    }

    func testRejectsOversizedOrUnsupportedInputAndTamperedDimensions() throws {
        XCTAssertThrowsError(try DotImageAttachment.importData(Data(repeating: 0, count: 20 * 1_048_576 + 1)))
        XCTAssertThrowsError(try DotImageAttachment.importData(Data("not an image".utf8)))
        let attachment = try DotImageAttachment.importData(png(width: 32, height: 32))
        let forged = DotImageAttachment(id: attachment.id, mimeType: attachment.mimeType,
            data: attachment.data, width: 31, height: 32)
        XCTAssertFalse(forged.isValid)
        XCTAssertThrowsError(try DotImageAttachment.validate([forged]))
        XCTAssertThrowsError(try DotImageAttachment.validate(Array(repeating: attachment, count: 5)))
    }

    func testOldArchiveWithoutAttachmentKeysDecodesEmpty() throws {
        let id = UUID(), now = Date()
        let legacy = DotChatArchive(messages: [DotChatMessage(id: id, role: .user, text: "legacy", createdAt: now)])
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any])
        object.removeValue(forKey: "draftAttachments")
        var messages = try XCTUnwrap(object["messages"] as? [[String: Any]])
        messages[0].removeValue(forKey: "attachments")
        object["messages"] = messages
        let bytes = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(DotChatArchive.self, from: bytes)
        XCTAssertTrue(decoded.draftAttachments.isEmpty)
        XCTAssertTrue(decoded.messages[0].attachments.isEmpty)
    }
}
