import SwiftUI
import UIKit

struct ReviewView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(L.f("待删除 %@ 张", model.basketAssets.count.formatted())).font(.title2.bold()).accessibilityIdentifier("basketCount")
                    Text(L.t("点照片可移出待删除。确认后，系统还会询问是否允许删除。"))
                        .font(.footnote).foregroundStyle(Palette.sub)
                    if model.basketAssets.isEmpty { EmptyState(title: L.t("待删除里没有照片。")) }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: typeSize >= .xxLarge ? 2 : 3), spacing: 8) {
                        ForEach(model.basketAssets) { photo in
                            Button { model.toggleBasket(photo.id) } label: {
                                PhotoThumbnail(asset: photo).frame(height: 125).clipped().clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(alignment: .topTrailing) { Image(systemName: "minus.circle.fill").font(.title3).foregroundStyle(.white, Palette.primary).padding(7) }
                            }.buttonStyle(.plain).accessibilityLabel(L.t("移出待删除"))
                                .accessibilityIdentifier("remove-" + photo.id).disabled(model.deleting)
                        }
                    }
                    Text(L.t("iCloud 照片会从所有同步设备删除。删除后 30 天内，可从「最近删除」恢复。"))
                        .font(.footnote).foregroundStyle(Palette.sub)
                    Text(L.t("分类可能重叠，空间已去重；最终由你确认。"))
                        .font(.caption).foregroundStyle(Palette.sub)
                }.padding(22)
            }
            VStack(spacing: 10) {
                if model.deleting { ProgressView(L.t("等待系统确认…")).accessibilityIdentifier("deletingProgress") }
                Button(L.f("删除 %@ 张 · 腾出 %@", model.basketAssets.count.formatted(), Bytes.label(model.basketAssets))) {
                    Task { await model.attemptDelete() }
                }.buttonStyle(SolidButton(destructive: true)).disabled(model.basketAssets.isEmpty || model.deleting).accessibilityIdentifier("confirmDelete")
                if !model.pro { Text(L.f("今日还可免费删除 %@ 张", model.remaining.formatted())).font(.caption).foregroundStyle(Palette.sub) }
            }.padding(22)
        }
        .alert(L.t("删除会同步到 iCloud"), isPresented: $model.cloudPrompt) {
            Button(L.t("继续删除"), role: .destructive) { Task { await model.acceptCloudWarning() } }.accessibilityIdentifier("confirmCloudDeletion")
            Button(L.t("取消"), role: .cancel) {}.accessibilityIdentifier("cancelCloudDeletion")
        } message: { Text(L.t("iCloud 照片会从所有同步设备删除。删除后 30 天内，可从「最近删除」恢复。")) }
    }
}

struct CelebrationView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress = 0.0
    @State private var challengeCopied = false
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 24) {
                    result
                    StorageComparison(before: model.receipt.before, removed: model.receipt.bytes)
                        .padding(18).background(Palette.card, in: RoundedRectangle(cornerRadius: 18))
                    keptStrip
                    VStack(alignment: .leading, spacing: 12) {
                        Label(L.t("去「最近删除」清空后，才会立即释放空间。"), systemImage: "info.circle")
                        Text(L.t("误删了？去 照片 → 相簿 → 最近删除 恢复。未清空时，30 天内可以找回。"))
                    }.font(.footnote).foregroundStyle(Palette.sub).frame(maxWidth: .infinity, alignment: .leading).panel()
                }.padding(24).frame(minHeight: geometry.size.height)
            }
        }.safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 10) {
                Button(L.t("分享这份清爽")) { model.modal = .share }.buttonStyle(SolidButton()).accessibilityIdentifier("openShare")
                Button(L.t("完成")) { model.finishCelebration() }.buttonStyle(QuietButton()).accessibilityIdentifier("finishCleanup")
                Button(challengeCopied ? L.t("挑战口令已复制，发给朋友吧") : L.t("复制挑战口令，叫朋友一起清")) {
                    model.copyChallengeText(model.challengeInvitation)
                    challengeCopied = true
                }.font(.footnote.weight(.medium)).foregroundStyle(Palette.accent).accessibilityIdentifier("copyChallenge")
            }.padding(.horizontal, 24).padding(.vertical, 14).background(Palette.background)
        }.task {
            if reduceMotion { progress = 1; return }
            for step in 0...40 {
                guard !Task.isCancelled else { return }
                withAnimation(.linear(duration: 0.025)) { progress = Double(step) / 40 }
                try? await Task.sleep(for: .milliseconds(25))
            }
        }
    }
    private var result: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle").font(.system(size: 48, weight: .ultraLight))
                .foregroundStyle(Palette.accent).accessibilityHidden(true)
            Text(model.receipt.milestones.isEmpty ? L.t("少一点占用，多一点清爽。") : L.t("又一个值得记住的里程碑。"))
                .font(.title2.bold()).multilineTextAlignment(.center)
            Text(L.t("已整理空间")).font(.subheadline).foregroundStyle(Palette.sub)
            Text(animatedBytes).largeNumber(60).lineLimit(1).minimumScaleFactor(0.4)
                .contentTransition(.numericText()).accessibilityIdentifier("freedBytes")
            Text(L.f("整理了 %@ 张照片", Int(Double(model.receipt.count) * progress).formatted()))
                .font(.subheadline).monospacedDigit().contentTransition(.numericText()).accessibilityIdentifier("deletedCount")
            if !model.receipt.milestones.isEmpty {
                Text(milestoneText).font(.footnote.weight(.semibold)).foregroundStyle(Palette.accent)
            }
        }.frame(maxWidth: .infinity)
    }
    @ViewBuilder private var keptStrip: some View {
        let photos = model.celebrationKeptPhotos
        if !photos.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(L.t("这个月，留下的喜欢")).font(.footnote.weight(.medium)).foregroundStyle(Palette.sub)
                HStack(spacing: 6) {
                    ForEach(photos) { photo in
                        PhotoThumbnail(asset: photo).frame(maxWidth: .infinity).frame(height: 58)
                            .clipped().clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }.accessibilityHidden(true)
            }.accessibilityElement(children: .combine).accessibilityIdentifier("keptPhotos")
        }
    }
    private var animatedBytes: String {
        let bytes = Int64(Double(model.receipt.bytes) * progress)
        let value = Bytes.format(bytes)
        return model.receipt.approximate ? L.f("约 %@", value) : value
    }
    private var milestoneText: String {
        let total = model.data.stats.total
        return L.f("累计整理 %@ 张 · %@", max(total.count, model.receipt.count).formatted(), Bytes.format(max(total.bytes, model.receipt.bytes)))
    }
}
