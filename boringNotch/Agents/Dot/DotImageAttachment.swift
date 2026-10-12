// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct DotImageAttachment: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let mimeType: String
    let data: Data
    let width: Int
    let height: Int

    var isValid: Bool {
        guard mimeType == "image/jpeg", !data.isEmpty, data.count <= DotChatLimits.imageBytes,
              (1...DotChatLimits.imageEdge).contains(width), (1...DotChatLimits.imageEdge).contains(height),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let actualWidth = properties[kCGImagePropertyPixelWidth] as? Int,
              let actualHeight = properties[kCGImagePropertyPixelHeight] as? Int else { return false }
        return actualWidth == width && actualHeight == height && CGImageSourceGetType(source) as String? == UTType.jpeg.identifier
    }

    static func validate(_ attachments: [DotImageAttachment]) throws {
        guard attachments.count <= DotChatLimits.imageCount else { throw DotChatError.tooManyImages }
        guard Set(attachments.map(\.id)).count == attachments.count,
              attachments.allSatisfy(\.isValid) else { throw DotChatError.invalidImage }
    }

    static func importData(_ data: Data) throws -> DotImageAttachment {
        guard data.count <= 20 * 1_048_576 else { throw DotChatError.imageTooLarge }
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0,
              let sourceType = CGImageSourceGetType(source),
              let type = UTType(sourceType as String),
              [UTType.png, .jpeg, .heic, .tiff, .webP].contains(where: { type.conforms(to: $0) }),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0,
                  [kCGImageSourceShouldCache: false] as CFDictionary) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 40_000_000 / height else { throw DotChatError.invalidImage }

        // ImageIO applies EXIF orientation while creating a bounded first-frame thumbnail.
        for edge in [1_600, 1_280, 1_024, 800, 640, 480, 320, 240] {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: edge,
                kCGImageSourceShouldCache: false
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { continue }
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
            guard let context = CGContext(data: nil, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { continue }
            context.setFillColor(NSColor.white.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            guard let flattened = context.makeImage() else { continue }
            for quality in [0.82, 0.68, 0.52, 0.38, 0.25] {
                let output = NSMutableData()
                guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { continue }
                CGImageDestinationAddImage(destination, flattened,
                    [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
                guard CGImageDestinationFinalize(destination) else { continue }
                let attachment = DotImageAttachment(id: UUID(), mimeType: "image/jpeg", data: output as Data,
                    width: image.width, height: image.height)
                if attachment.data.count <= DotChatLimits.imageBytes, attachment.isValid { return attachment }
            }
        }
        throw DotChatError.imageTooLarge
    }
}
