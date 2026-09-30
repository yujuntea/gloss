import CoreGraphics
import Foundation

/// 图片 fit 满矩形后的点击坐标换算（视图局部坐标，y 向下）。
/// 缩略图与图片放大窗共用同一算法（§4.4）——两处调用方都不得引入 ScrollView / 缩放，
/// 否则公式须叠加滚动偏移与缩放因子。
enum ImageGeometry {
    /// 图片以 `scaledToFit` 铺进 `container` 后实际占据的矩形（居中，两侧/上下留 letterbox 空白）。
    ///
    /// 归一化换算、放大窗绘制（`ZoomImageNSView.draw`）、准星反解三处必须用**同一个**公式——
    /// 任何一处另写一份都会在缩放比例或居中偏移上静默漂移，故收口于此。
    static func fitRect(imageSize: CGSize, container: CGSize) -> CGRect {
        let iw = max(imageSize.width, 1)
        let ih = max(imageSize.height, 1)
        let s = min(container.width / iw, container.height / ih)
        let dw = iw * s, dh = ih * s
        return CGRect(x: (container.width - dw) / 2, y: (container.height - dh) / 2, width: dw, height: dh)
    }

    /// 点击落在 fit 后的图片之外（letterbox 空白）时返回 nil，与原内联实现的 0…1 守卫一致
    static func normalizedPoint(viewSize: CGSize, imagePixelSize: CGSize, click: CGPoint) -> CGPoint? {
        let r = fitRect(imageSize: imagePixelSize, container: viewSize)
        let nx = (click.x - r.origin.x) / max(r.width, 1)
        let ny = (click.y - r.origin.y) / max(r.height, 1)
        guard nx >= 0, nx <= 1, ny >= 0, ny <= 1 else { return nil }
        return CGPoint(x: nx, y: ny)
    }

    /// 缩略图点击分流（§4.5）：原图自然宽超过卡片**实际可用宽**时，卡内正文小到不可读，
    /// 改为打开图片放大窗；否则保留卡片内就地点词。
    ///
    /// 卡宽传**实测**的 `geo.size.width` 而非写死 376：当前 `ResultPanelView` 有 `.frame(width: 400)`
    /// 把内容宽钉死，实测值恒为 376，两种写法结果相同；按实测值判定是为面板将来可调宽时不必回来改这里。
    static func needsZoomWindow(imageWidth: CGFloat, cardWidth: CGFloat) -> Bool {
        imageWidth > cardWidth
    }
}
