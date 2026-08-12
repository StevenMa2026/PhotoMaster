import Vision
import UIKit
import Photos

class TvMovieClassifier: PhotoClassifiable {
    var albumName: String { "经典电视电影综艺画面" }
    var exclusive: Bool { true }
    var requiresHighResolution: Bool { true }
    
    private let keywords = [
        "电视", "卫视", "电视台", "CCTV", "综艺", "节目", "央视频",
        "电影", "影院", "观影", "电视剧", "剧集", "追剧", "剧",
        "频道", "极光", "TV", "云视听", "云视", "视听",
        "裴", "林晚", "辛特", "豆包姐", "好看", "帅",
        "项羽", "何润东",
        "梅西", "C罗", "大罗", "罗纳尔多", "内马尔", "足球", "世界杯", "欧冠",
        "善语结善缘", "恶言伤人心", "老五", "三明", "四哥", "老四", "熊九东", "东哥","", "关注", "Follow", "分享给",
        "免费观看"
    ]

    func matches(image: CGImage, asset: PHAsset) -> Bool {
        let tag = "[🎬 \(albumName)]"
        
        // 检查是否包含关键词
        let hasKeyword = ImageUtil.containsText(
            in: image,
            keywords: keywords,
            debugName: albumName,
            cacheKeyAsset: asset.localIdentifier
        )
        #if DEBUG
        print("\(tag) 包含影视关键词：\(hasKeyword)")
        #endif
        
        guard hasKeyword else {
            #if DEBUG
            print("\(tag) 原因：未匹配到关键词")
            #endif
            return false
        }
        
        // 全部满足
        #if DEBUG
        print("\(tag) ✅ 全部满足，判定为影视截图")
        #endif
        return true
    }
    

}
