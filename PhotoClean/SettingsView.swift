import SwiftUI
import UIKit

struct PaywallView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var purchases: PurchaseManager
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PhotoStackIllustration().frame(maxWidth: .infinity).padding(.top, 8)
                Text(L.t("一次付费，永久使用。")).font(.system(size: 30, weight: .bold)).fixedSize(horizontal: false, vertical: true)
                Text(L.f("今日还可免费删除 %@ 张。你可以先删除额度内的照片，其余保留在待删除中，也可以明天继续。", model.remaining.formatted()))
                    .foregroundStyle(Palette.sub).accessibilityIdentifier("quotaExplanation")
                comparison
                VStack(alignment: .leading, spacing: 8) {
                    Label(L.t("没有订阅，不自动续费"), systemImage: "checkmark")
                    Label(L.t("无广告，照片不离开手机"), systemImage: "lock.shield")
                }.font(.footnote).foregroundStyle(Palette.sub)
                if purchases.busy { ProgressView().frame(maxWidth: .infinity) }
                if let error = purchases.error { Text(error).font(.footnote).foregroundStyle(Palette.sub) }
                if let note = purchases.note { Text(note).font(.footnote).foregroundStyle(Palette.sub) }
                if purchases.productLoadFailed && !model.demo {
                    Button(L.t("重新加载价格")) { Task { await purchases.loadProduct() } }
                        .disabled(purchases.loadingProduct || purchases.busy).accessibilityIdentifier("retryProduct")
                }
                Text(L.t("前 30 天不限张数，之后每天免费删除 50 张。扫描、复核与分享始终免费。"))
                    .font(.footnote).foregroundStyle(Palette.sub)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(22)
        }.accessibilityIdentifier("paywall")
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                Button { Task { await purchases.buy() } } label: {
                    HStack(spacing: 8) {
                        Text(purchaseTitle)
                        if purchases.product == nil && !purchases.productLoadFailed {
                            ProgressView().tint(.white).controlSize(.small).accessibilityHidden(true)
                        }
                    }
                }.buttonStyle(SolidButton()).disabled(purchases.busy || purchases.loadingProduct).accessibilityIdentifier("buyPro")
                if model.canDeletePartial {
                    Button(L.f("先删除前 %@ 张", model.partialDeleteCount.formatted())) { Task { await model.deleteRemaining() } }
                        .buttonStyle(QuietButton()).disabled(purchases.busy || model.deleting).accessibilityIdentifier("deleteRemainingQuota")
                    Text(L.t("仅删除本次额度内的照片，其余继续保留在待删除中。"))
                        .font(.caption).foregroundStyle(Palette.sub)
                }
                Button(L.t("明天再来")) { model.dismissPaywall() }.buttonStyle(QuietButton()).accessibilityIdentifier("tomorrow")
                Button(L.t("恢复购买")) { Task { await purchases.restore() } }.frame(maxWidth: .infinity).disabled(purchases.busy).accessibilityIdentifier("restorePurchases")
            }.padding(22).background(Palette.background)
        }
    }
    private var purchaseTitle: String {
        guard let product = purchases.product else { return L.t("买断") }
        return L.f("买断 · %@", product.displayPrice)
    }
    private var comparison: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(L.t("功能")).frame(maxWidth: .infinity, alignment: .leading)
                Text(L.t("免费")).frame(width: 64)
                Text(L.t("买断")).frame(width: 72)
            }.font(.footnote.weight(.semibold)).foregroundStyle(Palette.sub).padding(.bottom, 14)
            comparisonRow(L.t("每天删除"), free: L.t("50 张"), pro: L.t("不限张数"))
            comparisonRow(L.t("扫描和查看"), free: L.t("全部"), pro: L.t("全部"))
            comparisonRow(L.t("小组件与每月提醒"), included: true)
            comparisonRow(L.t("以后的新功能"), included: true)
        }.frame(maxWidth: .infinity, alignment: .leading).panel().accessibilityIdentifier("planComparison")
    }
    private func comparisonRow(_ title: String, free: String = "", pro: String = "", included: Bool = false) -> some View {
        VStack(spacing: 0) {
            Rectangle().fill(Palette.line).frame(height: 0.5)
            HStack(spacing: 8) {
                Text(title).frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                Text(included ? "–" : free).foregroundStyle(Palette.sub).frame(width: 64)
                Group {
                    if included { Image(systemName: "checkmark").accessibilityLabel(L.t("包含")) }
                    else { Text(pro).fixedSize(horizontal: false, vertical: true) }
                }.fontWeight(.semibold).frame(width: 72)
            }.font(.subheadline).padding(.vertical, 14).accessibilityElement(children: .combine)
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var purchases: PurchaseManager
    @Environment(\.openURL) private var openURL
    @State private var activity = false
    @State private var copied = false
    @State private var shareRequested = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !Launch.isFree {
                VStack(alignment: .leading, spacing: 16) {
                    HStack { Text(planTitle).font(.title2.bold()); Spacer(); Image(systemName: "checkmark.seal") }
                    if !model.data.entitlement.purchasedPro { Button(L.t("了解一次买断")) { model.showPaywall() }.buttonStyle(SolidButton()).accessibilityIdentifier("settingsPro") }
                    hairline
                    Button { Task { await purchases.restore() } } label: {
                        Text(L.t("恢复购买")).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                    }
                        .disabled(purchases.busy).accessibilityIdentifier("settingsRestore")
                    if let error = purchases.error { Text(error).font(.footnote).foregroundStyle(Palette.sub) }
                    if let note = purchases.note { Text(note).font(.footnote).foregroundStyle(Palette.sub) }
                }.panel()
                }
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(L.t("每月提醒"), isOn: Binding(get: { model.data.reminderEnabled }, set: { value in Task { await model.setReminder(value) } }))
                        .accessibilityIdentifier("monthlyReminder")
                    hairline
                    Text(Launch.isFree ? L.t("每月 1 日 20:00 提醒，随时可关闭。") : L.t("每月 1 日 20:00 提醒。买断后可用，随时可关闭。"))
                        .font(.footnote).foregroundStyle(Palette.sub)
                }.panel()
                VStack(alignment: .leading, spacing: 14) {
                    Text(L.t("怎么找回误删")).font(.headline)
                    Text(L.t("误删了？去 照片 → 相簿 → 最近删除 恢复。未清空时，30 天内可以找回。"))
                    hairline
                    Text(L.t("去「最近删除」清空后，才会立即释放空间。"))
                }.font(.subheadline).panel()
                VStack(alignment: .leading, spacing: 14) {
                    Text(L.t("隐私说明")).font(.headline)
                    Text(L.t("照片与分析结果只在本机处理，不收集数据，不使用分析服务，不上传照片。浏览 iCloud 照片由系统下载预览；购买由 App Store 处理。"))
                    hairline
                    Text(L.t("语言跟随系统，可在系统设置中更改。"))
                }.font(.subheadline).panel()
                VStack(alignment: .leading, spacing: 18) {
                    Button {
                        model.copyChallengeText(model.challengeInvitation)
                        copied = true
                    } label: {
                        Text(L.t("邀请朋友一起清理")).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                    }
                        .accessibilityIdentifier("inviteFriend")
                    if copied { Text(L.t("邀请文案已复制")).font(.caption).foregroundStyle(Palette.sub) }
                    hairline
                    Button {
                        if model.testing { shareRequested = true }
                        else { activity = true }
                    } label: {
                        Text(L.t("推荐给朋友")).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                    }.accessibilityIdentifier("shareApp")
                    if shareRequested {
                        Text(L.t("分享已请求")).font(.caption).foregroundStyle(Palette.sub)
                            .accessibilityIdentifier("share.requested")
                    }
                    hairline
                    Button {
                        if let url = QRCode.downloadURL, let review = URL(string: url.absoluteString + "?action=write-review") { openURL(review) }
                        else { model.message = L.t("上架后即可在 App Store 评分。") }
                    } label: {
                        Text(L.t("为我们评分")).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                    }.accessibilityIdentifier("rateApp")
                }.frame(maxWidth: .infinity, alignment: .leading).panel()
                Text(L.f("版本 %@", model.version)).font(.footnote).foregroundStyle(Palette.sub)
                    .frame(maxWidth: .infinity).padding(.vertical, 12).accessibilityIdentifier("appVersion")
            }.frame(maxWidth: .infinity, alignment: .leading).padding(22)
        }.accessibilityIdentifier("settingsPage").sheet(isPresented: $activity) { ShareActivity(items: [model.challengeInvitation]) }
    }
    private var planTitle: String {
        if model.data.entitlement.purchasedPro { return L.t("已买断，永久使用") }
        if let left = model.data.entitlement.trialDaysLeft(at: Date()), left > 0 { return L.f("全功能试用 · 还剩 %@ 天", String(left)) }
        return L.t("免费版")
    }
    private var hairline: some View { Rectangle().fill(Palette.line).frame(height: 0.5).accessibilityHidden(true) }
}
