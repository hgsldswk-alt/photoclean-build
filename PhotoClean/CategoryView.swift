import SwiftUI

struct CategoryView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dynamicTypeSize) private var typeSize
    let category: Category
    @State private var selection = GroupSelection()
    @State private var initialized = false
    @State private var preview: PhotoAsset?
    private var grouped: Bool { category == .similar || category == .duplicates }
    private var groups: [PhotoGroup] { category == .similar ? model.analysis.similar : model.analysis.duplicates }
    private var photos: [PhotoAsset] { model.categoryAssets(category) }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if grouped {
                    AnalysisProgressView()
                    Text(L.t("默认保留最好的一张；收藏永远不会预选删除。点击照片可调整。"))
                        .font(.footnote).foregroundStyle(Palette.sub)
                    ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(L.f("第 %@ 组", (index + 1).formatted())).font(.headline)
                                    Text(L.f("%@ 张 · 可整理 %@", group.assets.count.formatted(), Bytes.label(group.assets.filter { selection.selected.contains($0.id) })))
                                        .font(.footnote).foregroundStyle(Palette.sub)
                                }
                                Spacer(minLength: 8)
                                Button(L.t("全部保留")) { selection.keepAll(group) }
                                    .font(.footnote.weight(.semibold)).padding(.vertical, 12)
                                    .accessibilityIdentifier("keepGroup-" + group.id)
                            }
                            LazyVGrid(columns: columns, spacing: 10) {
                                ForEach(group.assets) { photo in tile(photo, best: photo.id == group.bestID) }
                            }
                        }.panel()
                    }
                } else if category == .screenshots {
                    ForEach(AnalysisCore.months(photos)) { month in
                        Text(CalendarKey.monthTitle(month.id)).font(.headline)
                        LazyVGrid(columns: columns, spacing: 10) { ForEach(month.assets) { tile($0) } }
                    }
                } else {
                    Text(L.t("按大小排序，默认不选。点播放可预览。"))
                        .font(.footnote).foregroundStyle(Palette.sub)
                    ForEach(photos) { photo in
                        HStack(spacing: 14) {
                            Button { toggle(photo.id) } label: {
                                HStack {
                                    PhotoThumbnail(asset: photo).frame(width: 76, height: 90).clipped().clipShape(RoundedRectangle(cornerRadius: 12))
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(Bytes.label([photo])).font(.headline)
                                        Text(duration(photo.duration)).font(.subheadline).foregroundStyle(Palette.sub)
                                        Text(photo.created.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(Palette.sub)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: selection.selected.contains(photo.id) ? "checkmark.circle.fill" : "circle")
                                }
                            }.buttonStyle(.plain).accessibilityIdentifier("select-" + photo.id)
                                .accessibilityValue(selection.selected.contains(photo.id) ? L.t("已选择删除") : L.t("保留"))
                            Button { preview = photo } label: { Image(systemName: "play.circle").font(.title2).frame(width: 44, height: 44) }
                                .accessibilityLabel(L.t("播放视频")).accessibilityIdentifier("preview-" + photo.id)
                        }.panel()
                    }
                }
                if photos.isEmpty && (!grouped || model.analysis.complete) { EmptyState(title: L.t("这一类已经很清爽。")) }
            }.padding(22)
        }.background(Palette.background).navigationTitle(category.title).navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                Button(grouped ? L.t("删除全部预选") : L.t("复核所选照片")) { model.addToBasket(selection.selected); model.modal = .review }
                    .buttonStyle(SolidButton(destructive: true)).disabled(selection.selected.isEmpty).accessibilityIdentifier("reviewCategory")
                Text(L.f("已选 %@ 张 · %@", selection.selected.count.formatted(), Bytes.label(photos.filter { selection.selected.contains($0.id) }))).font(.caption).foregroundStyle(Palette.sub).accessibilityIdentifier("categorySelection")
            }.padding(.horizontal, 22).padding(.vertical, 12).background(Palette.background)
        }
        .onAppear { initialize() }
        .onChange(of: model.analysis.complete) { _, _ in initialize() }
        .onChange(of: groups.map(\.id)) { _, _ in initialize() }
        .onChange(of: model.assets.count) { _, _ in selection.selected.formIntersection(Set(photos.map(\.id))) }
        .sheet(item: $preview) { photo in
            VStack {
                HStack { Spacer(); Button(L.t("关闭")) { preview = nil }.padding().accessibilityIdentifier("closeVideoPreview") }
                PhotoViewer(asset: photo)
            }.background(Palette.background)
        }
    }
    private var columns: [GridItem] { Array(repeating: GridItem(.flexible(), spacing: 10), count: typeSize >= .xxLarge ? 1 : 2) }
    private func initialize() {
        if grouped {
            selection.update(groups)
        } else if !initialized {
            initialized = true
            selection.selected = category == .screenshots ? Set(photos.map(\.id)) : []
        }
    }
    private func toggle(_ id: String) { if selection.selected.contains(id) { selection.selected.remove(id) } else { selection.selected.insert(id) } }
    private func duration(_ value: Double) -> String { String(format: "%d:%02d", Int(value) / 60, Int(value) % 60) }
    private func tile(_ photo: PhotoAsset, best: Bool = false) -> some View {
        Button { toggle(photo.id) } label: {
            VStack(alignment: .leading, spacing: 8) {
                PhotoThumbnail(asset: photo).frame(height: 146).clipped().clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: selection.selected.contains(photo.id) ? "checkmark.circle.fill" : "circle")
                            .font(.title2).foregroundStyle(.white, selection.selected.contains(photo.id) ? Palette.delete : Palette.primary).padding(8)
                    }
                if best { Label(L.t("建议保留"), systemImage: "checkmark.seal").font(.caption.bold()) }
                AssetBadges(asset: photo)
                Text(Bytes.label([photo])).font(.caption).foregroundStyle(Palette.sub)
            }
        }.buttonStyle(.plain).accessibilityIdentifier("select-" + photo.id)
            .accessibilityLabel((best ? L.t("建议保留") + ", " : "") + photo.created.formatted(date: .abbreviated, time: .shortened))
            .accessibilityValue(selection.selected.contains(photo.id) ? L.t("已选择删除") : L.t("保留"))
    }
}
