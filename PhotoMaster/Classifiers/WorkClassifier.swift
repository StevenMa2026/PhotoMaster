import UIKit
import Photos

class WorkClassifier: PhotoClassifiable {
    var albumName: String { "工作" }
    var exclusive: Bool { true }
    var requiresHighResolution: Bool { true }

    private let keywords = [
        "sonarcube", "pipeline", "github", "eufiudwq", "confluence",
        "meet", "chat", "udw", "it/cn",
        "release", "java",
        "Shannon", "青年活动", "老登活动"
    ]

    // 办公室地理位置
    private let officeLocation = (latitude: 31.222032, longitude: 121.472938)
    private let locationThreshold: CLLocationDistance = 1000 // 1公里范围内

    func matches(image: CGImage, asset: PHAsset) -> Bool {
        let tag = "[💼 Work]"

        // 1. 检查是否在办公室附近（使用ImageUtil）
        let nearOffice = ImageUtil.isNearLocation(
            asset: asset,
            latitude: officeLocation.latitude,
            longitude: officeLocation.longitude,
            threshold: locationThreshold
        )
        #if DEBUG
        print("\(tag) 在办公室附近：\(nearOffice)")
        #endif
        
        // 如果在办公室附近，直接返回true，无需检测关键词
        if nearOffice {
            return true
        }
        
        // 2. 英文关键词检测（只有位置不满足时才执行）
        let hasText = ImageUtil.containsText(
            in: image,
            keywords: keywords,
            roi: CGRect(x: 0, y: 0, width: 1, height: 1),
            recognitionLanguages: ["en-US"],
            debugName: "Work-English",
            cacheKeyAsset: asset.localIdentifier
        )
        #if DEBUG
        print("\(tag) 匹配关键词：\(hasText)")
        #endif

        return hasText
    }
}