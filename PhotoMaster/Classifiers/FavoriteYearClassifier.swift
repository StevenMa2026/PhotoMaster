import Photos
import UIKit

class FavoriteYearClassifier: PhotoClassifiable {
    var albumName: String { "精华" }
    var exclusive: Bool { false }
    var supportedMediaTypes: Set<PHAssetMediaType> { [.image, .video] }
    var supportedAlbumTypes: [(type: PHAssetCollectionType, subtype: PHAssetCollectionSubtype)] {
        // 只扫描收藏相册
        return [(type: .smartAlbum, subtype: .smartAlbumFavorites)]
    }

    private let supportedYears = 2021...2026

    func matches(image: CGImage, asset: PHAsset) -> Bool {
        guard let creationDate = asset.creationDate else {
            return false
        }

        let year = Calendar.current.component(.year, from: creationDate)
        return supportedYears.contains(year)
    }   

    func albumName(for asset: PHAsset) -> String {
        guard let creationDate = asset.creationDate else {
            return albumName
        }
        let year = Calendar.current.component(.year, from: creationDate)
        return "精华\(year)"
    }
}
