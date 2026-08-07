import UIKit
import Photos

class ShangDeClassifier: PhotoClassifiable {
    var albumName: String { "尚德坤庭幼儿园" }
    var exclusive: Bool { true }
    var supportedMediaTypes: Set<PHAssetMediaType> { [.image, .video] }
    
    // 尚德幼儿园地理位置
    private let kindergartenLocation = (latitude: 31.094952833333334, longitude: 121.48799166666667)
    private let locationThreshold: CLLocationDistance = 200 // 200米范围内

    func matches(image: CGImage, asset: PHAsset) -> Bool {
        let tag = "[🏫 尚德]"
        let creationDate = asset.creationDate ?? Date()

        // 检查是否是节假日（考虑调休补班）
        let isHoliday = DateUtil.isHoliday(date: creationDate)
        
        #if DEBUG
        print("\(tag) 是否节假日：\(isHoliday)")
        #endif
        
        // 如果是节假日，直接返回 false
        if isHoliday {
            return false
        }

        // 检查是否在幼儿园附近
        let nearKindergarten = ImageUtil.isNearLocation(
            asset: asset,
            latitude: kindergartenLocation.latitude,
            longitude: kindergartenLocation.longitude,
            threshold: locationThreshold
        )
        #if DEBUG
        print("\(tag) 在幼儿园附近：\(nearKindergarten)")
        #endif

        return nearKindergarten
    }
}