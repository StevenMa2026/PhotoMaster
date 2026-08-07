import UIKit
import Photos

class SelfieClassifier: PhotoClassifiable {
    var albumName: String { "自拍" }
    var exclusive: Bool { true }
    var supportedMediaTypes: Set<PHAssetMediaType> { [.image] }
    // 使用iOS自带的自拍相册检测
    var supportedAlbumTypes: [(type: PHAssetCollectionType, subtype: PHAssetCollectionSubtype)] {
        [(.smartAlbum, .smartAlbumSelfPortraits)]
    }
    
    func matches(image: CGImage, asset: PHAsset) -> Bool {
        // 使用系统自带的自拍相册，不需要额外检测
        return true
    }
    
    func albumName(for asset: PHAsset) -> String {
        return albumName
    }
}