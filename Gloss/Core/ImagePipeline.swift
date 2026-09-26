import AppKit
import CryptoKit
import ImageIO

struct ProcessedImage {
    let jpeg: Data
    let sha256: String
    let pixelSize: CGSize
}

enum ImagePipeline {
    /// 等比缩放至长边 ≤ maxEdge 并压缩 JPEG（截图 1568 / PDF 页 2200 / 缩略 200——tech-design §6.1）。
    /// 纯 CoreGraphics 实现（CGContext + ImageIO），不依赖 NSGraphicsContext（无 WindowServer 会话的进程也可用）。
    static func normalize(_ image: NSImage, maxEdge: Int, quality: CGFloat = 0.85) -> ProcessedImage? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let w = cg.width, h = cg.height
        guard w > 0, h > 0 else { return nil }
        let scale = min(1.0, Double(maxEdge) / Double(max(w, h)))
        let tw = max(1, Int((Double(w) * scale).rounded()))
        let th = max(1, Int((Double(h) * scale).rounded()))
        let bytesPerRow = tw * 4
        var data = Data(count: bytesPerRow * th)
        let scaled: CGImage? = data.withUnsafeMutableBytes { raw -> CGImage? in
            guard let base = raw.baseAddress,
                  let ctx = CGContext(data: base, width: tw, height: th, bitsPerComponent: 8,
                                      bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            ctx.interpolationQuality = .high
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: tw, height: th))
            return ctx.makeImage()
        }
        guard let out = scaled else { return nil }
        let jpegData = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(jpegData, "public.jpeg" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, out, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        let jpeg = jpegData as Data
        let digest = SHA256.hash(data: jpeg).map { String(format: "%02x", $0) }.joined()
        return ProcessedImage(jpeg: jpeg, sha256: digest, pixelSize: CGSize(width: tw, height: th))
    }

    /// 历史记录缩略图（≤200px，原图不入库）
    static func thumbnailImage(_ image: NSImage, maxEdge: Int = 200) -> NSImage? {
        guard let p = normalize(image, maxEdge: maxEdge, quality: 0.8) else { return nil }
        return NSImage(data: p.jpeg)
    }
}

func glossSHA256(_ s: String) -> String {
    SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
}
