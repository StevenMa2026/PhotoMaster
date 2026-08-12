import UIKit
import Photos

class WeChatFavoriteClassifier: PhotoClassifiable {
    var albumName: String { "微信favorite截图" }
    var exclusive: Bool { true }
    var requiresHighResolution: Bool { true }
    var supportedAlbumTypes: [(type: PHAssetCollectionType, subtype: PHAssetCollectionSubtype)] {
        // 只检查截图相册
        return [(type: .smartAlbum, subtype: .smartAlbumScreenshots)]
    }
    
    private let keywords = [
        "老婆", "一家人", "爸妈", "马运昌", "邵润霞", "家人", "互动消息", "新关注我", "评论了你", "赞了你的", "NDFZ"
    ]
    
    func matches(image: CGImage, asset: PHAsset) -> Bool {
        let isVertical = image.height > image.width
        let hasTop = checkTopBar(cgImage: image, assetKey: asset.localIdentifier)
        return isVertical && hasTop
    }
}

extension WeChatFavoriteClassifier {
    private func checkTopBar(cgImage: CGImage, assetKey: String) -> Bool {
        let roi = CGRect(x: 0, y: 0.88, width: 1, height: 0.12)
        return ImageUtil.containsText(
            in: cgImage,
            keywords: keywords,
            roi: roi,
            debugName: "",
            cacheKeyAsset: assetKey
        )
    }
}
