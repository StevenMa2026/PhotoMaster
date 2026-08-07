import Vision
import UIKit
import Photos

class FinanceClassifier: PhotoClassifiable {
    var albumName: String { "投资" }
    var exclusive: Bool { true }
    var supportedAlbumTypes: [(type: PHAssetCollectionType, subtype: PHAssetCollectionSubtype)] {
        // 只检查截图相册
        return [(type: .smartAlbum, subtype: .smartAlbumScreenshots)]
    }
    var supportedAlbumNames: Set<String> {
        // 只检查微信相册
        return ["微信"]
    }

    private let keywords = [
        "股票", "基金", "持仓", "盈亏", "收益率", "净值",
        "买入", "卖出", "加仓", "减仓", "止盈", "止损",
        "上证指数", "深证成指", "创业板指", "资产", "市值",
        "etf", "定投", "混合", "联接", "理财", "证券", "收益", "亏损",
        "分时", "日K", "周K", "股市", "选股",
        "恐贪", "立减", "积分余额", "人民法院",
        "stock", "fund", "portfolio", "数字藏品", "诊股", "研报",
        "自选", "返现", "分红", "大橙子", "大登子",
        "跨年群", "橙心", "未来云启", "老歪", "慢涨"
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
}
