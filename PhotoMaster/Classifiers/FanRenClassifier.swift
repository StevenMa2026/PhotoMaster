import UIKit
import Vision
import Photos



class FanRenClassifier: PhotoClassifiable {
    var albumName: String { "凡人修仙传" }
    var exclusive: Bool { true }
    var requiresHighResolution: Bool { true }
    
    func matches(image: CGImage, asset: PHAsset) -> Bool {
        let isHorizontal = image.width > image.height
        
        // 首先检查是否是横向图片
        guard isHorizontal else {
            return false
        }
        
        // 按顺序检查，前面满足了就直接返回
        // 1. 检查左下角水印
        if checkBottomLeftWatermark(cgImage: image, assetKey: asset.localIdentifier) {
            return true
        }
        
        // 2. 检查右上角水印
        if checkTopRightWatermark(cgImage: image, assetKey: asset.localIdentifier) {
            return true
        }
        
        // 3. 检查弹幕
        if checkDanmuInTopRegion(cgImage: image, assetKey: asset.localIdentifier) {
            return true
        }
        
        // 都不满足
        return false
    }
}

// MARK: - 核心 OCR 统一用 ImageUtil
extension FanRenClassifier {
    
    // 左下角 B 站水印
    private func checkBottomLeftWatermark(cgImage: CGImage, assetKey: String) -> Bool {
        let roi = CGRect(x: 0, y: 0, width: 0.55, height: 0.22)
        let keywords = ["bilibili", "哔哩哔哩", "bv", "独播", "bil", "bii", "bli"]
        
        return ImageUtil.containsText(
            in: cgImage,
            keywords: keywords,
            roi: roi,
            debugName: "左下角水印",
            cacheKeyAsset: assetKey
        )
    }

    // 右上角 B 站水印
    private func checkTopRightWatermark(cgImage: CGImage, assetKey: String) -> Bool {
        let roi = CGRect(x: 0.72, y: 0.78, width: 0.28, height: 0.22)
        let keywords = ["bilibili", "哔哩哔哩", "独播", "bil", "bii", "bli"]

        return ImageUtil.containsText(
            in: cgImage,
            keywords: keywords,
            roi: roi,
            debugName: "右上角水印",
            cacheKeyAsset: assetKey
        )
    }
    
    // 上方 30% 有文字就算弹幕
    private func checkDanmuInTopRegion(cgImage: CGImage, assetKey: String) -> Bool {
        let roi = CGRect(x: 0, y: 0.7, width: 1, height: 0.3)
        let fanRenKeywords = ["凡人", "修仙", "韩立", "劳模", "派克", "蛮胡子", "极阴岛",
        "可爱", "南宫婉", "玄骨", "墨彩环", "黄枫谷", "灵根", "筑基", "结丹", "元婴",
        "恐怖如斯", "神仙打架", "bil", "bii", "bli", "进度条", "泪目"]
        
        return ImageUtil.containsText(
            in: cgImage,
            keywords: fanRenKeywords,
            roi: roi,
            recognitionLanguages: ["zh-CN"],
            debugName: "上方弹幕",
            cacheKeyAsset: assetKey
        )
    }
}
