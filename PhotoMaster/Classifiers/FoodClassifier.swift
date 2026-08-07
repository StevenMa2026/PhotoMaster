import Vision
import UIKit
import Photos

class FoodClassifier: PhotoClassifiable {
    var albumName: String { "食物" }
    var exclusive: Bool { true }
    var supportedMediaTypes: Set<PHAssetMediaType> { [.image] }

    func matches(image: CGImage, asset: PHAsset) -> Bool {
        let tag = "[🍎 \(albumName)]"
        
        // 1. 不是截图
        let isScreenShot = ImageUtil.isScreenshot(asset: asset)
        #if DEBUG
        print("\(tag) 是否是手机截图：\(isScreenShot)")
        #endif
        
        guard !isScreenShot else {
            #if DEBUG
            print("\(tag) 原因：是截图，跳过")
            #endif
            return false
        }
        
        // 2. 地点在家
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
        
        // 3. 利用苹果的图片分类判断是否是食物
        let isFood = isFoodImage(image)
        #if DEBUG
        print("\(tag) 识别为食物：\(isFood)")
        #endif
        
        guard isFood else {
            #if DEBUG
            print("\(tag) 原因：不是食物，跳过")
            #endif
            return false
        }
        
        // 全部满足
        #if DEBUG
        print("\(tag) ✅ 全部满足，判定为食物")
        #endif
        return true
    }
    
    private func isFoodImage(_ image: CGImage) -> Bool {
        let tag = "[🍎 \(albumName)]"
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
            
            // 打印前5个识别结果，方便看系统识别成了啥
            let top5 = results.prefix(5).map {
                String(format: "%.2f %@", $0.confidence, $0.identifier)
            }
            #if DEBUG
            print("\(tag) 图像分类Top5：\(top5)")
            #endif
            
            let identifiers = results.prefix(15)
                .compactMap { $0.identifier.lowercased() }
                .joined()
            
            // 检查是否包含食物相关的分类
            let foodKeywords = ["food", "meal", "dish", "cuisine", "recipe", "restaurant", "dining", "cooking", "kitchen", "plate", "bowl", "fork", "knife", "spoon", "chopsticks", "sushi", "pizza", "burger", "fries", "salad", "soup", "dessert", "cake", "ice cream", "fruit", "vegetable", "meat", "fish", "chicken", "beef", "pork", "rice", "noodle", "bread", "coffee", "tea", "drink", "juice", "water", "milk", "beer", "wine", "cocktail"]
            
            for keyword in foodKeywords {
                if identifiers.contains(keyword) {
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