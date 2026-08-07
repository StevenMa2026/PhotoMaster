import Vision
import UIKit
import Photos

class PetClassifier: PhotoClassifiable {
    var albumName: String { "宠物" }
    var exclusive: Bool { true }
    var supportedMediaTypes: Set<PHAssetMediaType> { [.image] }
    
    func matches(image: CGImage, asset: PHAsset) -> Bool {
        let tag = "[🐾 \(albumName)]"
        
        // 1. 检查位置是否在家
        let isAtHome = ImageUtil.isLocationAtHome(asset: asset)
        #if DEBUG
        print("\(tag) 是否在家：\(isAtHome)")
        #endif
        
        guard isAtHome else {
            #if DEBUG
            print("\(tag) 原因：不在家，跳过")
            #endif
            return false
        }
        
        // 2. 使用 Vision 图像分类判断是否是宠物相关图片
        let isPet = isPetImage(image)
        #if DEBUG
        print("\(tag) 识别为宠物：\(isPet)")
        #endif
        
        guard isPet else {
            #if DEBUG
            print("\(tag) 原因：不是宠物，跳过")
            #endif
            return false
        }
        
        #if DEBUG
        print("\(tag) ✅ 全部满足，判定为宠物")
        #endif
        return true
    }
    
    /// 使用 Vision 图像分类判断是否是宠物相关图片
    private func isPetImage(_ image: CGImage) -> Bool {
        let tag = "[🐾 \(albumName)]"
        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
        
        do {
            try handler.perform([request])
            guard let results = request.results else {
                #if DEBUG
                print("\(tag) 无分类结果")
                #endif
                return false
            }
            
            // 打印前5个识别结果，方便调试
            let top5 = results.prefix(5).map {
                String(format: "%.2f %@", $0.confidence, $0.identifier)
            }
            #if DEBUG
            print("\(tag) 图像分类Top5：\(top5)")
            #endif
            
            // 检查前15个分类结果
            let identifiers = results.prefix(15)
                .compactMap { $0.identifier.lowercased() }
                .joined()
            
            // 宠物相关的关键词
            let petKeywords = [
                // 猫
                "cat", "cats",
                // 笼子
                "cage", "birdcage", "pet cage", "animal cage",
                // 鱼缸
                "aquarium", "fish tank", "fishbowl", "goldfish", "fish",
                // 仓鼠
                "hamster", "hamsters"
            ]
            
            for keyword in petKeywords {
                if identifiers.contains(keyword) {
                    #if DEBUG
                    print("\(tag) 匹配到关键词: \(keyword)")
                    #endif
                    return true
                }
            }
            
            return false
        } catch {
            #if DEBUG
            print("\(tag) Vision 分类失败: \(error)")
            #endif
            return false
        }
    }
    
    func albumName(for asset: PHAsset) -> String {
        return albumName
    }
}