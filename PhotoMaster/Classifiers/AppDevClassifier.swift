import Vision
import UIKit
import Photos

class AppDevClassifier: PhotoClassifiable {
    var albumName: String { "app开发" }
    var exclusive: Bool { true }
    var requiresHighResolution: Bool { true }
    
    private let keywords = [
        "智能相册归类", "开始自动归类", "MacBook", "TRAE", "Xcode", "PhotoMaster"
    ]

    func matches(image: CGImage, asset: PHAsset) -> Bool {
        let tag = "[💻 \(albumName)]"
        
        // 检查是否包含关键词
        let hasKeyword = ImageUtil.containsText(
            in: image,
            keywords: keywords,
            debugName: albumName,
            cacheKeyAsset: asset.localIdentifier
        )
        #if DEBUG
        print("\(tag) 包含开发关键词：\(hasKeyword)")
        #endif
        
        guard hasKeyword else {
            #if DEBUG
            print("\(tag) 原因：未匹配到关键词")
            #endif
            return false
        }
        
        // 全部满足
        #if DEBUG
        print("\(tag) ✅ 全部满足，判定为开发相关")
        #endif
        return true
    }
    
    func albumName(for asset: PHAsset) -> String {
        return albumName
    }
}