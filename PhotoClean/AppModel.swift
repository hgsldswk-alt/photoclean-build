import SwiftUI
import UIKit
import WidgetKit
import StoreKit

enum Route: Hashable { case months, swipe(String), category(Category) }
enum Modal: Equatable { case review, celebration, share, paywall, settings }

@MainActor final class AppModel: ObservableObject {
    @Published var data: AppData
    @Published var assets: [PhotoAsset] = []
    @Published var months: [PhotoMonth] = []
    @Published var analysis = AnalysisResult()
    @Published var access: LibraryAccess = .notDetermined
    @Published var ready = false
    @Published var path: [Route] = []
    @Published var modal: Modal?
    @Published var message: String?
    @Published var fetching = false
    @Published var deleting = false
    @Published var cloudPrompt = false
    @Published var reminderPrompt = false
    @Published var receipt = CleanupReceipt()
    @Published var celebrationMonth = CalendarKey.month(Date())
    @Published var deviceFree: Int64 = 0
    @Published var deviceTotal: Int64 = 0
    @Published var scanError: String?
    @Published var readError = false
    let library: any PhotoLibrary
    let purchases: PurchaseManager
    let demo: Bool
    private let defaults: UserDefaults
    private let service: AnalysisService
    private var scan: Task<Void, Never>?
    private var fetchTask: Task<Void, Never>?
    private let changeRefresh = RefreshDebouncer()
    private var queuedRefresh = false
    private var scanPaused = false
    private var pendingAnalysis: [PhotoAsset]?
    private var scanToken = UUID()
    private var generation = UUID()
    private var started = false
    private var paywallReturn: Modal?
    private var suppressReview = false
    private var cloudDeleteCount: Int?
    private var pendingLink: String?
    private var screenshotAssets: [PhotoAsset] = []
    private var videoAssets: [PhotoAsset] = []
    private var assetIndex: [String: PhotoAsset] = [:]
    private var widgetRefresh: Task<Void, Never>?
    var pro: Bool { data.entitlement.hasPro(at: Date()) }
    var remaining: Int { data.quota.remaining(at: Date(), pro: pro) }
    var canDeletePartial: Bool { paywallReturn == .review && remaining > 0 && remaining < basketAssets.count }
    var partialDeleteCount: Int { data.quota.batchCount(selected: basketAssets.count, at: Date(), pro: pro) }
    var basketAssets: [PhotoAsset] { assets.filter { data.basket.contains($0.id) } }
    var reclaimable: [PhotoAsset] {
        let ids = Set(analysis.similar.flatMap { $0.selectedIDs }).union(analysis.duplicates.flatMap { $0.selectedIDs })
            .union(screenshotAssets.map(\.id)).union(videoAssets.map(\.id))
        return assets.filter { ids.contains($0.id) }
    }
    var latestMonth: PhotoMonth? { months.first { $0.reviewed(data.reviewed[$0.id] ?? []) < $0.assets.count } ?? months.first }
    var celebrationKeptPhotos: [PhotoAsset] {
        let month = months.first { $0.id == celebrationMonth }
        return PhotoPresentation.kept(in: month, reviewed: data.reviewed[celebrationMonth] ?? [], basket: data.basket)
    }
    var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0" }

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        demo = arguments.contains("-demo")
        let testing = demo && arguments.contains("-ui-testing")
        defaults = demo ? (UserDefaults(suiteName: "photoclean.demo.v1") ?? .standard) : Store.defaults
        if demo && (arguments.contains("-reset") || !testing) { defaults.removeObject(forKey: Store.key) }
        var initial = (try? Store.load(from: defaults)) ?? AppData()
        if let raw = defaults.data(forKey: Store.key), (try? JSONDecoder().decode(AppData.self, from: raw)) == nil {
            defaults.set(raw, forKey: Store.key + ".unreadable-backup")
        }
        if demo {
            if !arguments.contains("-onboarding") { initial.onboarded = true }
            initial.cloudWarningShown = true; initial.reminderOffered = true
            if let index = arguments.firstIndex(of: "-quota-left"), arguments.indices.contains(index + 1), let left = Int(arguments[index + 1]) {
                initial.entitlement.proStartedAt = Date().addingTimeInterval(-40 * 86400)
                initial.quota.used[CalendarKey.day(Date())] = max(0, initial.quota.limit(at: Date()) - max(0, left))
            }
        }
        data = initial
        library = demo ? DemoLibrary(denied: arguments.contains("-denied")) : PhotoKitLibrary()
        purchases = PurchaseManager(demo: demo); service = AnalysisService(demo: demo)
        library.onChange = { [weak self] in self?.libraryChanged() }
        purchases.onEntitlement = { [weak self] pro in
            guard let self else { return }
            self.data.entitlement.purchasedPro = pro; self.persist()
            if pro, self.modal == .paywall { self.modal = self.paywallReturn; self.paywallReturn = nil }
            if !pro && self.data.reminderEnabled { Task { await self.setReminder(false) } }
        }
    }
    deinit { scan?.cancel(); fetchTask?.cancel(); widgetRefresh?.cancel() }
    func start() async {
        guard !started else { return }; started = true
        access = await library.authorization()
        if !Launch.freePeriod && data.entitlement.proStartedAt == nil { data.entitlement.proStartedAt = Date() }
        ready = true; persist(); updateDiskSpace()
        refresh()
        Task { await purchases.start() }
    }
    func begin() async {
        access = await library.requestAuthorization(); data.onboarded = true; persist(); refresh()
    }
    func becameActive() async {
        let next = await library.authorization()
        if next != access { access = next; refresh() }
        updateDiskSpace()
    }
    private func libraryChanged() {
        guard !deleting else { return }
        changeRefresh.schedule { [weak self] in
            guard let self else { return }
            guard !self.deleting else { return }
            if self.fetching { self.queuedRefresh = true }
            else { self.refresh() }
        }
    }
    func refresh() {
        guard !deleting else { return }
        guard data.onboarded, access.readable else {
            fetchTask?.cancel(); scan?.cancel(); scan = nil; pendingAnalysis = nil
            generation = UUID(); scanToken = UUID()
            assets = []; assetIndex = [:]; months = []; screenshotAssets = []; videoAssets = []; analysis = AnalysisResult(); fetching = false; return
        }
        if fetching { queuedRefresh = true; return }
        generation = UUID()
        let token = generation; fetching = true; readError = false
        if !scanPaused { scanError = nil }
        fetchTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.generation == token, self.queuedRefresh {
                    self.queuedRefresh = false
                    self.libraryChanged()
                }
            }
            do {
                let photos = try await self.library.fetch { [weak self] batch in
                    guard let self, self.generation == token else { return }
                    await self.setAssets(batch, generation: token)
                    guard self.generation == token, !Task.isCancelled else { return }
                    self.startAnalysis(batch)
                }
                guard !Task.isCancelled, self.generation == token else { return }
                await self.setAssets(photos, generation: token)
                guard !Task.isCancelled, self.generation == token else { return }
                self.fetching = false
                let valid = Set(photos.map(\.id)); self.data.basket.formIntersection(valid)
                self.updateWidgetSnapshot(); self.persist(); self.updateDiskSpace()
                self.startAnalysis(photos)
                self.applyLaunchRoute()
                if let month = self.pendingLink { self.pendingLink = nil; self.openMonth(month) }
            } catch is CancellationError { }
            catch {
                guard self.generation == token else { return }
                self.fetching = false; self.readError = true; self.message = L.t("读取相册失败，请重试。"); self.suppressReview = true
            }
        }
    }
    private func setAssets(_ photos: [PhotoAsset], generation token: UUID) async {
        let index = await Task.detached(priority: .userInitiated) {
            (AnalysisCore.months(photos), AnalysisCore.screenshots(photos), AnalysisCore.largeVideos(photos), Dictionary(uniqueKeysWithValues: photos.map { ($0.id, $0) }))
        }.value
        guard generation == token, !Task.isCancelled else { return }
        assets = photos; months = index.0; screenshotAssets = index.1; videoAssets = index.2
        assetIndex = index.3; analysis = analysis.restricted(to: assetIndex)
    }
    private func startAnalysis(_ photos: [PhotoAsset]) {
        guard !scanPaused else { return }
        if scan != nil { pendingAnalysis = photos; return }
        let token = UUID(); scanToken = token
        analysis.complete = false
        scan = Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.service.run(assets: photos, library: self.library, demo: self.demo, refreshPending: { [weak self] in self?.pendingAnalysis != nil }) { [weak self] result in
                    guard let self, self.scanToken == token else { return }
                    var current = result.restricted(to: self.assetIndex)
                    if self.pendingAnalysis != nil { current.complete = false }
                    self.analysis = current
                }
            } catch is CancellationError { }
            catch { if self.scanToken == token { self.scanError = L.t("分析暂时中断，已完成的进度已保存。") } }
            guard self.scanToken == token else { return }
            self.scan = nil
            if let latest = self.pendingAnalysis {
                self.pendingAnalysis = nil; self.startAnalysis(latest)
            }
        }
    }
    func toggleScan() {
        if scanError != nil { scanPaused = false; scanError = nil; startAnalysis(assets) }
        else {
            scanPaused = true
            scan?.cancel(); scan = nil; scanToken = UUID(); pendingAnalysis = nil
            scanError = L.t("分析已暂停，稍后可继续。")
        }
    }
    func categoryPreview(_ category: Category) -> [PhotoAsset] {
        if category == .similar { return Array((analysis.similar.first?.assets ?? []).prefix(3)) }
        if category == .duplicates {
            return PhotoPresentation.groupPreview(analysis.duplicates, avoiding: analysis.similar.first?.assets.first, demo: demo)
        }
        return Array(categoryAssets(category).prefix(3))
    }
    func categoryAssets(_ category: Category) -> [PhotoAsset] {
        switch category {
        case .screenshots: return screenshotAssets
        case .videos: return videoAssets
        case .similar: return unique(analysis.similar.flatMap(\.assets))
        case .duplicates: return unique(analysis.duplicates.flatMap(\.assets))
        }
    }
    private func unique(_ photos: [PhotoAsset]) -> [PhotoAsset] { var seen = Set<String>(); return photos.filter { seen.insert($0.id).inserted } }
    func toggleBasket(_ id: String) {
        guard !deleting else { return }
        if data.basket.contains(id) { data.basket.remove(id) } else { data.basket.insert(id) }; persist()
    }
    func addToBasket(_ ids: Set<String>) { guard !deleting else { return }; data.basket.formUnion(ids); persist() }
    func mark(_ photo: PhotoAsset, month: String, delete: Bool) {
        data.reviewed[month, default: []].insert(photo.id)
        if delete { data.basket.insert(photo.id) } else { data.basket.remove(photo.id) }
        updateWidgetSnapshot(); persist()
    }
    func undo(_ photo: PhotoAsset, month: String, wasBasket: Bool) {
        data.reviewed[month, default: []].remove(photo.id)
        if wasBasket { data.basket.insert(photo.id) } else { data.basket.remove(photo.id) }
        updateWidgetSnapshot(); persist()
    }
    func openMonth(_ key: String) {
        guard CalendarKey.monthDate(key) != nil else { return }
        path = [.months, .swipe(key)]
    }
    func handleURL(_ url: URL) {
        guard url.scheme == "photoclean", url.host == "swipe",
              let key = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "month" })?.value,
              CalendarKey.monthDate(key) != nil else { return }
        if months.isEmpty { pendingLink = key } else { openMonth(key) }
    }
    func showPaywall() {
        guard modal != .paywall else { return }
        paywallReturn = modal; modal = .paywall; suppressReview = true
    }
    func dismissPaywall() { modal = paywallReturn; paywallReturn = nil }
    func deleteRemaining() async {
        guard canDeletePartial else { return }
        paywallReturn = nil; modal = .review
        await attemptDelete(limitTo: partialDeleteCount)
    }
    func attemptDelete(limitTo maximum: Int? = nil) async {
        guard !deleting else { return }
        let quotaDay = Date(), quotaCalendar = Calendar.current
        let basket = basketAssets
        let count = maximum.map { data.quota.batchCount(selected: min($0, basket.count), at: quotaDay, pro: pro, calendar: quotaCalendar) } ?? basket.count
        let photos = Array(basket.prefix(count))
        guard !photos.isEmpty else { if !basket.isEmpty { showPaywall() }; return }
        guard data.quota.permits(photos.count, at: quotaDay, pro: pro, calendar: quotaCalendar) else { showPaywall(); return }
        guard data.cloudWarningShown else { cloudDeleteCount = maximum; cloudPrompt = true; return }
        deleting = true
        fetchTask?.cancel(); generation = UUID(); fetching = false; queuedRefresh = false
        defer {
            deleting = false
            refresh()
        }
        let before = Bytes.total(assets)
        do {
            let success = try await library.delete(photos)
            guard success else { return }
            let now = Date(), ids = Set(photos.map(\.id))
            if let route = path.last, case .swipe(let month) = route { celebrationMonth = month }
            else { celebrationMonth = CalendarKey.month(now) }
            data.quota.record(count: photos.count, success: true, at: quotaDay, calendar: quotaCalendar)
            let milestones = data.stats.record(photos, at: now)
            data.basket.subtract(ids)
            receipt = CleanupReceipt(count: photos.count, bytes: Bytes.total(photos), approximate: photos.contains(where: \.approximate), date: now, before: before, milestones: milestones)
            await setAssets(assets.filter { !ids.contains($0.id) }, generation: generation)
            updateWidgetSnapshot(); persist()
            modal = .celebration
        } catch {
            suppressReview = true
            message = L.t("删除未完成，待删除照片和额度已保留。请重试。")
        }
    }
    func acceptCloudWarning() async {
        data.cloudWarningShown = true; persist()
        let count = cloudDeleteCount; cloudDeleteCount = nil
        await attemptDelete(limitTo: count)
    }
    func finishCelebration() {
        modal = nil; path = []
        if !demo && ReviewGate.eligible(stats: data.stats, firstOpen: data.firstOpen, now: Date(), version: version,
            reviewedVersion: data.reviewedVersion, afterPaywallOrError: suppressReview) {
            data.reviewedVersion = version; persist()
            if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }) {
                SKStoreReviewController.requestReview(in: scene)
            }
        } else if !data.reminderOffered && !demo {
            data.reminderOffered = true; persist(); reminderPrompt = true
        }
        suppressReview = false
    }
    func setReminder(_ enabled: Bool) async {
        if enabled && !pro { showPaywall(); return }
        if demo { data.reminderEnabled = enabled; persist(); return }
        let previous = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
        let count = months.first { $0.id == CalendarKey.month(previous) }?.assets.count ?? 0
        data.reminderEnabled = await ReminderScheduler.setEnabled(enabled, pro: pro, lastMonthCount: count)
        if enabled && !data.reminderEnabled { message = L.t("提醒未开启，请在系统设置中允许通知后重试。") }
        persist()
    }
    func persist() {
        do {
            try Store.save(data, to: defaults)
            if !demo {
                widgetRefresh?.cancel()
                widgetRefresh = Task {
                    do { try await Task.sleep(for: .seconds(1)) } catch { return }
                    WidgetCenter.shared.reloadAllTimelines()
                }
            }
        }
        catch { message = L.t("保存失败，请保留当前页面并重试。") }
    }
    private func updateWidgetSnapshot() {
        let key = CalendarKey.month(Date()), month = months.first { $0.id == key }
        data.widgetMonth = key; data.widgetNewCount = month?.assets.count ?? 0
        data.widgetUnreviewed = (month?.assets.count ?? 0) - (month?.reviewed(data.reviewed[key] ?? []) ?? 0)
    }
    private func updateDiskSpace() {
        if demo { deviceFree = 23_400_000_000; deviceTotal = 128_000_000_000; return }
        Task.detached {
            let url = URL(fileURLWithPath: NSHomeDirectory())
            let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
            let free = values?.volumeAvailableCapacityForImportantUsage ?? 0, total = Int64(values?.volumeTotalCapacity ?? 0)
            await MainActor.run { [weak self] in self?.deviceFree = free; self?.deviceTotal = total }
        }
    }
    private var launchRouteApplied = false
    private func applyLaunchRoute() {
        guard demo, !launchRouteApplied else { return }; launchRouteApplied = true
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-months") { path = [.months] }
        if args.contains("-month-complete"), let month = months.first {
            data.reviewed[month.id] = Set(month.assets.map(\.id))
        }
        if args.contains("-swipe"), let month = latestMonth { path = [.swipe(month.id)] }
        if args.contains("-similar") { path = [.category(.similar)] }
        if args.contains("-review") { data.basket = Set(assets.filter { !$0.isVideo }.prefix(12).map(\.id)); persist(); modal = .review }
        if args.contains("-celebrate") {
            celebrationMonth = CalendarKey.month(Date())
            let monthPhotos = months.first { $0.id == celebrationMonth }?.assets ?? []
            let kept = PhotoPresentation.samples(monthPhotos, limit: 5)
            data.reviewed[celebrationMonth, default: []].formUnion(kept.map(\.id))
            data.basket.subtract(kept.map(\.id))
            receipt = CleanupReceipt(count: 128, bytes: 1_480_000_000, date: Date(), before: 9_800_000_000, milestones: ["gb-1"])
            modal = args.contains("-share") ? .share : .celebration
        }
        if args.contains("-paywall") { showPaywall() }
        if args.contains("-settings") { modal = .settings }
    }
}
