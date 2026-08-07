import Vision
import UIKit
import Photos

class WangZheClassifier: PhotoClassifiable {
    var albumName: String { "王者荣耀" }
    var exclusive: Bool { true }
    var supportedMediaTypes: Set<PHAssetMediaType> { [.image] }
    // 只检查截图相册
    var supportedAlbumTypes: [(type: PHAssetCollectionType, subtype: PHAssetCollectionSubtype)] {
        return [(type: .smartAlbum, subtype: .smartAlbumScreenshots)]
    }
    
    private let keywords = [
        "王者", "荣耀", "王者荣耀", "击杀", "助攻", "回城", "技能",
        "装备", "打野", "中路", "对抗路", "发育路", "辅助", "暴君",
        "主宰", "水晶", "防御塔", "五杀", "超神", "MVP", "战绩",
        "排位", "匹配", "巅峰赛", "王者营地", "KPL", "英雄", "皮肤",
        "星耀", "钻石", "铂金", "灵宝", "星元"
    ]

    func matches(image: CGImage, asset: PHAsset) -> Bool {
        ImageUtil.isHorizontalScreenshot(image: image, asset: asset)
        && ImageUtil.containsText(
            in: image,
            keywords: keywords,
            debugName: albumName,
            cacheKeyAsset: asset.localIdentifier
        )
    }
}
