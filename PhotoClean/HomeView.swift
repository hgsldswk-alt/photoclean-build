import SwiftUI
import UIKit

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openURL) private var openURL
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize = 32.0
    private let categories: [Category] = [.similar, .duplicates, .videos, .screenshots]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(L.t("相册清理")).font(.system(size: titleSize, weight: .heavy)).accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 8)
                    Button { model.modal = .settings } label: {
                        Image(systemName: "slider.horizontal.3").font(.system(size: 20, weight: .medium))
                            .frame(width: 40, height: 40).background(Palette.card, in: Circle())
                            .overlay(Circle().stroke(Palette.line, lineWidth: 0.5))
                            .frame(width: 44, height: 44)
                    }.buttonStyle(.plain).accessibilityLabel(L.t("设置")).accessibilityIdentifier("openSettings")
                }.padding(.top, 8)
                if model.readError {
                    Button(L.t("重新读取相册")) { model.refresh() }.buttonStyle(QuietButton()).accessibilityIdentifier("retryLibrary")
                }
                if model.access == .limited { limitedAccess }
                HomeCapacityCard(summary: HomeCapacity(reclaimable: model.reclaimable),
                                 free: model.deviceFree, total: model.deviceTotal,
                                 analyzed: model.analysis.analyzed, count: model.analysis.total,
                                 running: model.fetching || (!model.analysis.complete && model.scanError == nil))
                Button {
                    if let month = model.latestMonth { model.path.append(.swipe(month.id)) }
                    else { model.path.append(.months) }
                } label: {
                    MonthHero(month: model.latestMonth, reviewed: model.latestMonth.map { model.data.reviewed[$0.id] ?? [] } ?? [], fetching: model.fetching)
                }.buttonStyle(.plain).disabled(model.fetching && model.latestMonth == nil).accessibilityIdentifier("startMonthSwipe")
                HStack {
                    Text(L.t("分类整理")).font(.footnote.weight(.semibold)).foregroundStyle(Palette.sub)
                    Spacer()
                    Button(L.t("全部月份")) { model.path.append(.months) }
                        .font(.footnote.weight(.semibold)).padding(.vertical, 4).accessibilityIdentifier("openMonths")
                }
                VStack(spacing: 0) {
                    ForEach(categories) { category in
                        Button { model.path.append(.category(category)) } label: {
                            HomeCategoryRow(category: category, photos: model.categoryAssets(category), preview: model.categoryPreview(category),
                                            groupCount: category == .similar ? model.analysis.similar.count : model.analysis.duplicates.count)
                        }.buttonStyle(.plain).accessibilityIdentifier("category-" + category.id)
                        if category != categories.last {
                            Rectangle().fill(Palette.line).frame(height: 0.5).accessibilityHidden(true)
                        }
                    }
                }.background(Palette.card, in: RoundedRectangle(cornerRadius: 22))
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(Palette.line, lineWidth: 0.5))
                AnalysisProgressView().foregroundStyle(Palette.sub).padding(.top, 2)
            }.padding(.horizontal, 20).padding(.bottom, 20)
        }.background(Palette.background).navigationTitle("")
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            if !model.data.basket.isEmpty {
                Button { model.modal = .review } label: {
                    HStack(spacing: 12) {
                        Text(L.f("待删除 %@ 张 · %@", model.basketAssets.count.formatted(), Bytes.label(model.basketAssets)))
                            .monospacedDigit().multilineTextAlignment(.leading)
                        Spacer(minLength: 8)
                        Text(L.t("复核"))
                        Image(systemName: "arrow.right")
                    }.font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 22).padding(.vertical, 18)
                        .background(Palette.primary.opacity(0.94), in: Capsule())
                        .shadow(color: Palette.primary.opacity(0.25), radius: 15, y: 10)
                }.buttonStyle(.plain).disabled(model.fetching).accessibilityIdentifier("openBasket")
                    .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 12)
            }
        }
    }

    private var limitedAccess: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L.f("只能看到你选的 %@ 张", model.assets.count.formatted())).font(.footnote)
            HStack {
                Button(L.t("允许访问全部")) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }.accessibilityIdentifier("allowAllPhotos")
                Spacer()
                Button(L.t("再选几张")) {
                    if let controller = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first?.windows.first(where: \.isKeyWindow)?.rootViewController {
                        model.library.selectMore(from: controller)
                    }
                }.accessibilityIdentifier("selectMorePhotos")
            }.font(.footnote.bold())
        }.panel()
    }
}

private struct HomeCapacityCard: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let summary: HomeCapacity
    let free: Int64
    let total: Int64
    let analyzed: Int
    let count: Int
    let running: Bool
    @State private var appeared = false
    private let colors = [Palette.ringPhoto, Palette.ringVideo, Palette.ringScreenshot]
    private var progress: Double { running ? min(1, max(0, Double(analyzed) / Double(max(1, count)))) : 1 }
    private var extent: Double { appeared ? progress : 0 }

    var body: some View {
        let parts = Bytes.components(summary.total)
        let layout = typeSize >= .xxLarge ? AnyLayout(VStackLayout(alignment: .leading, spacing: 18)) : AnyLayout(HStackLayout(spacing: 18))
        layout {
            ZStack {
                Circle().stroke(Palette.ringTrack, lineWidth: 12)
                ForEach(0..<3) { index in
                    let span = CapacityRing.spans(values: summary.values, progress: extent)[index]
                    let fraction = span.end - span.start
                    if fraction > 0 {
                        let gap = min(0.045, fraction * 0.65)
                        let width = min(12.0, gap * 2 * Double.pi * 53 * 0.8)
                        Circle().trim(from: span.start + gap / 2, to: span.end - gap / 2)
                            .stroke(colors[index], style: StrokeStyle(lineWidth: CGFloat(width), lineCap: .round))
                            .rotationEffect(.degrees(-90)).opacity(extent > 0 ? 1 : 0)
                    }
                }
                VStack(spacing: 3) {
                    Text(parts.number).font(.system(size: 25, weight: .bold, design: .rounded)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.55).accessibilityIdentifier("reclaimableValue")
                        .accessibilityLabel(L.f("可整理 %@", summary.approximate ? L.f("约 %@", Bytes.format(summary.total)) : Bytes.format(summary.total)))
                    Text(L.f("%@ 可腾出", parts.unit)).font(.system(size: 12)).foregroundStyle(Palette.sub)
                        .lineLimit(1).minimumScaleFactor(0.65).accessibilityHidden(true)
                    if summary.approximate { Text(L.t("估算")).font(.caption2).foregroundStyle(Palette.sub).accessibilityHidden(true) }
                }.padding(.horizontal, 10)
            }.frame(width: 106, height: 106).padding(6).accessibilityElement(children: .contain)
                .accessibilityIdentifier("deviceStorageBar")
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.55), value: summary.values)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.55), value: extent)
            VStack(alignment: .leading, spacing: 7) {
                legend(L.t("相似和重复"), value: summary.photos, color: colors[0])
                legend(L.t("大视频"), value: summary.videos, color: colors[1])
                legend(L.t("截图"), value: summary.screenshots, color: colors[2])
                Text(L.f("手机剩余 %@ / %@", Bytes.format(free), Bytes.format(total)))
                    .font(.system(size: 12)).foregroundStyle(Palette.sub).fixedSize(horizontal: false, vertical: true).padding(.top, 4)
                if running {
                    Text(L.f("分析中 %@%%", Int(progress * 100).formatted())).font(.caption2).foregroundStyle(Palette.sub)
                        .accessibilityIdentifier("ringAnalysisProgress")
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(20).background(Palette.card, in: RoundedRectangle(cornerRadius: 26))
            .overlay(RoundedRectangle(cornerRadius: 26).stroke(Palette.line, lineWidth: 0.5))
            .onAppear { appeared = true }
    }
    private func legend(_ title: String, value: Int64, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8).accessibilityHidden(true)
            Text(title).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 2)
            Text(Bytes.format(value)).fontWeight(.semibold).monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
                .layoutPriority(1)
        }.font(.system(size: 12.5))
    }
}

private struct MonthHero: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .subheadline) private var captionSize = 13.0
    @ScaledMetric(relativeTo: .title2) private var headingSize = 24.0
    let month: PhotoMonth?
    let reviewed: Set<String>
    let fetching: Bool
    private var preview: [PhotoAsset] {
        PhotoPresentation.samples(month?.assets ?? [], limit: 5)
    }
    private var caption: String {
        guard let month else { return fetching ? L.t("正在读取相册…") : L.t("相册里还没有照片。") }
        let done = month.reviewed(reviewed)
        let status = done == 0 ? L.t("还没整理") : L.f("已整理 %@ / %@", done.formatted(), month.assets.count.formatted())
        return L.f("%@ · %@ 张 · %@", CalendarKey.heroMonth(month.id), month.assets.count.formatted(), status)
    }
    var body: some View {
        let photos = preview
        ZStack(alignment: .bottomLeading) {
            GeometryReader { geometry in
                let smallWidth = max(0, (geometry.size.width - 6) / 4)
                HStack(spacing: 3) {
                    cell(photos, index: 0).frame(width: smallWidth * 2, height: geometry.size.height)
                    VStack(spacing: 3) {
                        cell(photos, index: 1)
                        cell(photos, index: 3)
                    }.frame(width: smallWidth)
                    VStack(spacing: 3) {
                        cell(photos, index: 2)
                        cell(photos, index: 4)
                    }.frame(width: smallWidth)
                }
            }.accessibilityHidden(true)
            LinearGradient(stops: [.init(color: .clear, location: 0.3), .init(color: Color(red: 15/255, green: 20/255, blue: 30/255).opacity(0.78), location: 1)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 4) {
                Text(caption).font(.system(size: captionSize)).foregroundStyle(.white.opacity(0.88))
                HStack(alignment: .bottom) {
                    Text(L.t("按月滑一遍")).font(.system(size: headingSize, weight: .heavy))
                    Spacer(minLength: 8)
                    HStack(spacing: 6) {
                        Text(L.t("开始")); Image(systemName: "arrow.right")
                    }.font(.system(size: 14, weight: .bold)).padding(.horizontal, 14).padding(.vertical, 9)
                        .background(.white.opacity(0.94), in: Capsule()).foregroundStyle(Palette.primary)
                }
            }.foregroundStyle(.white).padding(.horizontal, 18).padding(.bottom, 16)
        }.frame(height: typeSize.isAccessibilitySize ? 250 : 200)
            .background(Palette.photoPlaceholder).clipShape(RoundedRectangle(cornerRadius: 26))
            .contentShape(RoundedRectangle(cornerRadius: 26)).accessibilityElement(children: .combine)
    }
    @ViewBuilder private func cell(_ photos: [PhotoAsset], index: Int) -> some View {
        if photos.indices.contains(index) { PhotoThumbnail(asset: photos[index]).clipped() }
        else { Palette.photoPlaceholder }
    }
}

private struct HomeCategoryRow: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .headline) private var titleSize = 16.0
    @ScaledMetric(relativeTo: .caption) private var captionSize = 12.0
    let category: Category
    let photos: [PhotoAsset]
    let preview: [PhotoAsset]
    let groupCount: Int
    private var caption: String {
        switch category {
        case .similar: return L.f("%@ 组 · 每组留最好的一张", groupCount.formatted())
        case .duplicates: return L.t("完全一样的副本")
        case .videos: return L.t("按大小排序")
        case .screenshots: return L.t("看过就可以删")
        }
    }
    var body: some View {
        HStack(spacing: 12) {
            thumbnails
            VStack(alignment: .leading, spacing: 2) {
                Text(category.title).font(.system(size: titleSize, weight: .semibold))
                Text(caption).font(.system(size: captionSize)).foregroundStyle(Palette.sub)
                    .fixedSize(horizontal: false, vertical: true)
                if typeSize >= .xxLarge { amounts }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if typeSize < .xxLarge { amounts }
        }.padding(.horizontal, 16).padding(.vertical, 13).frame(minHeight: 70)
            .contentShape(Rectangle()).accessibilityElement(children: .combine)
    }
    private var amounts: some View {
        VStack(alignment: typeSize >= .xxLarge ? .leading : .trailing, spacing: 2) {
            Text(Bytes.label(photos)).font(.system(size: 15, weight: .bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
            Text(category == .videos ? L.f("%@ 段", photos.count.formatted()) : L.f("%@ 张", photos.count.formatted()))
                .font(.system(size: captionSize)).foregroundStyle(Palette.sub)
        }.fixedSize(horizontal: true, vertical: false)
    }
    private var thumbnails: some View {
        ZStack(alignment: .leading) {
            ForEach(0..<3) { index in
                ZStack(alignment: .bottomTrailing) {
                    if preview.indices.contains(index) { PhotoThumbnail(asset: preview[index]) }
                    else { Palette.photoPlaceholder.opacity(0.45) }
                    if category == .videos, preview.indices.contains(index) {
                        let seconds = max(0, Int(preview[index].duration))
                        Text(String(format: "%d:%02d", seconds / 60, seconds % 60))
                            .font(.system(size: 8, weight: .semibold)).monospacedDigit().foregroundStyle(.white)
                            .padding(2).background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 3)).padding(2)
                    }
                }.frame(width: 40, height: 44).clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white, lineWidth: 2)).offset(x: CGFloat(index) * 11)
            }
        }.frame(width: 62, height: 44, alignment: .leading).accessibilityHidden(true)
    }
}

struct AnalysisProgressView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(model.fetching ? L.t("正在读取相册…") : (model.analysis.complete ? L.t("本机分析完成") : L.f("已分析 %@ / %@", model.analysis.analyzed.formatted(), model.analysis.total.formatted())))
                    .font(.footnote).accessibilityIdentifier("analysisProgress")
                Spacer()
                if !model.analysis.complete && model.analysis.total > 0 {
                    Button(model.scanError == nil ? L.t("暂停") : L.t("继续分析")) { model.toggleScan() }.font(.footnote).accessibilityIdentifier("toggleAnalysis")
                }
            }
            if !model.analysis.complete { ProgressView(value: Double(model.analysis.analyzed), total: Double(max(1, model.analysis.total))).tint(Palette.accent) }
            if model.analysis.skippedCloud > 0 { Text(L.f("有 %@ 张在 iCloud 中未下载，未参与比对。", model.analysis.skippedCloud.formatted())).font(.caption).foregroundStyle(Palette.sub) }
            if model.analysis.failed > 0 { Text(L.f("%@ 张暂时无法分析。", model.analysis.failed.formatted())).font(.caption).foregroundStyle(Palette.sub) }
            if let error = model.scanError { Text(error).font(.caption).foregroundStyle(Palette.sub) }
        }
    }
}

struct MonthsView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(model.months) { month in
                    Button { model.path.append(.swipe(month.id)) } label: {
                        let reviewed = month.reviewed(model.data.reviewed[month.id] ?? [])
                        let complete = !month.assets.isEmpty && reviewed == month.assets.count
                        HStack(spacing: 16) {
                            MonthMosaic(assets: month.assets)
                            VStack(alignment: .leading, spacing: 9) {
                                Text(CalendarKey.monthTitle(month.id)).font(.headline)
                                if complete {
                                    Label(L.t("已整理完"), systemImage: "checkmark.circle.fill")
                                        .font(.footnote).foregroundStyle(Palette.accent)
                                } else {
                                    Text(L.f("%@ 张 · 已整理 %@", month.assets.count.formatted(), reviewed.formatted()))
                                        .font(.footnote).foregroundStyle(Palette.sub)
                                }
                                StorageLine(fraction: Double(reviewed) / Double(max(1, month.assets.count)))
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            Spacer(minLength: 0); Image(systemName: "chevron.right").font(.footnote)
                        }.panel()
                    }.buttonStyle(.plain).accessibilityIdentifier("month-" + month.id)
                }
                if model.months.isEmpty { EmptyState(title: L.t("相册里还没有照片。")) }
            }.padding(20)
        }.background(Palette.background).navigationTitle(L.t("按月整理")).navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
    }
}

private struct MonthMosaic: View {
    let assets: [PhotoAsset]
    var body: some View {
        let photos = PhotoPresentation.samples(assets, limit: 4)
        VStack(spacing: 2) {
            HStack(spacing: 2) { cell(photos, 0); cell(photos, 1) }
            HStack(spacing: 2) { cell(photos, 2); cell(photos, 3) }
        }.frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 12)).accessibilityHidden(true)
    }
    @ViewBuilder private func cell(_ photos: [PhotoAsset], _ index: Int) -> some View {
        if photos.indices.contains(index) { PhotoThumbnail(asset: photos[index]).frame(width: 31, height: 31).clipped() }
        else { Palette.photoPlaceholder.opacity(0.35).frame(width: 31, height: 31) }
    }
}
