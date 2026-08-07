import Vision
import UIKit
import Photos

class AppScreenshotsClassifier: PhotoClassifiable {
    var albumName: String { "app截图" }
    var exclusive: Bool { true }
    var supportedMediaTypes: Set<PHAssetMediaType> { [.image] }
    var supportedAlbumTypes: [(type: PHAssetCollectionType, subtype: PHAssetCollectionSubtype)] {
        return [(type: .smartAlbum, subtype: .smartAlbumScreenshots)]
    }
    
    private let keywords = [
        "任务助手", "股票", "持仓", "盈亏", "收益率", "净值",
        "上证指数", "深证成指", "创业板指", "市值", "涨幅", "跌幅",
        "上涨", "下跌", "趋势", "成功率", "均价",
        "买入", "卖出", "撤单", "成交", "委托", "市价", "限价",
        "ETF", "基金", "自选", "可用", "资金", "余额",
        "分时", "日K", "周K", "月K", "年K", "K线", "均线",
        "布林带", "量比", "换手率", "市盈率", "市净率",
        "涨停", "跌停", "停牌", "复牌", "退市"
    ]
    
    func matches(image: CGImage, asset: PHAsset) -> Bool {
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