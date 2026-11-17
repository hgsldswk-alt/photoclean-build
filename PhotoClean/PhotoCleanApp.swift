import SwiftUI
import UIKit

@main @MainActor struct PhotoCleanApp: App {
    @StateObject private var model = AppModel()
    var body: some Scene {
        WindowGroup { RootView().environmentObject(model).environmentObject(model.purchases).tint(Palette.accent) }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var phase
    var body: some View {
        NavigationStack(path: $model.path) {
            Group {
                if !model.ready { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).background(Palette.background) }
                else if model.access == .denied || model.access == .restricted { DeniedView() }
                else if !model.data.onboarded || model.access == .notDetermined { OnboardingView() }
                else { HomeView() }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .months: MonthsView()
                case .swipe(let month): SwipeView(month: month)
                case .category(let category): CategoryView(category: category)
                }
            }
        }
        .foregroundStyle(Palette.ink)
        .sheet(isPresented: Binding(get: { model.modal != nil }, set: { if !$0 { model.modal = nil } })) { ModalHost() }
        .alert(L.t("提示"), isPresented: Binding(get: { model.message != nil && model.modal == nil }, set: { if !$0 { model.message = nil } })) {
            Button(L.t("知道了")) { model.message = nil }.accessibilityIdentifier("dismissMessage")
        } message: { Text(model.message ?? "") }
        .confirmationDialog(L.t("每月提醒整理一次？"), isPresented: $model.reminderPrompt, titleVisibility: .visible) {
            Button(L.t("开启每月提醒")) { Task { await model.setReminder(true) } }.accessibilityIdentifier("enableReminderOffer")
            Button(L.t("以后再说"), role: .cancel) {}.accessibilityIdentifier("laterReminder")
        } message: { Text(Launch.isFree ? L.t("每月 1 日 20:00 提醒，随时可关闭。") : L.t("每月 1 日 20:00 提醒。买断后可用，随时可关闭。")) }
        .task { await model.start() }
        .onChange(of: phase) { _, next in if next == .active { Task { await model.becameActive() } } }
        .onOpenURL { model.handleURL($0) }
    }
}

struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Image(systemName: "rectangle.stack").font(.system(size: 64, weight: .ultraLight)).padding(.top, 60)
                Text(L.t("留下喜欢的，给手机一点空间。")).font(.system(size: 34, weight: .bold))
                Text(L.t("左右滑动整理，找出相似照片、截图和大视频。需要相册权限才能查看和整理你选择的照片。"))
                Label(L.t("照片只在手机里处理，不上传。"), systemImage: "lock.shield")
                Label(L.t("删除后进入系统「最近删除」，30 天内可找回。"), systemImage: "arrow.uturn.backward")
                Button(L.t("开始整理")) { Task { await model.begin() } }.buttonStyle(SolidButton()).accessibilityIdentifier("startCleaning")
                Text(Launch.isFree ? L.t("没有广告，所有功能免费使用。") : L.t("无广告。买断一次，永久使用；免费也能每天整理。"))
                    .font(.footnote).foregroundStyle(Palette.sub)
            }.padding(28)
        }.background(Palette.background).navigationTitle(L.t("相册清理"))
    }
}

struct DeniedView: View {
    @Environment(\.openURL) private var openURL
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 20) {
                        PhotoStackIllustration(locked: true).frame(maxWidth: .infinity).padding(.vertical, 10)
                        Text(L.t("允许访问相册，才能开始整理。")).font(.title2.bold())
                        Text(L.t("照片只在手机里处理。你可以允许全部访问，也可以只选择部分照片。"))
                            .foregroundStyle(Palette.sub)
                        Button(L.t("去设置打开")) {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }.buttonStyle(SolidButton()).accessibilityIdentifier("openPhotoSettings")
                    }.panel()
                }.padding(24).frame(minHeight: geometry.size.height)
            }
        }.background(Palette.background).navigationTitle(L.t("相册清理"))
    }
}

struct ModalHost: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Button {
                    if model.modal == .paywall { model.dismissPaywall() }
                    else if model.modal == .celebration || model.modal == .share { model.finishCelebration() }
                    else { model.modal = nil }
                } label: { Image(systemName: "xmark").frame(width: 44, height: 44).contentShape(Rectangle()) }
                    .accessibilityLabel(L.t("关闭")).accessibilityIdentifier("closeSheet").disabled(model.deleting)
            }.padding(.horizontal, 20).padding(.top, 8)
            Divider().overlay(Palette.line)
            Group {
                switch model.modal {
                case .review: ReviewView()
                case .celebration: CelebrationView()
                case .share: SharingView()
                case .paywall: PaywallView()
                case .settings: SettingsView()
                case nil: Color.clear
                }
            }
        }.background(Palette.background).foregroundStyle(Palette.ink).interactiveDismissDisabled(model.deleting)
        .alert(L.t("提示"), isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button(L.t("知道了")) { model.message = nil }.accessibilityIdentifier("dismissMessage")
        } message: { Text(model.message ?? "") }
    }
    private var title: String {
        switch model.modal {
        case .review: return L.t("确认待删除")
        case .celebration: return L.t("整理完成")
        case .share: return L.t("分享这份清爽")
        case .paywall: return L.t("一次买断，轻松整理")
        case .settings: return L.t("设置")
        case nil: return ""
        }
    }
}
