import UIKit
import Vision
import Photos
import CoreLocation

struct ImageUtil {
    private static let ocrTextCache: NSCache<NSString, NSString> = {
        let cache = NSCache<NSString, NSString>()
        cache.countLimit = 2000
        return cache
    }()
    
    // 位置判断缓存
    private static let locationCache: NSCache<NSString, NSNumber> = {
        let cache = NSCache<NSString, NSNumber>()
        cache.countLimit = 5000
        return cache
    }()

    private static func cacheKey(
        assetKey: String,
        image: CGImage,
        roi: CGRect,
        recognitionLanguages: [String]
    ) -> String {
        let roiPart = "\(roi.origin.x),\(roi.origin.y),\(roi.size.width),\(roi.size.height)"
        let langPart = recognitionLanguages.joined(separator: ",")
        return "\(assetKey)|\(image.width)x\(image.height)|\(roiPart)|\(langPart)"
    }

    private static func recognizedText(
        in image: CGImage,
        roi: CGRect,
        recognitionLanguages: [String],
        recognitionLevel: VNRequestTextRecognitionLevel,
        cacheKeyAsset: String?
    ) -> String {
        if let cacheKeyAsset {
            let key = cacheKey(
                assetKey: cacheKeyAsset,
                image: image,
                roi: roi,
                recognitionLanguages: recognitionLanguages
            ) as NSString
            if let cached = ocrTextCache.object(forKey: key) {
                return String(cached)
            }
        }

        let sema = DispatchSemaphore(value: 0)
        var recognized = ""

        let request = VNRecognizeTextRequest { req, _ in
            defer { sema.signal() }

            recognized = req.results?
                .compactMap { $0 as? VNRecognizedTextObservation }
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: " ")
                .lowercased() ?? ""
        }

        request.regionOfInterest = roi
        request.recognitionLevel = recognitionLevel
        request.recognitionLanguages = recognitionLanguages
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.002

        try? VNImageRequestHandler(cgImage: image).perform([request])
        sema.wait()

        if let cacheKeyAsset {
            let key = cacheKey(
                assetKey: cacheKeyAsset,
                image: image,
                roi: roi,
                recognitionLanguages: recognitionLanguages
            ) as NSString
            ocrTextCache.setObject(recognized as NSString, forKey: key)
        }

        return recognized
    }

    // MARK: - 指定 ROI 区域文字检测（支持自定义语言）
    static func containsText(
        in image: CGImage,
        keywords: [String],
        roi: CGRect,
        recognitionLanguages: [String] = ["zh-CN", "en-US"],
        recognitionLevel: VNRequestTextRecognitionLevel = .accurate,
        debugName: String,
        cacheKeyAsset: String? = nil
    ) -> Bool {
        let text = recognizedText(
            in: image,
            roi: roi,
            recognitionLanguages: recognitionLanguages,
            recognitionLevel: recognitionLevel,
            cacheKeyAsset: cacheKeyAsset
        )

        #if DEBUG
        //  print("[\(debugName)] 检测出的文字: \(text)")
        #endif

        if keywords.isEmpty {
            return !text.isEmpty
        }

        let matchedKeywords = keywords.filter { keyword in
            text.contains(keyword.lowercased())
        }

        #if DEBUG
        if !matchedKeywords.isEmpty {
            print("[\(debugName)] 匹配的关键词: \(matchedKeywords.joined(separator: ", "))")
        }
        #endif

        return !matchedKeywords.isEmpty
    }

    // MARK: - 全图版本（兼容旧调用）
    static func containsText(
        in image: CGImage,
        keywords: [String],
        roi: CGRect,
        debugName: String,
        cacheKeyAsset: String? = nil
    ) -> Bool {
        // 走新版，用默认语言
        containsText(
            in: image,
            keywords: keywords,
            roi: roi,
            recognitionLanguages: ["zh-CN", "en-US"],
            recognitionLevel: .accurate,
            debugName: debugName,
            cacheKeyAsset: cacheKeyAsset
        )
    }

    // MARK: - 最旧版全图（兼容更早代码）
    static func containsText(
        in image: CGImage,
        keywords: [String],
        debugName: String,
        cacheKeyAsset: String? = nil
    ) -> Bool {
        containsText(
            in: image,
            keywords: keywords,
            roi: CGRect(x: 0, y: 0, width: 1, height: 1),
            recognitionLevel: .accurate,
            debugName: debugName,
            cacheKeyAsset: cacheKeyAsset
        )
    }

    // MARK: - 指定语言的全图版本
    static func containsText(
        in image: CGImage,
        keywords: [String],
        debugName: String,
        cacheKeyAsset: String? = nil,
        recognitionLanguages: [String]
    ) -> Bool {
        containsText(
            in: image,
            keywords: keywords,
            roi: CGRect(x: 0, y: 0, width: 1, height: 1),
            recognitionLanguages: recognitionLanguages,
            recognitionLevel: .accurate,
            debugName: debugName,
            cacheKeyAsset: cacheKeyAsset
        )
    }

    // MARK: - 截图判断
    static func isScreenshot(asset: PHAsset) -> Bool {
        let isScreen = asset.mediaSubtypes.contains(.photoScreenshot)
        return isScreen
    }

    static func isVerticalScreenshot(image: CGImage, asset: PHAsset) -> Bool {
        let isScreen = isScreenshot(asset: asset)
        let isVertical = image.height > image.width
        #if DEBUG
        print("[竖屏截图] isScreenshot=\(isScreen), 高>宽=\(isVertical)")
        #endif
        return isScreen && isVertical
    }

    static func isHorizontalScreenshot(image: CGImage, asset: PHAsset) -> Bool {
        let isScreen = isScreenshot(asset: asset)
        let isHorizontal = image.width > image.height
        #if DEBUG
        print("[横屏截图] isScreenshot=\(isScreen), 宽>高=\(isHorizontal)")
        #endif
        return isScreen && isHorizontal
    }
    
    // MARK: - 位置判断
    static func isLocationInShanghai(asset: PHAsset) -> Bool {
        guard let location = asset.location else {
            return false
        }
        
        let latitude = location.coordinate.latitude
        let longitude = location.coordinate.longitude
        
        // 上海坐标范围
        let isInShanghai = latitude >= 30.7 && latitude <= 31.5 &&
                           longitude >= 120.8 && longitude <= 122.0
        
        #if DEBUG
        print("[上海位置判断] 纬度: \(latitude), 经度: \(longitude), 结果: \(isInShanghai)")
        #endif
        
        return isInShanghai
    }
    
    // MARK: - 获取和打印地点信息
    static func printLocationInfo(asset: PHAsset) {
        guard let location = asset.location else {
            print("[位置信息] 无位置信息")
            return
        }
        
        let latitude = location.coordinate.latitude
        let longitude = location.coordinate.longitude
        print("[位置信息] 纬度: \(latitude), 经度: \(longitude)")
        
        // 这里可以使用反向地理编码来获取地点名称
        // 简单起见，我们暂时只打印坐标，实际应用中需要实现地理编码
    }
    
    // MARK: - 检查地点是否在家
    static func isLocationAtHome(asset: PHAsset) -> Bool {
        // 家的坐标：纬度: 31.092288833333335, 经度: 121.48850333333333
        let homeLatitude = 31.092288833333335
        let homeLongitude = 121.48850333333333
        
        // 使用统一的位置检测方法（100米范围）
        return isNearLocation(
            asset: asset,
            latitude: homeLatitude,
            longitude: homeLongitude,
            threshold: 100
        )
    }
    
    // 判断照片是否在指定位置附近
    static func isNearLocation(asset: PHAsset, latitude: CLLocationDegrees, longitude: CLLocationDegrees, threshold: CLLocationDistance = 1000) -> Bool {
        // 构建缓存key
        let cacheKey = "\(asset.localIdentifier)|\(latitude)|\(longitude)|\(threshold)" as NSString
        
        // 检查缓存
        if let cached = locationCache.object(forKey: cacheKey) {
            return cached.boolValue
        }
        
        guard let location = asset.location else {
            // 无位置信息，缓存结果
            locationCache.setObject(false as NSNumber, forKey: cacheKey)
            return false
        }
        
        let targetLocation = CLLocation(latitude: latitude, longitude: longitude)
        let distance = location.distance(from: targetLocation)
        let result = distance <= threshold
        
        #if DEBUG
        print("[位置判断] 距离: \(distance)米, 阈值: \(threshold)米, 结果: \(result)")
        #endif
        
        // 缓存结果
        locationCache.setObject(result as NSNumber, forKey: cacheKey)
        
        return result
    }
}
