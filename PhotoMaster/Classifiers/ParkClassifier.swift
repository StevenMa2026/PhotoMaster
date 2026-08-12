import Photos
import UIKit
import CoreML
import Vision

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
    
    /// 检测图像中是否包含宝宝（ML 模型只加载一次，避免每次都从磁盘重建）
    private static let mlModel: VNCoreMLModel? = {
        do {
            let model = try JunjunMLClassifier(configuration: MLModelConfiguration())
            return try VNCoreMLModel(for: model.model)
        } catch {
            print("[ParkClassifier] 模型加载失败: \(error)")
            return nil
        }
    }()

    private func detectBaby(image: CGImage) -> Bool {
        guard let mlModel = Self.mlModel else { return false }

        let request = VNCoreMLRequest(model: mlModel)
        request.imageCropAndScaleOption = .centerCrop

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
            guard let results = request.results as? [VNClassificationObservation],
                  let top = results.first else { return false }
            return top.identifier == "Junjun"
        } catch {
            print("[ParkClassifier] 模型预测失败: \(error)")
            return false
        }
    }
}
