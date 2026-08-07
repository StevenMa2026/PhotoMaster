import Photos
import UIKit
import CoreML

class ParkClassifier: PhotoClassifiable {
    var albumName: String { "公园" }
    var exclusive: Bool { true }
    var supportedMediaTypes: Set<PHAssetMediaType> { [.image, .video] }
    
    // 目标地点
    private let targetLocation = "上海"
    
    func matches(image: CGImage, asset: PHAsset) -> Bool {
    #if DEBUG
        let fileName = asset.value(forKey: "filename") as? String ?? "无文件名"
        print("""
        [\(fileName)]
        """)
        #endif
        // 打印地点信息
        ImageUtil.printLocationInfo(asset: asset)
        
        // 检查是否是截图
        if ImageUtil.isScreenshot(asset: asset) {
            return false
        }
        
        // 检查是否包含宝宝
        let hasBaby = detectBaby(image: image)
        if !hasBaby {
            return false
        }
        
        // 检查地点是否在上海但不是在家
        let isInShanghai = ImageUtil.isLocationInShanghai(asset: asset)
        let isAtHome = ImageUtil.isLocationAtHome(asset: asset)
        return isInShanghai && !isAtHome
    }
    
    func albumName(for asset: PHAsset) -> String {
        albumName
    }
    
    /// 检测图像中是否包含宝宝
    /// - Parameter image: 要检测的图像
    /// - Returns: 是否包含宝宝
    private func detectBaby(image: CGImage) -> Bool {
        do {
            // 加载ML模型
            let model = try JunjunMLClassifier(configuration: MLModelConfiguration())
            
            // 将CGImage转换为CVPixelBuffer
            guard let pixelBuffer = image.toCVPixelBuffer() else {
                return false
            }
            
            // 预测
            let prediction = try model.prediction(image: pixelBuffer)
            
            // 返回预测结果：如果classLabel是"Junjun"，则认为包含宝宝
            return prediction.classLabel == "Junjun"
        } catch {
            print("[ParkClassifier] 模型预测失败: \(error)")
            return false
        }
    }
}

// 扩展CGImage以支持转换为CVPixelBuffer
extension CGImage {
    func toCVPixelBuffer() -> CVPixelBuffer? {
        let width = self.width
        let height = self.height
        
        let attrs = [kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
                     kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue] as CFDictionary
        
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                         width,
                                         height,
                                         kCVPixelFormatType_32ARGB,
                                         attrs,
                                         &pixelBuffer)
        
        guard status == kCVReturnSuccess, let pb = pixelBuffer else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(pb, CVPixelBufferLockFlags(rawValue: 0))
        let pixelData = CVPixelBufferGetBaseAddress(pb)
        
        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: pixelData,
                                width: width,
                                height: height,
                                bitsPerComponent: 8,
                                bytesPerRow: CVPixelBufferGetBytesPerRow(pb),
                                space: rgbColorSpace,
                                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)
        
        context?.draw(self, in: CGRect(x: 0, y: 0, width: width, height: height))
        CVPixelBufferUnlockBaseAddress(pb, CVPixelBufferLockFlags(rawValue: 0))
        
        return pb
    }
}
