import AVFoundation
import UIKit

/// Draws a window of the script (past words dimmed, current word highlighted)
/// into a video frame that the Picture-in-Picture layer can display.
enum PipFrameRenderer {

    static func makeFrame(words: [String], position: Int, size: CGSize,
                          timestamp: CMTime? = nil) -> CMSampleBuffer? {
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())
        guard width > 0, height > 0 else { return nil }

        guard let pixelBuffer = makePixelBuffer(width: width, height: height) else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        context.setFillColor(UIColor.black.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Flip into UIKit's coordinate space and draw the text.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(context)
        draw(words: words, position: position, in: CGRect(x: 0, y: 0, width: width, height: height))
        UIGraphicsPopContext()

        return makeSampleBuffer(from: pixelBuffer, timestamp: timestamp)
    }

    private static func draw(words: [String], position: Int, in bounds: CGRect) {
        let fontSize = bounds.height / 10.0
        let font = UIFont.systemFont(ofSize: fontSize, weight: .bold)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = fontSize * 0.16

        // Show a couple of words behind the reader and plenty ahead.
        let start = max(0, min(position, words.count) - 2)
        let end = min(words.count, start + 90)
        guard start < end else { return }

        let text = NSMutableAttributedString()
        for i in start..<end {
            let color: UIColor =
                i < position ? UIColor.white.withAlphaComponent(0.35) :
                i == position ? .systemYellow : .white
            text.append(NSAttributedString(
                string: (i > start ? " " : "") + words[i],
                attributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
            ))
        }
        text.draw(with: bounds.insetBy(dx: bounds.width * 0.05, dy: bounds.height * 0.06),
                  options: [.usesLineFragmentOrigin, .usesFontLeading],
                  context: nil)
    }

    private static func makePixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary
        ]
        CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                            kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pixelBuffer)
        return pixelBuffer
    }

    private static func makeSampleBuffer(from pixelBuffer: CVPixelBuffer, timestamp: CMTime?) -> CMSampleBuffer? {
        var formatDescription: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
                                                     imageBuffer: pixelBuffer,
                                                     formatDescriptionOut: &formatDescription)
        guard let formatDescription else { return nil }

        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: timestamp ?? CMClockGetTime(CMClockGetHostTimeClock()),
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault,
                                                 imageBuffer: pixelBuffer,
                                                 formatDescription: formatDescription,
                                                 sampleTiming: &timing,
                                                 sampleBufferOut: &sampleBuffer)
        guard let sampleBuffer else { return nil }

        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dict,
                                 Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        return sampleBuffer
    }
}
