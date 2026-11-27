import Foundation
import Combine
import StoreKit

@MainActor final class PurchaseManager: ObservableObject {
    @Published var product: Product?
    @Published var busy = false
    @Published var loadingProduct = false
    @Published var productLoadFailed = false
    @Published var error: String?
    @Published var note: String?
    private let demo: Bool
    private var updates: Task<Void, Never>?
    var onEntitlement: ((Bool) -> Void)?
    private var productID: String { Bundle.main.object(forInfoDictionaryKey: "PhotoCleanProProductID") as? String ?? "com.hgsldswk.photoclean.pro" }
    init(demo: Bool) { self.demo = demo }
    deinit { updates?.cancel() }
    func start() async {
        guard !demo else { return }
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                guard !Task.isCancelled else { return }
                guard case .verified(let transaction) = result, let self, transaction.productID == self.productID else { continue }
                await self.refresh(); await transaction.finish()
            }
        }
        await refresh(); await loadProduct()
    }
    func loadProduct() async {
        guard !demo, !loadingProduct else { return }
        loadingProduct = true; productLoadFailed = false; error = nil
        defer { loadingProduct = false }
        do {
            product = try await Product.products(for: [productID]).first
            productLoadFailed = product == nil
        } catch { productLoadFailed = true }
        if productLoadFailed { error = L.t("暂时无法连接 App Store，稍后再试") }
    }
    @discardableResult func refresh() async -> Bool {
        guard !demo else { return false }
        var pro = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, transaction.productID == productID,
               transaction.revocationDate == nil, !transaction.isUpgraded { pro = true }
        }
        onEntitlement?(pro); return pro
    }
    func buy() async {
        guard !busy, !loadingProduct else { return }; error = nil; note = nil
        guard !demo else { error = L.t("演示模式不会产生购买。请在正式版本购买。"); return }
        busy = true; defer { busy = false }
        if product == nil { await loadProduct() }
        guard let product else { return }
        do {
            switch try await product.purchase() {
            case .success(let result):
                guard case .verified(let transaction) = result else { error = L.t("购买验证失败，请恢复购买。"); return }
                await refresh(); await transaction.finish()
            case .pending: error = L.t("购买等待批准，完成后会自动解锁。")
            case .userCancelled: break
            @unknown default: break
            }
        } catch { self.error = L.t("购买未完成，请稍后重试。") }
    }
    func restore() async {
        guard !busy else { return }; error = nil; note = nil
        guard !demo else { error = L.t("演示模式不会产生购买。请在正式版本购买。"); return }
        busy = true; defer { busy = false }
        do { try await AppStore.sync(); let restored = await refresh(); note = restored ? L.t("购买已恢复") : L.t("未找到可恢复的购买。") }
        catch { self.error = L.t("恢复失败，请检查网络后重试。") }
    }
}
