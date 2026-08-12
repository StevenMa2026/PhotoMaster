import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var sorter = PhotoSorter()
    @State private var isStatsExpanded = false
    @State private var isScanStatsExpanded = false
    @FocusState private var isStartIndexFocused: Bool

    var body: some View {
        ZStack {
            Theme.background
                .ignoresSafeArea()

            NavigationStack {
                Group {
                    if sorter.isLoadingAssets {
                        loadingView
                    } else if sorter.isRunning {
                        scanningView
                    } else {
                        ScrollView {
                            VStack(spacing: 14) {
                                headerCard
                                progressCard
                                configCard
                                rulesCard
                                statsCard
                                actionArea
                                utilityArea
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                            .padding(.bottom, 24)
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .background(
                            ScrollStateObserver { isScrolling in
                                sorter.isUserScrolling = isScrolling
                            }
                        )
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: sorter.isLoadingAssets)
                .animation(.easeInOut(duration: 0.25), value: sorter.isRunning)
            }
            .navigationBarHidden(true)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            if sorter.isRunning {
                sorter.pause()
            }
        }
        .task {
            // 应用启动即请求相册权限，避免点"开始"时才弹窗/等待。
            sorter.requestPhotoPermissionIfNeeded()
        }
        .onTapGesture {
            isStartIndexFocused = false
        }
    }

    // MARK: - 状态进度计算
    private var progressFraction: Double {
        guard sorter.totalCount > 0 else { return 0 }
        return Double(min(sorter.processedCount, sorter.totalCount)) / Double(sorter.totalCount)
    }

    private var statusColor: Color {
        if sorter.isRunning { return Theme.accent }
        if sorter.status.contains("完成") { return Theme.success }
        if sorter.status.contains("权限") || sorter.status.contains("请先") { return Theme.warning }
        return .secondary
    }

    // MARK: - 加载过渡视图
    /// 点击"开始"后、扫描真正启动前的加载过渡，避免长时间无反馈。
    private var loadingView: some View {
        VStack(spacing: 18) {
            ProgressView()
                .scaleEffect(1.4)
                .tint(Theme.accent)

            Text("正在读取相册…")
                .font(.headline)

            Text("正在扫描照片库，可能需要几秒钟")
                .font(.caption)
                .foregroundColor(.secondary)

            Button(action: { sorter.stopAndReset() }) {
                Text("取消")
                    .font(.subheadline.weight(.medium))
            }
            .tint(Theme.danger)
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 扫描监控视图
    /// 扫描进行中时展示：实时缩略图 + 归类结果 + 大进度 + 可折叠相册统计。
    /// 不渲染规则配置等重控件，让每次进度更新的重渲染成本降到最低。
    private var scanningView: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 实时当前照片
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.black.opacity(0.06))
                    if let thumb = sorter.currentThumbnail {
                        Image(uiImage: thumb)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: 420)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .transition(.opacity)
                    } else {
                        ProgressView()
                            .scaleEffect(1.6)
                    }
                }
                .frame(height: 420)
                .padding(.horizontal, 16)
                .padding(.top, 16)

                // 当前照片归类结果
                albumResultRow
                    .padding(.horizontal, 20)

                // 大进度
                VStack(spacing: 12) {
                    HStack {
                        Text("扫描中")
                            .font(.title3.weight(.semibold))
                        Spacer()
                        Text("\(Int(progressFraction * 100))%")
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            .foregroundColor(Theme.accent)
                    }

                    progressBar(progress: progressFraction, color: Theme.accent, height: 14)

                    HStack {
                        Text("\(sorter.processedCount)/\(sorter.totalCount) 张")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("⏱ \(sorter.processingTime)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 24)

                // 可折叠相册统计
                scanStatsSection
                    .padding(.horizontal, 16)

                // 控制按钮
                HStack(spacing: 12) {
                    Button(action: { sorter.pause() }) {
                        Label("暂停", systemImage: "pause.fill")
                            .font(.title3.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .tint(Theme.warning)

                    Button(action: { sorter.stopAndReset() }) {
                        Label("结束", systemImage: "stop.fill")
                            .font(.title3.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .tint(Theme.danger)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    /// 当前照片归类结果：命中相册 → 绿色胶囊标签；未归类 → 灰色提示。
    private var albumResultRow: some View {
        HStack(spacing: 8) {
            if sorter.currentAlbumNames.isEmpty {
                Label("未归类", systemImage: "questionmark.circle")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(Capsule())
            } else {
                ForEach(sorter.currentAlbumNames, id: \.self) { name in
                    Label("→ \(name)", systemImage: "checkmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(Theme.success)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Theme.success.opacity(0.12))
                        .overlay(
                            Capsule().strokeBorder(Theme.success.opacity(0.3), lineWidth: 1)
                        )
                        .clipShape(Capsule())
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.2), value: sorter.currentAlbumNames)
    }

    /// 可折叠的相册数量统计：折叠时只显示总览，展开时逐相册显示张数。
    private var scanStatsSection: some View {
        VStack(spacing: 0) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isScanStatsExpanded.toggle()
                }
            }) {
                HStack {
                    Label("各相册数量", systemImage: "chart.pie.fill")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(sorter.albumPhotoCounts.count) 个相册")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Image(systemName: isScanStatsExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)

            if isScanStatsExpanded {
                Divider()
                    .padding(.vertical, 10)
                LazyVStack(spacing: 8) {
                    ForEach(sortedAlbumCounts, id: \.key) { name, count in
                        HStack(spacing: 10) {
                            Text(name)
                                .font(.subheadline)
                                .lineLimit(1)
                            Spacer()
                            Text("\(count) 张")
                                .font(.subheadline.monospacedDigit())
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .cardStyle()
    }

    private var sortedAlbumCounts: [(key: String, value: Int)] {
        sorter.albumPhotoCounts
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return lhs.key < rhs.key
            }
    }

    // MARK: - 头部：标题 + 状态
    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Text("智能相册归类")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Spacer()
                statusDot
            }

            HStack(spacing: 8) {
                Text(sorter.status)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onChange(of: sorter.status) {
                if sorter.status == "✅ 全部处理完成" {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var statusDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 9, height: 9)
            .overlay(Circle().strokeBorder(Color.white.opacity(0.4), lineWidth: 1))
    }

    // MARK: - 进度卡片
    @ViewBuilder
    private var progressCard: some View {
        if sorter.totalCount > 0 {
            VStack(spacing: 10) {
                HStack {
                    Text("处理进度")
                        .font(.headline)
                    Spacer()
                    Text("\(Int(progressFraction * 100))%")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .foregroundColor(Theme.accent)
                }

                progressBar(progress: progressFraction, color: Theme.accent, height: 10)

                HStack {
                    Text("\(sorter.processedCount)/\(sorter.totalCount) 张")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("⏱ \(sorter.processingTime)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .cardStyle()
        }
    }

    // MARK: - 扫描设置卡片
    private var configCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Text("扫描范围")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Picker("扫描范围", selection: $sorter.scanScope) {
                    ForEach(PhotoSorter.ScanScope.allCases) { scope in
                        Text(scope.description).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)
            }

            Divider()

            HStack(spacing: 12) {
                Text("从第几张开始")
                    .font(.subheadline.weight(.medium))
                Spacer()
                TextField("1", value: $sorter.startIndex, formatter: NumberFormatter())
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .focused($isStartIndexFocused)
                Text("张")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .cardStyle()
    }

    // MARK: - 规则选择卡片
    private var rulesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("执行规则")
                    .font(.headline)
                Spacer()
                Button("全选") {
                    isStartIndexFocused = false
                    sorter.selectAllRules()
                }
                .font(.caption.weight(.medium))
                .foregroundColor(Theme.accent)
                Button("清空") {
                    isStartIndexFocused = false
                    sorter.clearAllRules()
                }
                .font(.caption.weight(.medium))
                .foregroundColor(.secondary)
            }

            ForEach(sorter.ruleGroups, id: \.title) { group in
                ruleGroupView(group)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func ruleGroupView(_ group: PhotoSorter.RuleGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(group.title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("全选") {
                    isStartIndexFocused = false
                    sorter.selectGroupRules(groupTitle: group.title)
                }
                .font(.caption)
                .foregroundColor(Theme.accent)
                Button("清空") {
                    isStartIndexFocused = false
                    sorter.clearGroupRules(groupTitle: group.title)
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 8) {
                ForEach(group.rules) { option in
                    ruleOptionButton(option)
                }
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func ruleOptionButton(_ option: PhotoSorter.RuleOption) -> some View {
        let selected = sorter.selectedRuleIDs.contains(option.id)
        return Button {
            isStartIndexFocused = false
            sorter.toggleRuleSelection(option.id, enabled: !selected)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.caption.weight(.semibold))
                Text(option.title)
                    .font(.caption.weight(selected ? .semibold : .regular))
            }
            .foregroundColor(selected ? Theme.accent : .primary.opacity(0.7))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(selected ? Theme.accentSoft : Color.primary.opacity(0.05))
            .overlay(
                Capsule().strokeBorder(
                    selected ? Theme.accent.opacity(0.35) : Color.primary.opacity(0.08),
                    lineWidth: 1
                )
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 相册统计卡片
    @ViewBuilder
    private var statsCard: some View {
        if !sorter.albumPhotoCounts.isEmpty {
            VStack(spacing: 0) {
                Button(action: {
                    isStartIndexFocused = false
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isStatsExpanded.toggle()
                    }
                }) {
                    HStack {
                        Label("相册统计", systemImage: "chart.pie.fill")
                            .font(.headline)
                        Spacer()
                        Text("\(sorter.albumPhotoCounts.count) 个相册")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Image(systemName: isStatsExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)

                if isStatsExpanded {
                    Divider()
                        .padding(.vertical, 12)
                    statsDetailList
                }
            }
            .cardStyle()
        }
    }

    private var statsDetailList: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(
                    sorter.albumPhotoCounts
                        .sorted { lhs, rhs in
                            if lhs.value != rhs.value { return lhs.value > rhs.value }
                            return lhs.key < rhs.key
                        },
                    id: \.key
                ) { name, count in
                    HStack(spacing: 10) {
                        Text(name)
                            .font(.subheadline)
                            .lineLimit(1)
                        Spacer()
                        Text("\(count) 张")
                            .font(.subheadline.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 1)
                }
            }
        }
    }

    // MARK: - 操作按钮
    @ViewBuilder
    private var actionArea: some View {
        Group {
            if !sorter.isRunning {
                if sorter.status == "等待开始" || sorter.status.contains("完成") || sorter.status.contains("权限") {
                    startButtons
                } else {
                    resumeResetButtons
                }
            } else {
                pauseButton
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    @ViewBuilder
    private var startButtons: some View {
        VStack(spacing: 10) {
            Button(action: {
                isStartIndexFocused = false
                sorter.start()
            }) {
                Label("开始自动归类", systemImage: "play.circle.fill")
                    .font(.title2.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .tint(Theme.accent)

            Button(action: {
                isStartIndexFocused = false
                sorter.startFromIndex()
            }) {
                Label("从第 \(sorter.startIndex + 1) 张开始", systemImage: "flag.fill")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
            }
            .tint(Theme.warning)
            .disabled(sorter.startIndex < 0)
        }
    }

    @ViewBuilder
    private var resumeResetButtons: some View {
        HStack(spacing: 10) {
            Button(action: {
                isStartIndexFocused = false
                sorter.resume()
            }) {
                Label("继续处理", systemImage: "play.fill")
                    .font(.title2.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .tint(Theme.success)

            Button(action: {
                isStartIndexFocused = false
                sorter.stopAndReset()
            }) {
                Label("结束扫描", systemImage: "stop.fill")
                    .font(.title2.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .tint(Theme.danger)
        }
    }

    @ViewBuilder
    private var pauseButton: some View {
        Button(action: {
            isStartIndexFocused = false
            sorter.pause()
        }) {
            Label("暂停扫描", systemImage: "pause.fill")
                .font(.title2.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .tint(Theme.warning)
    }

    // MARK: - 一键处理
    @ViewBuilder
    private var utilityArea: some View {
        if !sorter.isRunning {
            screenshotProgressCard
            processScreenshotsButton
            cleanupProgressCard
            moveToCleanupButton
        }
    }

    @ViewBuilder
    private var screenshotProgressCard: some View {
        if sorter.screenshotProcessingTotal > 0 {
            VStack(spacing: 10) {
                HStack {
                    Text("处理未分类截图")
                        .font(.headline)
                    Spacer()
                }
                progressBar(
                    progress: progressFraction(
                        count: sorter.screenshotProcessingCount,
                        total: sorter.screenshotProcessingTotal
                    ),
                    color: .purple,
                    height: 8
                )
                HStack {
                    Text("正在处理：\(sorter.screenshotProcessingCount)/\(sorter.screenshotProcessingTotal) 张")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
            .cardStyle()
        }
    }

    @ViewBuilder
    private var cleanupProgressCard: some View {
        if sorter.cleanupProcessingTotal > 0 {
            VStack(spacing: 10) {
                HStack {
                    Text("移动到可清理相册")
                        .font(.headline)
                    Spacer()
                }
                progressBar(
                    progress: progressFraction(
                        count: sorter.cleanupProcessingCount,
                        total: sorter.cleanupProcessingTotal
                    ),
                    color: Theme.danger,
                    height: 8
                )
                HStack {
                    Text("正在移动：\(sorter.cleanupProcessingCount)/\(sorter.cleanupProcessingTotal) 张")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
            .cardStyle()
        }
    }

    private func progressFraction(count: Int, total: Int) -> Double {
        guard total > 0 else { return 0 }
        return Double(min(count, total)) / Double(total)
    }

    private func progressBar(progress: Double, color: Color, height: CGFloat) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.75), color],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(0, geo.size.width * min(1, progress)))
                    .animation(.linear(duration: 0.2), value: progress)
            }
        }
        .frame(height: height)
    }

    @ViewBuilder
    private var processScreenshotsButton: some View {
        Button(action: {
            isStartIndexFocused = false
            sorter.status = "正在处理未分类截图..."
            sorter.moveUncategorizedScreenshotsToAlbum { count in
                if count > 0 {
                    sorter.status = "✅ 已将 \(count) 张未分类截图移入相册"
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                } else {
                    sorter.status = "ℹ️ 没有未分类的截图"
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    sorter.screenshotProcessingTotal = 0
                    sorter.screenshotProcessingCount = 0
                }
            }
        }) {
            Label("一键处理未分类截图", systemImage: "photo.on.rectangle")
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
        }
        .tint(.purple)
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    @ViewBuilder
    private var moveToCleanupButton: some View {
        Button(action: {
            isStartIndexFocused = false
            sorter.status = "正在将照片移入可清理相册..."
            sorter.moveSelectedAlbumPhotosToCleanupAlbum { count in
                if count > 0 {
                    sorter.status = "✅ 已将 \(count) 张照片移入可清理相册"
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                } else {
                    sorter.status = "ℹ️ 没有需要清理的照片或未选择规则"
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    sorter.cleanupProcessingTotal = 0
                    sorter.cleanupProcessingCount = 0
                }
            }
        }) {
            Label("一键移动到可清理相册", systemImage: "trash")
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
        }
        .tint(Theme.danger)
        .buttonStyle(.bordered)
        .controlSize(.large)
    }
}

// MARK: - 滚动状态观察器
/// 嵌入 SwiftUI ScrollView 的背景，通过 KVO 观察底层 UIScrollView，
/// 在用户拖动/减速滚动期间回调 onScroll。
/// 用于扫描时暂停 OCR，让出 CPU/GPU 给 UI。
private struct ScrollStateObserver: UIViewRepresentable {
    let onScroll: (Bool) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isHidden = true
        DispatchQueue.main.async { [weak view] in
            guard let view else { return }
            let observer = context.coordinator
            observer.install(on: view)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onScroll: onScroll) }

    final class Coordinator: NSObject {
        private let onScroll: (Bool) -> Void
        private var observing: UIScrollView?
        private var isTracking = false

        init(onScroll: @escaping (Bool) -> Void) {
            self.onScroll = onScroll
        }

        func install(on view: UIView) {
            guard observing == nil else { return }
            if let scroll = enclosingScrollView(from: view) {
                observing = scroll
                scroll.addObserver(self, forKeyPath: #keyPath(UIScrollView.contentOffset), options: [.new], context: nil)
                scroll.addObserver(self, forKeyPath: #keyPath(UIScrollView.isTracking), options: [.new], context: nil)
                scroll.addObserver(self, forKeyPath: #keyPath(UIScrollView.isDecelerating), options: [.new], context: nil)
                scroll.panGestureRecognizer.addTarget(self, action: #selector(panChanged(_:)))
            }
        }

        @objc private func panChanged(_ pan: UIPanGestureRecognizer) {
            // 手指刚接触 / 拖动 / 即将减速 → 滚动中；手指离开且减速结束 → 停止
            let state = pan.state
            let moving = (state == .began || state == .changed || state == .ended) ||
                         (observing?.isDecelerating ?? false)
            updateState(moving)
        }

        override func observeValue(
            forKeyPath keyPath: String?,
            of object: Any?,
            change: [NSKeyValueChangeKey: Any]?,
            context: UnsafeMutableRawPointer?
        ) {
            guard let scroll = object as? UIScrollView else { return }
            if keyPath == #keyPath(UIScrollView.contentOffset) {
                if scroll.isTracking || scroll.isDecelerating {
                    updateState(true)
                }
            } else if keyPath == #keyPath(UIScrollView.isTracking) ||
                        keyPath == #keyPath(UIScrollView.isDecelerating) {
                let moving = scroll.isTracking || scroll.isDecelerating
                updateState(moving)
            }
        }

        private var lastState: Bool?
        private func updateState(_ moving: Bool) {
            guard moving != lastState else { return }
            lastState = moving
            onScroll(moving)
        }

        private func enclosingScrollView(from view: UIView) -> UIScrollView? {
            var superview = view.superview
            while let sv = superview {
                if let scroll = sv as? UIScrollView { return scroll }
                superview = sv.superview
            }
            return nil
        }

        deinit {
            if let scroll = observing {
                scroll.removeObserver(self, forKeyPath: #keyPath(UIScrollView.contentOffset))
                scroll.removeObserver(self, forKeyPath: #keyPath(UIScrollView.isTracking))
                scroll.removeObserver(self, forKeyPath: #keyPath(UIScrollView.isDecelerating))
            }
        }
    }
}

// MARK: - 主题

private enum Theme {
    static let background = Color(uiColor: UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(red: 0.09, green: 0.09, blue: 0.085, alpha: 1)
            : UIColor(red: 0.958, green: 0.953, blue: 0.937, alpha: 1)
    })

    static let card = Color(uiColor: UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(red: 0.135, green: 0.135, blue: 0.13, alpha: 1)
            : UIColor(red: 1, green: 1, blue: 1, alpha: 1)
    })

    static let accent = Color(uiColor: UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(red: 0.42, green: 0.75, blue: 0.63, alpha: 1)
            : UIColor(red: 0.09, green: 0.45, blue: 0.36, alpha: 1)
    })

    static let accentSoft = accent.opacity(0.13)

    static let success = Color(uiColor: UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(red: 0.4, green: 0.75, blue: 0.5, alpha: 1)
            : UIColor(red: 0.15, green: 0.58, blue: 0.33, alpha: 1)
    })

    static let warning = Color(uiColor: UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(red: 0.92, green: 0.68, blue: 0.32, alpha: 1)
            : UIColor(red: 0.84, green: 0.55, blue: 0.12, alpha: 1)
    })

    static let danger = Color(uiColor: UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(red: 0.9, green: 0.42, blue: 0.4, alpha: 1)
            : UIColor(red: 0.82, green: 0.25, blue: 0.24, alpha: 1)
    })
}

private extension View {
    func cardStyle() -> some View {
        self
            .padding(16)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
