import Vision
import Photos

class PS5ProGameClassifier: PhotoClassifiable {
    var albumName: String { "PS5 Pro游戏" }
    var exclusive: Bool { true }
    var supportedMediaTypes: Set<PHAssetMediaType> { [.image] }
    // 只检查截图相册
    var supportedAlbumTypes: [(type: PHAssetCollectionType, subtype: PHAssetCollectionSubtype)] {
        return [(type: .smartAlbum, subtype: .smartAlbumScreenshots)]
    }
    
    private let keywords = [
        "最近游玩", "奖杯", "游戏帮助", "心愿单", "追加内容", "珍贵", "提示", "已隐藏",
        "PlayStation", "PS4", "PS5",
        "美末", "最后生还者", "最后的生还者", "卧龙", "黑悟空", "黑神话", "仁王",
        "对马岛", "异闻录", "影之刃", "明末", "只狼", "底特律变人", "爱丽丝", "仿生人", "P5R"
    ]
    
    func matches(image: CGImage, asset: PHAsset) -> Bool {
        // 判断关键词
        let hasKeyword = ImageUtil.containsText(
            in: image,
            keywords: keywords,
            debugName: albumName,
            cacheKeyAsset: asset.localIdentifier
        )
        
        return hasKeyword
    }
    
    func albumName(for asset: PHAsset) -> String {
        return albumName
    }
}
