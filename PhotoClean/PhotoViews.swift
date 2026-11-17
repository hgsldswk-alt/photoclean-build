import SwiftUI
import UIKit
import AVKit
import PhotosUI
import Photos

struct PhotoThumbnail: View {
    @EnvironmentObject private var model: AppModel
    let asset: PhotoAsset
    var network = false
    var large = false
    var fit = false
    @State private var image: UIImage?
    @State private var loading = true
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Palette.line.opacity(0.4)
                if let image {
                    Image(uiImage: image).resizable().aspectRatio(contentMode: fit ? .fit : .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                } else if loading { ProgressView().tint(Palette.accent).accessibilityLabel(L.t("正在载入照片…")) }
                else { Image(systemName: "icloud.slash").foregroundStyle(Palette.sub).accessibilityLabel(L.t("照片暂不可用，请重试。")) }
            }
        }
        .task(id: asset.cacheKey + String(large) + String(network)) {
            loading = true; image = nil
            let result = await model.library.thumbnail(asset, size: CGSize(width: large ? 1200 : 300, height: large ? 1600 : 400), network: network)
            guard !Task.isCancelled else { return }; image = result; loading = false
        }
        .accessibilityLabel(asset.created.formatted(date: .abbreviated, time: .shortened))
    }
}

private struct LivePhotoDisplay: UIViewRepresentable {
    let photo: PHLivePhoto
    func makeUIView(context: Context) -> PHLivePhotoView {
        let view = PHLivePhotoView(); view.contentMode = .scaleAspectFit; view.livePhoto = photo; view.isMuted = true; return view
    }
    func updateUIView(_ view: PHLivePhotoView, context: Context) { if view.livePhoto !== photo { view.livePhoto = photo } }
}

struct PhotoViewer: View {
    @EnvironmentObject private var model: AppModel
    let asset: PhotoAsset
    @State private var player: AVPlayer?
    @State private var livePhoto: PHLivePhoto?
    @State private var mediaLoading = false
    var body: some View {
        ZStack {
            PhotoThumbnail(asset: asset, network: true, large: true, fit: true)
            if let player { VideoPlayer(player: player) }
            if let livePhoto { LivePhotoDisplay(photo: livePhoto) }
            if mediaLoading { ProgressView().padding(12).background(.regularMaterial, in: Circle()) }
        }
        .task(id: asset.cacheKey) {
            player?.pause(); player = nil; livePhoto = nil
            if !model.demo && (asset.isVideo || asset.live) {
                mediaLoading = true
                if asset.isVideo {
                    let item = await model.library.playerItem(asset)
                    guard !Task.isCancelled else { return }
                    if let item { let p = AVPlayer(playerItem: item); p.isMuted = true; player = p; p.play() }
                } else {
                    let live = await model.library.livePhoto(asset)
                    guard !Task.isCancelled else { return }; livePhoto = live
                }
                mediaLoading = false
            }
        }
        .onDisappear { player?.pause(); player = nil }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { notification in
            if let item = notification.object as? AVPlayerItem, item === player?.currentItem { player?.seek(to: .zero); player?.play() }
        }
    }
}

struct AssetBadges: View {
    let asset: PhotoAsset
    var body: some View {
        HStack(spacing: 10) {
            if asset.favorite { Label(L.t("收藏"), systemImage: "heart.fill") }
            if asset.live { Label(L.t("实况"), systemImage: "livephoto") }
            if asset.isVideo { Label(L.t("视频"), systemImage: "video.fill") }
        }.font(.caption.weight(.medium)).foregroundStyle(Palette.sub)
    }
}

struct SwipeView: View {
    @EnvironmentObject private var model: AppModel
    let month: String
    @State private var session = SwipeSession()
    @State private var offset: CGFloat = 0
    @State private var moving = false
    private var photos: [PhotoAsset] { session.photos }
    private var index: Int { session.index }
    private var initialReviewed: Int { session.initialReviewed }
    private var current: PhotoAsset? { session.current }
    private var monthAssets: [PhotoAsset] { model.months.first { $0.id == month }?.assets ?? [] }
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 18) {
                    if let photo = current {
                        HStack {
                            Text(photo.created.formatted(date: .abbreviated, time: .omitted)).font(.subheadline)
                            Spacer(); Text(Bytes.label([photo])).font(.footnote).foregroundStyle(Palette.sub)
                        }
                        ZStack {
                            ForEach([2, 1], id: \.self) { depth in
                                if photos.indices.contains(index + depth) {
                                    PhotoThumbnail(asset: photos[index + depth])
                                        .clipShape(RoundedRectangle(cornerRadius: 24))
                                        .scaleEffect(depth == 1 ? 0.94 : 0.88, anchor: .bottom)
                                        .offset(y: CGFloat(depth) * 10)
                                        .accessibilityHidden(true).allowsHitTesting(false)
                                }
                            }
                            PhotoViewer(asset: photo).id(photo.id).clipShape(RoundedRectangle(cornerRadius: 24))
                                .overlay(RoundedRectangle(cornerRadius: 24).stroke(offset < 0 ? Palette.delete : Palette.accent, lineWidth: min(5, abs(offset) / 24)))
                                .overlay(alignment: offset < 0 ? .topLeading : .topTrailing) {
                                    if abs(offset) > 15 {
                                        Text(offset < 0 ? L.t("待删除") : L.t("保留")).font(.title2.bold()).padding(18)
                                            .foregroundStyle(offset < 0 ? Palette.delete : Palette.accent)
                                            .background(.regularMaterial, in: Capsule()).padding(20).opacity(Double(min(1, abs(offset)/90)))
                                    }
                                }
                                .rotationEffect(.degrees(Double(offset / 24))).offset(x: offset)
                                .simultaneousGesture(DragGesture(minimumDistance: 25)
                                    .onChanged { value in
                                        if !moving && abs(value.translation.width) > abs(value.translation.height) { offset = value.translation.width }
                                    }
                                    .onEnded { value in
                                        guard !moving else { return }
                                        if abs(value.translation.width) > 80 && abs(value.translation.width) > abs(value.translation.height) { commit(delete: value.translation.width < 0) }
                                        else { withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { offset = 0 } }
                                    })
                                .accessibilityIdentifier("swipeCard")
                        }.frame(height: max(240, min(540, geometry.size.height - 250))).padding(.bottom, 20)
                        AssetBadges(asset: photo)
                        Text(L.t("左滑待删除，右滑保留")).font(.footnote).foregroundStyle(Palette.sub)
                        HStack(spacing: 14) {
                            Button { commit(delete: true) } label: { Label(L.t("待删除"), systemImage: "trash") }
                                .buttonStyle(SolidButton(destructive: true)).accessibilityIdentifier("swipeDelete")
                            Button { commit(delete: false) } label: { Label(L.t("保留"), systemImage: "checkmark") }
                                .buttonStyle(SolidButton()).accessibilityIdentifier("swipeKeep")
                        }.disabled(moving)
                    } else if session.loading(fetching: model.fetching) {
                        ProgressView(L.t("正在读取相册…"))
                            .frame(maxWidth: .infinity, minHeight: 240).accessibilityIdentifier("swipeLoading")
                    } else {
                        EmptyState(title: L.t("这个月整理好了。"))
                        Button(L.t("复核待删除")) { model.modal = .review }.buttonStyle(SolidButton()).accessibilityIdentifier("endReview")
                        Button(L.t("分享本月整理")) {
                            let total = model.data.stats.monthly[CalendarKey.month(Date())] ?? CleanupTotal()
                            model.receipt = CleanupReceipt(count: total.count, bytes: total.bytes, date: Date(), before: total.bytes + Bytes.total(model.assets))
                            model.modal = .share
                        }.buttonStyle(QuietButton()).accessibilityIdentifier("shareMonth")
                    }
                    HStack {
                        Button { undo() } label: { Label(L.t("撤销"), systemImage: "arrow.uturn.backward") }
                            .disabled(session.history.isEmpty || moving).accessibilityIdentifier("swipeUndo")
                        Spacer()
                        Text(L.f("%@ / %@", (initialReviewed + index).formatted(), (initialReviewed + photos.count).formatted())).monospacedDigit().font(.footnote).accessibilityIdentifier("swipeProgress")
                        Spacer()
                        Button(L.t("复核")) { model.modal = .review }.accessibilityIdentifier("swipeReview")
                    }.font(.subheadline)
                }.padding(22)
            }
        }.background(Palette.background).navigationTitle(CalendarKey.monthTitle(month)).navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .onAppear { loadPhotos() }
        .onChange(of: monthAssets) { _, _ in loadPhotos() }
        .onChange(of: model.fetching) { _, _ in loadPhotos() }
        .onDisappear { model.library.preheat([]) }
    }
    private func loadPhotos() {
        session.sync(monthAssets, reviewed: model.data.reviewed[month] ?? [], fetching: model.fetching)
        preheat()
    }
    private func commit(delete: Bool) {
        guard !moving, let photo = current else { return }; moving = true
        let wasBasket = model.data.basket.contains(photo.id)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) { offset = delete ? -480 : 480 }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            guard session.advance(photo.id, wasBasket: wasBasket) else { offset = 0; moving = false; return }
            model.mark(photo, month: month, delete: delete)
            offset = 0; moving = false; preheat()
            if index == photos.count && !model.fetching { model.modal = .review }
        }
    }
    private func undo() {
        guard let step = session.undo() else { return }
        model.undo(step.photo, month: month, wasBasket: step.basket); offset = 0; preheat()
    }
    private func preheat() {
        let start = max(0, index - 3), end = min(photos.count, index + 4)
        model.library.preheat(start < end ? Array(photos[start..<end]) : [])
    }
}
