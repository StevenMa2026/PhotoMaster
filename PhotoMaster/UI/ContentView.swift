import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var sorter = PhotoSorter()
    @State private var isStatsExpanded = false
    @FocusState private var isStartIndexFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 30) {
                    headerView
                    progressSection
                    ruleSelectionSection
                    Spacer(minLength: 20)
                    statsSection
                    actionButtonsSection
                    utilityButtonsSection
                    Spacer(minLength: 40)
                }
                .padding(.top, 20)
            }
        }
        .navigationBarHidden(true)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            if sorter.isRunning {
                sorter.pause()
            }
        }
        .onTapGesture {
            isStartIndexFocused = false
        }
    }

    // MARK: - 标题与状态
    @ViewBuilder
    private var headerView: some View {
        VStack(spacing: 10) {
            Text("智能相册归类")
                .font(.largeTitle)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(sorter.status)
                .font(.title2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .onChange(of: sorter.status) {
                    if sorter.status == "✅ 全部处理完成" {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
                }
        }
        .padding(.horizontal)
    }

    // MARK: - 进度条
    @ViewBuilder
    private var progressSection: some View {
        if sorter.totalCount > 0 {
            VStack(spacing: 8) {
                ProgressView(
                    value: Double(min(sorter.processedCount, sorter.totalCount)),
                    total: Double(sorter.totalCount)
                )
                .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                .scaleEffect(x: 1, y: 1.5, anchor: .center)

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
            .padding(.horizontal)
        }
    }

    // MARK: - 规则选择
    @ViewBuilder
    private var ruleSelectionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ruleSelectionHeader
            scanScopeRow
            startIndexRow
            ruleGroupsList
        }
    }

    @ViewBuilder
    private var ruleSelectionHeader: some View {
        HStack {
            Text("执行规则")
                .font(.headline)
            Spacer()
            Button("全选") {
                isStartIndexFocused = false
                sorter.selectAllRules()
            }
            .font(.caption)
            Button("清空") {
                isStartIndexFocused = false
                sorter.clearAllRules()
            }
            .font(.caption)
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var scanScopeRow: some View {
        HStack {
            Text("扫描范围")
                .font(.subheadline)
            Spacer()
            Picker("扫描范围", selection: $sorter.scanScope) {
                ForEach(PhotoSorter.ScanScope.allCases) { scope in
                    Text(scope.description).tag(scope)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var startIndexRow: some View {
        HStack {
            Text("从第几张开始")
                .font(.subheadline)
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
        .padding(.horizontal)
    }

    @ViewBuilder
    private var ruleGroupsList: some View {
        VStack(spacing: 16) {
            ForEach(sorter.ruleGroups, id: \.title) { group in
                ruleGroupView(group)
            }
        }
        .padding(.bottom, 20)
    }

    @ViewBuilder
    private func ruleGroupView(_ group: PhotoSorter.RuleGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(group.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Button("全选") {
                    isStartIndexFocused = false
                    sorter.selectGroupRules(groupTitle: group.title)
                }
                .font(.caption)
                Button("清空") {
                    isStartIndexFocused = false
                    sorter.clearGroupRules(groupTitle: group.title)
                }
                .font(.caption)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 8) {
                ForEach(group.rules) { option in
                    ruleOptionButton(option)
                }
            }
        }
        .padding(.vertical, 4)
        .border(Color.gray.opacity(0.2), width: 1)
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func ruleOptionButton(_ option: PhotoSorter.RuleOption) -> some View {
        let selected = sorter.selectedRuleIDs.contains(option.id)
        Button {
            isStartIndexFocused = false
            sorter.toggleRuleSelection(option.id, enabled: !selected)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                Text(option.title)
            }
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(selected ? Color.blue.opacity(0.12) : Color.gray.opacity(0.1))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 相册统计浮窗
    @ViewBuilder
    private var statsSection: some View {
        if !sorter.albumPhotoCounts.isEmpty {
            VStack {
                Button(action: {
                    isStartIndexFocused = false
                    withAnimation {
                        isStatsExpanded.toggle()
                    }
                }) {
                    HStack {
                        Text("相册统计 (\(sorter.albumPhotoCounts.count))")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Spacer()
                        Image(systemName: isStatsExpanded ? "chevron.up" : "chevron.down")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)

                if isStatsExpanded {
                    statsDetailList
                }
            }
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private var statsDetailList: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(
                    sorter.albumPhotoCounts
                        .sorted { lhs, rhs in
                            if lhs.value != rhs.value { return lhs.value > rhs.value }
                            return lhs.key < rhs.key
                        },
                    id: \.key
                ) { name, count in
                    HStack {
                        Text(name)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                        Text("\(count)")
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
        .padding(.horizontal, 8)
    }

    // MARK: - 操作按钮组
    @ViewBuilder
    private var actionButtonsSection: some View {
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
        .padding(.horizontal)
    }

    @ViewBuilder
    private var startButtons: some View {
        VStack(spacing: 12) {
            Button(action: {
                isStartIndexFocused = false
                sorter.start()
            }) {
                Label("🚀 开始自动归类", systemImage: "play.circle.fill")
                    .font(.title2)
                    .frame(maxWidth: .infinity)
            }
            .tint(.blue)

            Button(action: {
                isStartIndexFocused = false
                sorter.startFromIndex()
            }) {
                Label("📍 从第 \(sorter.startIndex + 1) 张开始", systemImage: "play.circle")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
            }
            .tint(.orange)
            .disabled(sorter.startIndex < 0)
        }
    }

    @ViewBuilder
    private var resumeResetButtons: some View {
        HStack(spacing: 20) {
            Button(action: {
                isStartIndexFocused = false
                sorter.resume()
            }) {
                Label("▶️ 继续处理", systemImage: "play.fill")
                    .font(.title2)
                    .frame(maxWidth: .infinity)
            }
            .tint(.green)

            Button(action: {
                isStartIndexFocused = false
                sorter.stopAndReset()
            }) {
                Label("⏹️ 结束扫描", systemImage: "stop.fill")
                    .font(.title2)
                    .frame(maxWidth: .infinity)
            }
            .tint(.red)
        }
    }

    @ViewBuilder
    private var pauseButton: some View {
        Button(action: {
            isStartIndexFocused = false
            sorter.pause()
        }) {
            Label("⏸️ 暂停扫描", systemImage: "pause.fill")
                .font(.title2)
                .frame(maxWidth: .infinity)
        }
        .tint(.red)
    }

    // MARK: - 一键处理按钮
    @ViewBuilder
    private var utilityButtonsSection: some View {
        if !sorter.isRunning {
            screenshotProgressBar
            processScreenshotsButton
            cleanupProgressBar
            moveToCleanupButton
        }
    }

    @ViewBuilder
    private var screenshotProgressBar: some View {
        if sorter.screenshotProcessingTotal > 0 {
            VStack(spacing: 8) {
                ProgressView(
                    value: Double(min(sorter.screenshotProcessingCount, sorter.screenshotProcessingTotal)),
                    total: Double(sorter.screenshotProcessingTotal)
                )
                .progressViewStyle(LinearProgressViewStyle(tint: .purple))
                .scaleEffect(x: 1, y: 1.5, anchor: .center)

                HStack {
                    Text("正在处理：\(sorter.screenshotProcessingCount)/\(sorter.screenshotProcessingTotal) 张")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
            .padding(.horizontal)
        }
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
            Label("📷 一键处理未分类截图", systemImage: "folder.badge.plus")
                .font(.subheadline)
                .frame(maxWidth: .infinity)
        }
        .tint(.purple)
        .buttonStyle(.bordered)
        .controlSize(.large)
        .padding(.horizontal)
    }

    @ViewBuilder
    private var cleanupProgressBar: some View {
        if sorter.cleanupProcessingTotal > 0 {
            VStack(spacing: 8) {
                ProgressView(
                    value: Double(min(sorter.cleanupProcessingCount, sorter.cleanupProcessingTotal)),
                    total: Double(sorter.cleanupProcessingTotal)
                )
                .progressViewStyle(LinearProgressViewStyle(tint: .red))
                .scaleEffect(x: 1, y: 1.5, anchor: .center)

                HStack {
                    Text("正在移动：\(sorter.cleanupProcessingCount)/\(sorter.cleanupProcessingTotal) 张")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
            .padding(.horizontal)
        }
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
            Label("🗑️ 一键移动到可清理相册", systemImage: "trash")
                .font(.subheadline)
                .frame(maxWidth: .infinity)
        }
        .tint(.red)
        .buttonStyle(.bordered)
        .controlSize(.large)
        .padding(.horizontal)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
