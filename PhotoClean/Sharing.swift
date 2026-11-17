import SwiftUI
import UIKit

struct SharingView: View {
    @EnvironmentObject private var model: AppModel
    @State private var image: UIImage?
    @State private var activity = false
    @State private var copied = false
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if let image {
                    Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 24))
                        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Palette.line, lineWidth: 0.5))
                        .shadow(color: Palette.primary.opacity(0.12), radius: 14, x: 0, y: 8)
                        .accessibilityLabel(L.t("分享卡预览，不含个人照片")).accessibilityIdentifier("sharePreview")
                    Button(L.t("分享图片与文案")) { activity = true }.buttonStyle(SolidButton()).accessibilityIdentifier("shareImage")
                } else { ProgressView(L.t("正在生成分享卡…")) }
                Button(copied ? L.t("文案已复制") : L.t("复制文案")) {
                    UIPasteboard.general.string = ShareText.caption(bytes: model.receipt.bytes, count: model.receipt.count); copied = true
                }.buttonStyle(QuietButton()).accessibilityIdentifier("copyCaption")
                Button(L.t("完成")) { model.finishCelebration() }.accessibilityIdentifier("finishSharing")
            }.frame(maxWidth: 540).padding(24).frame(maxWidth: .infinity)
        }.task {
            let renderer = ImageRenderer(content: ShareCard(receipt: model.receipt))
            renderer.proposedSize = ProposedViewSize(width: 540, height: 720)
            renderer.scale = 2
            image = renderer.uiImage
            if image == nil { model.message = L.t("分享图生成失败，请重试。") }
        }
        .sheet(isPresented: $activity) {
            if let image { ShareActivity(items: [image, ShareText.caption(bytes: model.receipt.bytes, count: model.receipt.count)]) }
        }
    }
}

struct ShareActivity: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.view.accessibilityIdentifier = "systemShareSheet"
        return controller
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
