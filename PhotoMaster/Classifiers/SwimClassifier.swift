import UIKit
import Photos

class SwimClassifier: PhotoClassifiable {
    var albumName: String { "游泳课" }
    var exclusive: Bool { true }
    var supportedMediaTypes: Set<PHAssetMediaType> { [.image, .video] }

    // 游泳馆地理位置
    private let poolLocation = (latitude: 31.0954055, longitude: 121.48802166666667)
    private let locationThreshold: CLLocationDistance = 100 // 100米范围内

    func matches(image: CGImage, asset: PHAsset) -> Bool {
        let tag = "[🏊 游泳课]"
        let creationDate = asset.creationDate ?? Date()

        // 1. 只要节假日
        let isHoliday = DateUtil.isHoliday(date: creationDate)
        #if DEBUG
        print("\(tag) 是否节假日：\(isHoliday)")
        #endif
        if !isHoliday {
            return false
        }

        // 2. 检查是否是截图
        let isScreenshot = ImageUtil.isScreenshot(asset: asset)
        #if DEBUG
        print("\(tag) 是否截图：\(isScreenshot)")
        #endif
        if isScreenshot {
            return false
        }

        // 3. 检查是否在游泳馆附近
        let nearPool = ImageUtil.isNearLocation(
            asset: asset,
            latitude: poolLocation.latitude,
            longitude: poolLocation.longitude,
            threshold: locationThreshold
        )
        #if DEBUG
        print("\(tag) 在游泳馆附近：\(nearPool)")
        #endif

        return nearPool
    }
}