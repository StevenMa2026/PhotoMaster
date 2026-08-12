import Photos
import SwiftUI
import UIKit
import QuartzCore

class PhotoSorter: ObservableObject {
    struct RuleOption: Identifiable {
        let id: String
        let title: String
    }
    
    // 扫描范围枚举
    enum ScanScope: String, CaseIterable, Identifiable {
        case unscanned = "未扫描"
        case uncategorized = "未分类"
        case all = "全部照片"
        
        var id: String { rawValue }
        var description: String { rawValue }
    }
    
    // 已扫描照片的缓存键
    private let scannedAssetsKey = "scannedAssets"

    @Published var status = "等待开始"
    @Published var isRunning = false

    // 处理时间显示：非 @Published，每秒更新不触发 SwiftUI 重渲染。
    // 扫描中 processedCount 每 100ms 刷新会让 UI 读取到最新值。
    private(set) var processingTime = "00:00"

    @Published var totalCount = 0
    @Published var processedCount = 0

    /// 当前正在处理的照片缩略图（复用扫描解码结果降采样，零额外请求）。
    /// 用于扫描时的"监控视图"实时展示。
    @Published var currentThumbnail: UIImage?

    /// 当前照片被归入的相册名数组（可能为空 = 未归类）。
    /// 扫描时展示在缩略图下方，即时反馈分类结果。
    @Published var currentAlbumNames: [String] = []

    /// 正在读取照片库（加载 asset 列表）时置 true，用于显示过渡 UI。
    /// 点击"开始"后立即为 true，加载完成或失败后为 false。
    @Published var isLoadingAssets = false

    /// 用户是否正在滚动页面。滚动时暂停启动新的 OCR 处理，让出 CPU/GPU 给 UI。
    /// 非 @Published：主线程写、后台线程读，Bool 原子读写足够。
    var isUserScrolling = false
    
    // 一键处理未分类截图的进度
    @Published var screenshotProcessingTotal = 0
    @Published var screenshotProcessingCount = 0
    
    // 一键移动到可清理相册的进度
    @Published var cleanupProcessingTotal = 0
    @Published var cleanupProcessingCount = 0
    
    private var startTime: Date?  // 记录开始处理时间
    private var timer: Timer?     // 计时器用于更新处理时间

    // 实时统计：各相册当前照片数量（启动时读取一次 + 扫描过程中成功加入后递增）
    @Published var albumPhotoCounts: [String: Int] = [:]
    @Published var selectedRuleIDs: Set<String> = []
    @Published var scanScope: ScanScope = .unscanned  // 默认未扫描
    @Published var startIndex: Int = 0  // 从第几张照片开始扫描（0-based）
    
    // 已扫描照片ID缓存
    private var scannedAssetIDsCache: Set<String>?

    // MARK: - 扫描性能优化
    /// 两帧之间的节流间隔 (秒)，防止 Vision OCR 连续占用 GPU 导致 UI 卡顿
    private let scanThrottleInterval: TimeInterval = 0.05

    /// 主线程进度通知的最短间隔 (秒)：每张照片不再立即刷新 UI，而是合并刷新
    private let progressNotifyInterval: TimeInterval = 0.1
    private var lastProgressNotifyTime: TimeInterval = 0

    /// 待写入 UserDefaults 的已扫描 ID 集合，批量刷入减少磁盘 I/O
    private var pendingScannedIDs = Set<String>()
    private let scannedFlushBatchSize = 50

    /// 缓存 "已在任意相册中的照片 ID" 集合，避免每次扫描重复遍历所有相册
    private var assetsInAnyAlbumCache: Set<String>?
    
    private var scannedAssetIDs: Set<String> {
        get {
            // 先检查内存缓存
            if let cached = scannedAssetIDsCache {
                return cached
            }

            // 缓存未命中，从 UserDefaults 读取
            if let data = UserDefaults.standard.data(forKey: scannedAssetsKey),
               let set = try? JSONDecoder().decode(Set<String>.self, from: data) {
                scannedAssetIDsCache = set
                return set
            }
            return []
        }
        set {
            // 避免通过 setter 全量写入；走 markAsScanned 批量刷入
            scannedAssetIDsCache = newValue
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: scannedAssetsKey)
            }
        }
    }
    
    // 缓存相册中的照片ID，减少重复查询
    private var albumTypeAssetCache: [String: Set<String>] = [:]
    
    // 缓存相册名对应的照片ID，减少重复查询
    private var albumNameAssetCache: [String: Set<String>] = [:]
    
    // 缓存相册存在性检查结果，避免重复查询
    private var albumExistenceCache: [String: Bool] = [:]

    // ✅ 统一管理所有分类器，顺序决定匹配优先级
    private let classifiers: [(id: String, title: String, classifier: PhotoClassifiable)] = [
        // 第1组：特殊系统相册
        ("FavoriteYearClassifier", "精华年份（收藏）", FavoriteYearClassifier()),
        ("SelfieClassifier", "自拍", SelfieClassifier()),

        // 优先跑因为它可能包含很多后置分类器的关键词
        ("AppDevClassifier", "app开发", AppDevClassifier()),
        
        // 第2组：高频
        ("FanRenClassifier", "凡人修仙传", FanRenClassifier()),
        ("FinanceClassifier", "投资", FinanceClassifier()),
        
        // 第3组：截图类
        ("AppScreenshotsClassifier", "app截图", AppScreenshotsClassifier()),
        ("WeChatFavoriteClassifier", "微信favorite截图", WeChatFavoriteClassifier()),
        ("WangZheClassifier", "王者荣耀", WangZheClassifier()),
        ("PS5ProGameClassifier", "PS5 Pro游戏", PS5ProGameClassifier()),
        
        // 第4组：地点类
        ("ShangDeClassifier", "尚德", ShangDeClassifier()),
        ("SwimClassifier", "游泳课", SwimClassifier()),
        ("WorkClassifier", "工作", WorkClassifier()),
        ("ParkClassifier", "公园", ParkClassifier()),

        // 第5组：非必须截图类
        ("TvMovieClassifier", "经典电视电影综艺画面", TvMovieClassifier()),

        // 第6组：依据图像分类
        ("PetClassifier", "宠物", PetClassifier()),
        ("FoodClassifier", "食物", FoodClassifier()),
        ("BuildingBlocksClassifier", "积木", BuildingBlocksClassifier())
    ]

    struct RuleGroup {
        let title: String
        let rules: [RuleOption]
    }
    
    var ruleOptions: [RuleOption] {
        classifiers.map { RuleOption(id: $0.id, title: $0.title) }
    }
    
    var ruleGroups: [RuleGroup] {
        // 定义规则分组
        var groups: [RuleGroup] = []
        
        // 全部分类器（不指定相册类型和相册名，检查全部照片）
        // 只有当分类器对应的 albumName 存在于设备中时才显示
        let allRules = classifiers.filter { entry in
            let hasNoAlbumRestrictions = entry.classifier.supportedAlbumTypes.isEmpty && entry.classifier.supportedAlbumNames.isEmpty
            // 检查该分类器对应的相册名是否存在
            let albumNameExists = hasAlbum(named: entry.classifier.albumName)
            return hasNoAlbumRestrictions && albumNameExists
        }.map { RuleOption(id: $0.id, title: $0.title) }
        
        // 收藏相册分类器（检查smartAlbumFavorites）- 总是显示
        let favoriteRules = classifiers.filter { 
            $0.classifier.supportedAlbumTypes.contains { $0.subtype == .smartAlbumFavorites }
        }.map { RuleOption(id: $0.id, title: $0.title) }
        
        // 特定范围分类器（指定了相册类型或相册名，但不是收藏）
        // 只有当分类器对应的 albumName 存在于设备中时才显示
        let specificRules = classifiers.filter { entry in
            // 有相册限制（不是"全部"）
            let hasAlbumRestrictions = !entry.classifier.supportedAlbumTypes.isEmpty || !entry.classifier.supportedAlbumNames.isEmpty
            // 不是"收藏"
            let isNotFavorite = !entry.classifier.supportedAlbumTypes.contains { $0.subtype == .smartAlbumFavorites }
            // 检查该分类器对应的相册名是否存在
            let albumNameExists = hasAlbum(named: entry.classifier.albumName)
            return hasAlbumRestrictions && isNotFavorite && albumNameExists
        }.map { RuleOption(id: $0.id, title: $0.title) }
        
        if !allRules.isEmpty {
            groups.append(RuleGroup(title: "全部", rules: allRules))
        }
        if !favoriteRules.isEmpty {
            groups.append(RuleGroup(title: "收藏", rules: favoriteRules))
        }
        if !specificRules.isEmpty {
            groups.append(RuleGroup(title: "特定范围", rules: specificRules))
        }
        
        return groups
    }
    
    // 检查指定类型的相册是否存在于设备中（带缓存）
    private func hasAlbumType(type: PHAssetCollectionType, subtype: PHAssetCollectionSubtype) -> Bool {
        let key = "\(type.rawValue)-\(subtype.rawValue)"
        if let cached = albumExistenceCache[key] {
            return cached
        }
        let collections = PHAssetCollection.fetchAssetCollections(
            with: type,
            subtype: subtype,
            options: nil
        )
        let exists = collections.count > 0
        albumExistenceCache[key] = exists
        return exists
    }
    
    // 检查指定名字的相册是否存在于设备中（带缓存）
    private func hasAlbum(named albumName: String) -> Bool {
        if let cached = albumExistenceCache[albumName] {
            return cached
        }
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "title == %@", albumName)
        let collections = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .any,
            options: options
        )
        let exists = collections.count > 0
        albumExistenceCache[albumName] = exists
        return exists
    }

    // Cache album collections to avoid repeated Photos-framework lookups.
    // Note: albums should be created by you; this sorter will not auto-create.
    private var albumCache: [String: PHAssetCollection] = [:]

    // 根据 classifier 的 `exclusive` 属性决定是否停止继续判断后续分类器：
    // - `exclusive == true`：一旦命中该分类，停止继续判断后续分类器
    // - `exclusive == false`：允许继续追加其他命中的相册
    // 预处理分类器，过滤出可能匹配的分类器
    private func getApplicableClassifiers(for asset: PHAsset) -> [(id: String, title: String, classifier: PhotoClassifiable)] {
        var applicable: [(id: String, title: String, classifier: PhotoClassifiable)] = []

        for entry in classifiers {
            guard selectedRuleIDs.contains(entry.id) else { continue }
            let classifier = entry.classifier

            // 目标相册不存在则跳过：不做 OCR、不显示"归类到"。
            // 先按动态 albumName(for:) 判断，FavoriteYear 这类按年份的也能正确过滤。
            guard albumExists(for: classifier, asset: asset) else { continue }

            // 检查媒体类型
            guard classifier.supportedMediaTypes.contains(asset.mediaType) else { continue }

            // 检查相册类型
            let albumTypesMatch = !classifier.supportedAlbumTypes.isEmpty &&
                                  isAssetInAlbumTypes(asset: asset, albumTypes: classifier.supportedAlbumTypes)

            // 检查相册名
            let albumNamesMatch = !classifier.supportedAlbumNames.isEmpty &&
                                  isAssetInAlbumNames(asset: asset, albumNames: classifier.supportedAlbumNames)

            // 相册类型匹配 或 相册名匹配，任一满足即可
            // 如果都没设置（albumTypes和albumNames都是空），则视为匹配
            let hasNoAlbumRestrictions = classifier.supportedAlbumTypes.isEmpty && classifier.supportedAlbumNames.isEmpty
            guard hasNoAlbumRestrictions || albumTypesMatch || albumNamesMatch else { continue }

            applicable.append(entry)
        }

        return applicable
    }

    /// 判断分类器的目标相册是否存在于设备中（带缓存）。
    /// 返回 nil 视为不存在。
    private func albumExists(for classifier: PhotoClassifiable, asset: PHAsset) -> Bool {
        let name = classifier.albumName(for: asset)
        guard !name.isEmpty else { return false }

        // 优先用已构建的 albumCache（标题 → 相册），命中即存在
        if albumCache[name] != nil {
            return true
        }
        // 缓存里没有就显式查询一次（带 albumExistenceCache）
        return hasAlbum(named: name)
    }
    
    func classifyAll(image: CGImage, asset: PHAsset) -> [String] {
        var albumNames: [String] = []
        var seen = Set<String>()
        
        let fileName = asset.value(forKey: "filename") as? String ?? "无文件名"
        print("\n[PhotoSorter] 处理照片: \(fileName)")

        // 获取适用于当前照片的分类器
        let applicableClassifiers = getApplicableClassifiers(for: asset)
        
        for entry in applicableClassifiers {
            let classifier = entry.classifier
            
            guard classifier.matches(image: image, asset: asset) else { continue }

            let name = classifier.albumName(for: asset)
            guard seen.insert(name).inserted else { continue }
            albumNames.append(name)
            print("[PhotoSorter] 归类到: \(name)")

            if classifier.exclusive {
                break
            }
        }

        return albumNames
    }
    
    // 检查照片是否在指定的相册类型中
    private func isAssetInAlbumTypes(asset: PHAsset, albumTypes: [(type: PHAssetCollectionType, subtype: PHAssetCollectionSubtype)]) -> Bool {
        for albumType in albumTypes {
            let key = "\(albumType.type.rawValue)-\(albumType.subtype.rawValue)"
            
            // 检查缓存中是否有该相册类型的照片ID
            if let assetIDs = albumTypeAssetCache[key] {
                if assetIDs.contains(asset.localIdentifier) {
                    return true
                }
                continue
            }
            
            // 缓存中没有，重新获取并缓存
            let collections = PHAssetCollection.fetchAssetCollections(
                with: albumType.type,
                subtype: albumType.subtype,
                options: nil
            )
            
            var assetIDs = Set<String>()
            var found = false
            
            collections.enumerateObjects { (collection, _, stop) in
                let assetsInCollection = PHAsset.fetchAssets(in: collection, options: nil)
                assetsInCollection.enumerateObjects { (a, _, _) in
                    let id = a.localIdentifier
                    assetIDs.insert(id)
                    if id == asset.localIdentifier {
                        found = true
                        stop.pointee = true
                    }
                }
                if found {
                    stop.pointee = true
                }
            }
            
            // 缓存该相册类型的照片ID
            albumTypeAssetCache[key] = assetIDs
            
            if found {
                return true
            }
        }
        return false
    }

    // 检查照片是否在指定的相册名中
    private func isAssetInAlbumNames(asset: PHAsset, albumNames: Set<String>) -> Bool {
        for albumName in albumNames {
            // 检查缓存中是否有该相册名的照片ID
            if let assetIDs = albumNameAssetCache[albumName] {
                if assetIDs.contains(asset.localIdentifier) {
                    return true
                }
                continue
            }
            
            // 缓存中没有，重新获取并缓存
            let options = PHFetchOptions()
            options.predicate = NSPredicate(format: "localizedTitle == %@", albumName)
            let collections = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: options)
            
            var assetIDs = Set<String>()
            var found = false
            
            collections.enumerateObjects { (collection, _, stop) in
                let assetsInCollection = PHAsset.fetchAssets(in: collection, options: nil)
                assetsInCollection.enumerateObjects { (a, _, _) in
                    let id = a.localIdentifier
                    assetIDs.insert(id)
                    if id == asset.localIdentifier {
                        found = true
                        stop.pointee = true
                    }
                }
                if found {
                    stop.pointee = true
                }
            }
            
            // 缓存该相册名的照片ID
            albumNameAssetCache[albumName] = assetIDs
            
            if found {
                return true
            }
        }
        return false
    }

    // 👇 下面是你原有的所有逻辑，完全不用改 👇
    // 过滤掉“已经在任意相册中的照片”后，用数组来承载可处理范围
    private var assets: [PHAsset] = []
    private var currentIndex = 0

    private let indexKey = "lastIndex"
    private let countKey = "lastCount"
    private let totalKey = "lastTotal"

    // qos 设为 background：OCR 属于低优先级批量任务，
    // 让出 CPU 给 UI 线程，避免扫描时滑动掉帧。
    private let scanQueue = DispatchQueue(label: "com.photomaster.scan", qos: .background)

    init() {
        selectedRuleIDs = Set() // 默认全部清空
        
        // 启动时获取人物列表
        // let persons = PersonUtil.fetchAllPersons()
        // print("[PhotoSorter] 启动时获取的人物列表:")
        // for person in persons {
        //     print("- \(person.name): \(person.assetCount) 张照片")
        // }
    }

    func toggleRuleSelection(_ id: String, enabled: Bool) {
        if enabled {
            selectedRuleIDs.insert(id)
        } else {
            selectedRuleIDs.remove(id)
        }
        _needsHighResCache = nil
        buildAlbumCache()
        albumPhotoCounts = buildInitialAlbumPhotoCounts()
    }

    func selectAllRules() {
        selectedRuleIDs = Set(classifiers.map { $0.id })
        _needsHighResCache = nil
        buildAlbumCache()
        albumPhotoCounts = buildInitialAlbumPhotoCounts()
    }

    func clearAllRules() {
        selectedRuleIDs.removeAll()
        _needsHighResCache = nil
        buildAlbumCache()
        albumPhotoCounts = buildInitialAlbumPhotoCounts()
    }

    func selectGroupRules(groupTitle: String) {
        for group in ruleGroups where group.title == groupTitle {
            for rule in group.rules {
                selectedRuleIDs.insert(rule.id)
            }
            break
        }
        _needsHighResCache = nil
        buildAlbumCache()
        albumPhotoCounts = buildInitialAlbumPhotoCounts()
    }

    func clearGroupRules(groupTitle: String) {
        for group in ruleGroups where group.title == groupTitle {
            for rule in group.rules {
                selectedRuleIDs.remove(rule.id)
            }
            break
        }
        _needsHighResCache = nil
        buildAlbumCache()
        albumPhotoCounts = buildInitialAlbumPhotoCounts()
    }

    // MARK: - 外部调用
    func start() {
        guard !selectedRuleIDs.isEmpty else {
            status = "请先选择至少一个规则"
            return
        }
        // 只有在重新扫描或刚开始扫描时才重置计数和缓存，暂停后再继续不重置
        if !isRunning {
            albumPhotoCounts.removeAll()
            albumTypeAssetCache.removeAll() // 清空相册类型缓存
            albumNameAssetCache.removeAll() // 清空相册名缓存
            albumExistenceCache.removeAll() // 清空相册存在性缓存
            assetsInAnyAlbumCache = nil      // 清空"已在相册中"缓存
            resetProcessingTime()
        }
        isLoadingAssets = true
        status = "正在读取相册…"
        ensurePermissionAndLoad(useStartIndex: false)
    }

    func startFromIndex() {
        guard !selectedRuleIDs.isEmpty else {
            status = "请先选择至少一个规则"
            return
        }
        // 只有在重新扫描或刚开始扫描时才重置计数和缓存，暂停后再继续不重置
        if !isRunning {
            albumPhotoCounts.removeAll()
            albumTypeAssetCache.removeAll() // 清空相册类型缓存
            albumNameAssetCache.removeAll() // 清空相册名缓存
            albumExistenceCache.removeAll() // 清空相册存在性缓存
            assetsInAnyAlbumCache = nil      // 清空"已在相册中"缓存
        }
        isLoadingAssets = true
        status = "正在读取相册…"
        ensurePermissionAndLoad(useStartIndex: true)
    }

    func pause() {
        isRunning = false
        stopProcessingTimer()
        finalizeScannedIDs()
        saveProgress()
        status = "已暂停 · 已处理 \(processedCount)/\(totalCount) 张"
    }

    func resume() {
        guard !assets.isEmpty else {
            start()
            return
        }
        isRunning = true
        startProcessingTimer()
        processNext()
    }

    func stopAndReset() {
        isRunning = false
        isLoadingAssets = false
        currentIndex = 0
        processedCount = 0
        totalCount = 0
        assets = []
        albumPhotoCounts.removeAll()
        currentThumbnail = nil
        currentAlbumNames = []
        albumTypeAssetCache.removeAll()
        albumNameAssetCache.removeAll()
        albumExistenceCache.removeAll()
        assetsInAnyAlbumCache = nil
        finalizeScannedIDs()

        UserDefaults.standard.removeObject(forKey: indexKey)
        UserDefaults.standard.removeObject(forKey: countKey)
        UserDefaults.standard.removeObject(forKey: totalKey)

        resetProcessingTime()
        status = "等待开始"
    }
    
    // MARK: - 处理时间管理
    private func resetProcessingTime() {
        startTime = nil
        stopProcessingTimer()
        processingTime = "00:00"
    }
    
    private func startProcessingTimer() {
        if startTime == nil {
            startTime = Date()
        }
        stopProcessingTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateProcessingTime()
        }
    }
    
    private func stopProcessingTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    private func updateProcessingTime() {
        guard let startTime = startTime else {
            processingTime = "00:00"
            return
        }
        
        let elapsed = Date().timeIntervalSince(startTime)
        let minutes = Int(elapsed / 60)
        let seconds = Int(elapsed.truncatingRemainder(dividingBy: 60))
        processingTime = String(format: "%02d:%02d", minutes, seconds)
    }

    // MARK: - 权限 & 加载

    /// 应用启动时调用一次：如果还未决定则请求相册权限。
    /// 之后 start() 只做状态检查，不再触发权限弹窗。
    func requestPhotoPermissionIfNeeded() {
        if PHPhotoLibrary.authorizationStatus() == .notDetermined {
            PHPhotoLibrary.requestAuthorization { _ in }
        }
    }

    /// 检查权限并加载。已授权直接加载，未授权给出提示。
    private func ensurePermissionAndLoad(useStartIndex: Bool) {
        let status = PHPhotoLibrary.authorizationStatus()
        switch status {
        case .authorized, .limited:
            if useStartIndex {
                loadAssetsWithStartIndex()
            } else {
                loadAssets()
            }
        default:
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.isLoadingAssets = false
                self.status = "请允许相册权限"
            }
        }
    }

    private func loadAssets() {
        loadAssetsInternal(useUserStartIndex: false)
    }

    private func loadAssetsWithStartIndex() {
        loadAssetsInternal(useUserStartIndex: true)
    }

    /// 统一的 asset 加载逻辑，消除 loadAssets / loadAssetsWithStartIndex 的代码重复
    private func loadAssetsInternal(useUserStartIndex: Bool) {
        // 所有 Photos fetch 都放到后台线程，避免"开始整理"时卡住主线程。
        scanQueue.async { [weak self] in
            guard let self = self else { return }

            self.buildAlbumCache()
            let initialCounts = self.buildInitialAlbumPhotoCounts()

            // 按规则类型分组
            var albumTypesWithRules: [PhotoClassifiable] = []
            var albumNamesWithRules: [PhotoClassifiable] = []
            var unrestrictedRules: [PhotoClassifiable] = []

            for entry in classifiers where selectedRuleIDs.contains(entry.id) {
                let c = entry.classifier
                let hasTypes = !c.supportedAlbumTypes.isEmpty
                let hasNames = !c.supportedAlbumNames.isEmpty
                if hasTypes { albumTypesWithRules.append(c) }
                if hasNames { albumNamesWithRules.append(c) }
                if !hasTypes && !hasNames { unrestrictedRules.append(c) }
            }

            var allAssets = Set<PHAsset>()

            // 相册类型
            if !albumTypesWithRules.isEmpty {
                var seen = Set<String>()
                var types: [(PHAssetCollectionType, PHAssetCollectionSubtype)] = []
                for c in albumTypesWithRules {
                    for t in c.supportedAlbumTypes {
                        let key = "\(t.type.rawValue)-\(t.subtype.rawValue)"
                        guard seen.insert(key).inserted else { continue }
                        types.append((t.type, t.subtype))
                    }
                }
                fetchAssetsFromAlbumTypes(types).forEach { allAssets.insert($0) }
            }

            // 相册名
            if !albumNamesWithRules.isEmpty {
                var names = Set<String>()
                for c in albumNamesWithRules { names.formUnion(c.supportedAlbumNames) }
                fetchAssetsFromAlbumNames(names).forEach { allAssets.insert($0) }
            }

            // 无限制
            if !unrestrictedRules.isEmpty {
                let opt = PHFetchOptions()
                opt.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
                opt.predicate = NSPredicate(
                    format: "mediaType == %d OR mediaType == %d",
                    PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)
                PHAsset.fetchAssets(with: opt).enumerateObjects { a, _, _ in allAssets.insert(a) }
            }

            var arr = Array(allAssets)
            arr.sort { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }

            // 范围过滤
            var filtered: [PHAsset] = []
            filtered.reserveCapacity(arr.count)

            switch self.scanScope {
            case .all:
                filtered = arr
            case .uncategorized:
                let inAlbum = self.buildAssetsInAnyAlbumSet()
                for a in arr { if !inAlbum.contains(a.localIdentifier) { filtered.append(a) } }
            case .unscanned:
                let inAlbum = self.buildAssetsInAnyAlbumSet()
                for a in arr {
                    if !inAlbum.contains(a.localIdentifier),
                       !self.scannedAssetIDs.contains(a.localIdentifier) {
                        filtered.append(a)
                    }
                }
            }

            let savedTotal = UserDefaults.standard.integer(forKey: self.totalKey)

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.isLoadingAssets = false
                self.assets = filtered
                self.totalCount = filtered.count
                self.albumPhotoCounts = initialCounts

                if useUserStartIndex {
                    let target = min(max(0, self.startIndex), self.totalCount)
                    self.currentIndex = target
                    self.processedCount = target
                    self.status = "从第 \(target + 1) 张开始，共 \(self.totalCount) 张"
                } else {
                    if savedTotal == self.totalCount, savedTotal > 0 {
                        self.currentIndex = UserDefaults.standard.integer(forKey: self.indexKey)
                        self.processedCount = min(UserDefaults.standard.integer(forKey: self.countKey), self.totalCount)
                    } else {
                        self.currentIndex = 0
                        self.processedCount = 0
                    }
                    self.status = "已处理 \(self.processedCount)/\(self.totalCount) 张"
                }

                UserDefaults.standard.set(self.totalCount, forKey: self.totalKey)
                self.isRunning = true
                self.processNext()
            }
        }
    }
    
    /// 从指定的相册名中获取所有照片
    /// - Parameter albumNames: 相册名集合
    /// - Returns: 照片资产数组
    private func fetchAssetsFromAlbumNames(_ albumNames: Set<String>) -> [PHAsset] {
        var assets: [PHAsset] = []
        let mediaPredicate = NSPredicate(
            format: "mediaType == %d OR mediaType == %d",
            PHAssetMediaType.image.rawValue,
            PHAssetMediaType.video.rawValue
        )
        
        for albumName in albumNames {
            let options = PHFetchOptions()
            options.predicate = NSPredicate(format: "localizedTitle == %@", albumName)
            let collections = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: options)
            
            collections.enumerateObjects { collection, _, _ in
                let fetchOptions = PHFetchOptions()
                fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
                fetchOptions.predicate = mediaPredicate
                
                let albumAssets = PHAsset.fetchAssets(in: collection, options: fetchOptions)
                albumAssets.enumerateObjects { (asset, _, _) in
                    assets.append(asset)
                }
            }
        }
        
        return assets
    }
    
    /// 从指定的相册类型中获取所有照片
    /// - Parameter albumTypes: 相册类型数组
    /// - Returns: 照片资产数组
    private func fetchAssetsFromAlbumTypes(_ albumTypes: [(type: PHAssetCollectionType, subtype: PHAssetCollectionSubtype)]) -> [PHAsset] {
        var assets: [PHAsset] = []
        let mediaPredicate = NSPredicate(
            format: "mediaType == %d OR mediaType == %d",
            PHAssetMediaType.image.rawValue,
            PHAssetMediaType.video.rawValue
        )
        
        for albumType in albumTypes {
            let collections = PHAssetCollection.fetchAssetCollections(
                with: albumType.type,
                subtype: albumType.subtype,
                options: nil
            )
            
            collections.enumerateObjects { (collection, _, _) in
                let fetchOptions = PHFetchOptions()
                fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
                fetchOptions.predicate = mediaPredicate
                
                let albumAssets = PHAsset.fetchAssets(in: collection, options: fetchOptions)
                albumAssets.enumerateObjects { (asset, _, _) in
                    assets.append(asset)
                }
            }
        }
        
        return assets
    }

    // MARK: - 核心处理
    private func processNext() {
        guard currentIndex < assets.count, isRunning else {
            if currentIndex >= assets.count {
                DispatchQueue.main.async {
                    self.status = "✅ 全部处理完成"
                    self.isRunning = false
                    self.stopProcessingTimer()
                }
            }
            // 扫描结束或暂停时，刷入已扫描 ID 防止丢失
            finalizeScannedIDs()
            return
        }

        // 在第一次处理时启动计时器
        if currentIndex == 0 && processedCount == 0 {
            DispatchQueue.main.async {
                self.startProcessingTimer()
            }
        }

        let asset = assets[currentIndex]

        scanQueue.async { [weak self] in
            guard let self = self else { return }

            let semaphore = DispatchSemaphore(value: 0)

            self.processSingle(asset) {
                // currentIndex 每张照片都在主线程推进（非 @Published，不触发 SwiftUI 重渲染）
                // processedCount + status 两个 @Published 每 100ms 合并刷新一次，
                // 避免每张照片 3 次 objectWillChange 导致扫描时滑动卡顿。
                let now = CACurrentMediaTime()
                if now - self.lastProgressNotifyTime >= self.progressNotifyInterval {
                    self.lastProgressNotifyTime = now
                    DispatchQueue.main.async {
                        self.currentIndex += 1
                        let count = self.currentIndex
                        self.processedCount = count
                        self.status = "已处理 \(count)/\(self.totalCount) 张"
                    }
                } else {
                    DispatchQueue.main.async {
                        self.currentIndex += 1
                    }
                }
                semaphore.signal()
            }

            semaphore.wait()

            self.scheduleNextProcess()
        }
    }

    /// 调度下一张照片的处理。
    /// 用户滚动时挂起整个扫描（当前张 OCR 结束后就不再启动新工作），
    /// 让出 CPU/GPU 给 UI；滚动停止约 0.4s 后自动恢复。
    private func scheduleNextProcess() {
        let checkInterval: TimeInterval = isUserScrolling ? 0.4 : scanThrottleInterval
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + checkInterval) { [weak self] in
            guard let self = self else { return }
            guard self.isRunning else { return }
            if self.isUserScrolling {
                self.scheduleNextProcess()
            } else {
                self.processNext()
            }
        }
    }

    // MARK: 🔥 自适应分辨率：OCR 分类器用原图保证文字识别率，图像分类用降采样节省性能
    private var _needsHighResCache: Bool?

    private var needsHighRes: Bool {
        if let cached = _needsHighResCache { return cached }
        let val = classifiers.contains { entry in
            selectedRuleIDs.contains(entry.id) && entry.classifier.requiresHighResolution
        }
        _needsHighResCache = val
        return val
    }

    // MARK: 自适应分辨率核心：OCR 用原图，纯图像分类用降采样
    private func processSingle(_ asset: PHAsset, completion: @escaping () -> Void) {
        // 视频不走 OCR/截图类逻辑，使用占位图触发仅支持视频的规则（如 FavoriteYear）。
        if asset.mediaType == .video {
            let albumNames = classifyAll(image: placeholderImage(), asset: asset)
            DispatchQueue.main.async {
                self.currentAlbumNames = albumNames
                self.currentThumbnail = nil
            }
            for albumName in albumNames {
                move(asset: asset, toAlbum: albumName)
            }
            // 标记为已扫描
            markAsScanned(asset: asset)
            completion()
            return
        }

        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.resizeMode = .none          // 不缩放：原尺寸
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true

        // OCR 规则 → 原图；纯图像分类/位置 → 降采样到 1024 省性能
        let targetSize: CGSize = needsHighRes
            ? PHImageManagerMaximumSize
            : CGSize(width: 1024, height: 1024)

        // 在异步请求前打印位置信息，避免位置信息丢失
        #if DEBUG
        let location = asset.location
        if let loc = location {
            print("[📍 照片位置] 索引: \(currentIndex), 纬度: \(loc.coordinate.latitude), 经度: \(loc.coordinate.longitude)")
        } else {
            print("[📍 照片位置] 索引: \(currentIndex), 无位置信息")
        }
        #endif

        PHImageManager.default().requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: needsHighRes ? .default : .aspectFit,
            options: options
        ) { [weak self] image, info in
            guard let self = self,
                  let image = image,
                  let cgImage = image.cgImage else {
                completion()
                return
            }

            // 实时缩略图 + 归类结果：复用已解码的图降采样，避免额外 PHImageManager 请求。
            // 只在主线程设置 @Published，避免跨线程更新 SwiftUI。
            let thumb = self.makeThumbnail(from: cgImage)
            let albumNames = self.classifyAll(image: cgImage, asset: asset)
            DispatchQueue.main.async {
                self.currentThumbnail = thumb
                self.currentAlbumNames = albumNames
            }

            for albumName in albumNames {
                self.move(asset: asset, toAlbum: albumName)
            }

            // 标记为已扫描
            self.markAsScanned(asset: asset)

            completion()
        }
    }
    
    // 标记照片为已扫描（批量刷入 UserDefaults，减少磁盘 I/O）
    private func markAsScanned(asset: PHAsset) {
        if scannedAssetIDsCache == nil {
            scannedAssetIDsCache = scannedAssetIDs
        }
        scannedAssetIDsCache?.insert(asset.localIdentifier)
        pendingScannedIDs.insert(asset.localIdentifier)

        if pendingScannedIDs.count >= scannedFlushBatchSize {
            flushScannedIDs()
        }
    }

    /// 将待写入的已扫描 ID 批量持久化到 UserDefaults
    private func flushScannedIDs() {
        guard !pendingScannedIDs.isEmpty else { return }
        // 重新读取最新值再合并，防止多线程竞态覆盖
        var current = scannedAssetIDs
        current.formUnion(pendingScannedIDs)
        pendingScannedIDs.removeAll(keepingCapacity: true)
        scannedAssetIDsCache = current
        if let data = try? JSONEncoder().encode(current) {
            UserDefaults.standard.set(data, forKey: scannedAssetsKey)
        }
    }

    // MARK: - 扫描完成收尾
    /// 扫描停止或完成时调用，确保所有已扫描 ID 都已被持久化
    private func finalizeScannedIDs() {
        flushScannedIDs()
    }

    // MARK: - 移动照片（不创建相册）
    private func move(asset: PHAsset, toAlbum name: String) {
        guard let cached = albumCache[name] else {
            // 相册不存在时跳过（不查找、不报错）。
            return
        }

        addAsset(asset, to: cached, albumName: name)
    }
    
    private func addAsset(_ asset: PHAsset, to album: PHAssetCollection, albumName: String) {
        // 检查照片是否已经在目标相册中
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "localIdentifier = %@", asset.localIdentifier)
        let existingAssets = PHAsset.fetchAssets(in: album, options: fetchOptions)
        
        // 如果照片已经在相册中，不执行添加操作，也不增加计数
        guard existingAssets.count == 0 else {
            return
        }
        
        PHPhotoLibrary.shared().performChanges({
            PHAssetCollectionChangeRequest(for: album)?.addAssets([asset] as NSArray)
        }) { [weak self] success, _ in
            guard let self, success else { return }
            DispatchQueue.main.async {
                self.albumPhotoCounts[albumName, default: 0] += 1
            }
        }
    }
    
    private func buildAlbumCache() {
        albumCache.removeAll(keepingCapacity: true)

        let collections = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .albumRegular,
            options: nil
        )

        collections.enumerateObjects { obj, _, _ in
            let collection = obj as PHAssetCollection
            let title = collection.localizedTitle ?? ""
            if !title.isEmpty {
                self.albumCache[title] = collection
            }
        }
    }

    /// 计算选中规则对应相册的初始计数（不直接赋值 @Published，避免跨线程）。
    /// 返回字典，由调用方在主线程设置 albumPhotoCounts。
    @discardableResult
    private func buildInitialAlbumPhotoCounts() -> [String: Int] {
        // 初始化选中规则对应的相册，计数为0
        var counts: [String: Int] = [:]

        // 只统计我们关心的目标相册（分类器对应的相册名 + 精华年份）
        var targetAlbumNames = Set<String>()
        for entry in classifiers where selectedRuleIDs.contains(entry.id) {
            let albumName = entry.classifier.albumName

            // 精华年份相册：只统计年份相册（精华2021-精华2026），不统计单独的"精华"相册
            if albumName == "精华" {
                for year in 2021...2026 {
                    targetAlbumNames.insert("精华\(year)")
                }
            } else {
                // 其他相册只有在设备中存在时才显示
                if hasAlbum(named: albumName) {
                    targetAlbumNames.insert(albumName)
                }
            }
        }

        for name in targetAlbumNames {
            counts[name] = 0
        }

        return counts
    }

    // Build a set of asset identifiers that are already present in any user album.
    // Used to pre-filter the scan workload (skip photos already in albums).
    // Result is cached to avoid re-enumerating every time loadAssets is called.
    private func buildAssetsInAnyAlbumSet() -> Set<String> {
        if let cached = assetsInAnyAlbumCache { return cached }

        var ids = Set<String>()

        let collections = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .albumRegular,
            options: nil
        )

        collections.enumerateObjects { obj, _, _ in
            let collection = obj as PHAssetCollection
            let assetsInCollection = PHAsset.fetchAssets(in: collection, options: nil)
            assetsInCollection.enumerateObjects { asset, _, _ in
                ids.insert(asset.localIdentifier)
            }
        }

        assetsInAnyAlbumCache = ids
        return ids
    }

    private func placeholderImage() -> CGImage {
        let size = CGSize(width: 1, height: 1)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        return image.cgImage!
    }

    /// 从已解码的 CGImage 生成监控视图缩略图（最长边 ~800pt，居中裁切）。
    /// 在后台线程调用，返回的 UIImage 由调用方切到主线程设置。
    private func makeThumbnail(from cgImage: CGImage) -> UIImage {
        let targetMax: CGFloat = 800
        let w = CGFloat(cgImage.width)
        let h = CGFloat(cgImage.height)
        guard w > 0, h > 0 else {
            return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
        }

        // 计算保持宽高比的缩略尺寸
        let scale = min(1, targetMax / max(w, h))
        let tw = max(1, w * scale)
        let th = max(1, h * scale)

        // 安全使用 UIGraphicsImageRenderer 在后台渲染
        UIGraphicsBeginImageContextWithOptions(CGSize(width: tw, height: th), false, 1.0)
        defer { UIGraphicsEndImageContext() }
        guard let ctx = UIGraphicsGetCurrentContext() else {
            return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
        }
        ctx.interpolationQuality = .medium
        ctx.translateBy(x: 0, y: th)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: tw, height: th))
        if let result = UIGraphicsGetImageFromCurrentImageContext() {
            return result
        }
        return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
    }

    // MARK: - 进度保存
    private func saveProgress() {
        UserDefaults.standard.set(currentIndex, forKey: indexKey)
        UserDefaults.standard.set(processedCount, forKey: countKey)
        UserDefaults.standard.set(totalCount, forKey: totalKey)
    }
    
    // MARK: - 一键将未分类截图装入"未分类截图"相册
    func moveUncategorizedScreenshotsToAlbum(completion: @escaping (Int) -> Void) {
        DispatchQueue.main.async {
            self.screenshotProcessingTotal = 0
            self.screenshotProcessingCount = 0
        }
        
        // 获取截图相册
        let screenshotsCollection = PHAssetCollection.fetchAssetCollections(
            with: .smartAlbum,
            subtype: .smartAlbumScreenshots,
            options: nil
        )
        
        guard let screenshotsAlbum = screenshotsCollection.firstObject else {
            completion(0)
            return
        }
        
        // 获取截图相册中的所有照片
        let allScreenshots = PHAsset.fetchAssets(in: screenshotsAlbum, options: nil)
        var screenshotIdentifiers: Set<String> = []
        allScreenshots.enumerateObjects { asset, _, _ in
            screenshotIdentifiers.insert(asset.localIdentifier)
        }
        
        // 获取已经在任何用户相册中的照片 ID
        let assetsInAnyAlbum = buildAssetsInAnyAlbumSet()
        
        // 找出未分类的截图（在截图相册中但不在任何用户相册中）
        let uncategorizedScreenshots = screenshotIdentifiers.subtracting(assetsInAnyAlbum)
        
        guard !uncategorizedScreenshots.isEmpty else {
            completion(0)
            return
        }
        
        // 创建或获取"未分类截图"相册
        let targetAlbumName = "未分类截图"
        createAlbumIfNeeded(named: targetAlbumName) { [weak self] album in
            guard let self = self, let album = album else {
                completion(0)
                return
            }
            
            // 获取未分类截图的 PHAsset 对象
            var uncategorizedAssets: [PHAsset] = []
            allScreenshots.enumerateObjects { asset, _, _ in
                if uncategorizedScreenshots.contains(asset.localIdentifier) {
                    uncategorizedAssets.append(asset)
                }
            }
            
            guard !uncategorizedAssets.isEmpty else {
                completion(0)
                return
            }
            
            // 设置进度
            DispatchQueue.main.async {
                self.screenshotProcessingTotal = uncategorizedAssets.count
            }
            
            // 将未分类截图添加到相册
            let group = DispatchGroup()
            var successCount = 0
            
            for (index, asset) in uncategorizedAssets.enumerated() {
                group.enter()
                PHPhotoLibrary.shared().performChanges({
                    PHAssetCollectionChangeRequest(for: album)?.addAssets([asset] as NSArray)
                }) { success, _ in
                    if success {
                        successCount += 1
                    }
                    
                    // 更新进度
                    DispatchQueue.main.async {
                        self.screenshotProcessingCount = index + 1
                    }
                    
                    group.leave()
                }
            }
            
            group.notify(queue: .main) {
                completion(successCount)
            }
        }
    }
    
    // 创建相册（如果不存在）
    private func createAlbumIfNeeded(named name: String, completion: @escaping (PHAssetCollection?) -> Void) {
        // 先检查相册是否已存在
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "title = %@", name)
        let collections = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .albumRegular,
            options: fetchOptions
        )
        
        if let existingAlbum = collections.firstObject {
            completion(existingAlbum)
            return
        }
        
        // 创建新相册
        var albumPlaceholder: PHObjectPlaceholder?
        PHPhotoLibrary.shared().performChanges({
            let createRequest = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: name)
            albumPlaceholder = createRequest.placeholderForCreatedAssetCollection
        }) { success, _ in
            guard success, let placeholder = albumPlaceholder else {
                completion(nil)
                return
            }
            
            // 获取刚创建的相册
            let fetchResult = PHAssetCollection.fetchAssetCollections(
                withLocalIdentifiers: [placeholder.localIdentifier],
                options: nil
            )
            completion(fetchResult.firstObject)
        }
    }
    
    // MARK: - 一键将选中规则对应相册的照片移动到"可清理"相册
    func moveSelectedAlbumPhotosToCleanupAlbum(completion: @escaping (Int) -> Void) {
        DispatchQueue.main.async {
            self.cleanupProcessingTotal = 0
            self.cleanupProcessingCount = 0
        }
        
        // 获取当前选中规则对应的所有相册名
        var targetAlbumNames: Set<String> = []
        for entry in classifiers where selectedRuleIDs.contains(entry.id) {
            let albumName = entry.classifier.albumName
            
            // 精华年份相册：只处理年份相册（精华2021-精华2026）
            if albumName == "精华" {
                for year in 2021...2026 {
                    if hasAlbum(named: "精华\(year)") {
                        targetAlbumNames.insert("精华\(year)")
                    }
                }
            } else {
                if hasAlbum(named: albumName) {
                    targetAlbumNames.insert(albumName)
                }
            }
        }
        
        guard !targetAlbumNames.isEmpty else {
            completion(0)
            return
        }
        
        // 获取这些相册中的所有照片
        var allAssets: Set<PHAsset> = []
        let mediaPredicate = NSPredicate(
            format: "mediaType == %d OR mediaType == %d",
            PHAssetMediaType.image.rawValue,
            PHAssetMediaType.video.rawValue
        )
        
        for albumName in targetAlbumNames {
            let options = PHFetchOptions()
            options.predicate = NSPredicate(format: "localizedTitle == %@", albumName)
            let collections = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: options)
            
            collections.enumerateObjects { collection, _, _ in
                let fetchOptions = PHFetchOptions()
                fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
                fetchOptions.predicate = mediaPredicate
                
                let albumAssets = PHAsset.fetchAssets(in: collection, options: fetchOptions)
                albumAssets.enumerateObjects { (asset, _, _) in
                    allAssets.insert(asset)
                }
            }
        }
        
        guard !allAssets.isEmpty else {
            completion(0)
            return
        }
        
        let assetsArray = Array(allAssets)
        
        // 设置进度
        DispatchQueue.main.async {
            self.cleanupProcessingTotal = assetsArray.count
        }
        
        // 创建或获取"可清理"相册
        let targetAlbumName = "可清理"
        createAlbumIfNeeded(named: targetAlbumName) { [weak self] album in
            guard let self = self, let album = album else {
                completion(0)
                return
            }
            
            // 将照片添加到可清理相册
            let group = DispatchGroup()
            var successCount = 0
            
            for (index, asset) in assetsArray.enumerated() {
                group.enter()
                
                // 检查照片是否已经在目标相册中
                let fetchOptions = PHFetchOptions()
                fetchOptions.predicate = NSPredicate(format: "localIdentifier = %@", asset.localIdentifier)
                let existingAssets = PHAsset.fetchAssets(in: album, options: fetchOptions)
                
                if existingAssets.count > 0 {
                    // 照片已存在，跳过
                    DispatchQueue.main.async {
                        self.cleanupProcessingCount = index + 1
                    }
                    group.leave()
                    continue
                }
                
                PHPhotoLibrary.shared().performChanges({
                    PHAssetCollectionChangeRequest(for: album)?.addAssets([asset] as NSArray)
                }) { success, _ in
                    if success {
                        successCount += 1
                    }
                    
                    // 更新进度
                    DispatchQueue.main.async {
                        self.cleanupProcessingCount = index + 1
                    }
                    
                    group.leave()
                }
            }
            
            group.notify(queue: .main) {
                completion(successCount)
            }
        }
    }
}
