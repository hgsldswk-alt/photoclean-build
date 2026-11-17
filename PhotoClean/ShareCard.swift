import SwiftUI
import UIKit
import CoreImage.CIFilterBuiltins

enum QRCode {
    static var downloadURL: URL? { ShareText.downloadURL(id: Bundle.main.object(forInfoDictionaryKey: "APP_STORE_ID") as? String) }
    static func image() -> UIImage? {
        guard let url = downloadURL else { return nil }
        let filter = CIFilter.qrCodeGenerator(); filter.message = Data(url.absoluteString.utf8); filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

struct ShareCard: View {
    let receipt: CleanupReceipt
    var body: some View {
        VStack(spacing: 0) {
            header
            VStack(alignment: .leading, spacing: 0) {
                StorageComparison(before: receipt.before, removed: receipt.bytes, poster: true)
                Text(L.t("清空系统「最近删除」后释放空间。"))
                    .font(.system(size: 17)).foregroundStyle(Palette.sub).fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
                Spacer(minLength: 20)
                challenge
                Spacer(minLength: 20)
                footer
            }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }.frame(width: 540, height: 720).background(Color(red: 247/255, green: 246/255, blue: 243/255))
            .foregroundStyle(Palette.primary)
            .environment(\.colorScheme, .light).environment(\.dynamicTypeSize, .medium)
    }
    private var challenge: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L.t("30 天相册断舍离")).font(.system(size: 30, weight: .bold))
                .lineLimit(2).minimumScaleFactor(0.75).fixedSize(horizontal: false, vertical: true)
            Text(L.t("留下喜欢的，给手机一点空间。")).font(.system(size: 18)).foregroundStyle(Palette.sub)
                .fixedSize(horizontal: false, vertical: true)
        }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(CalendarKey.monthTitle(CalendarKey.month(receipt.date))).font(.system(size: 19, weight: .medium))
                Spacer()
                Text(L.t("已整理空间")).font(.system(size: 17))
            }.foregroundStyle(.white.opacity(0.8))
            Text(freedText).font(.system(size: 76, weight: .bold, design: .rounded)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.5)
            Text(L.f("删掉 %@ 张", receipt.count.formatted())).font(.system(size: 21, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
        }.padding(32).frame(width: 540, height: 250, alignment: .leading)
            .foregroundStyle(.white).background(Palette.primary)
    }
    private var freedText: String {
        let value = Bytes.format(receipt.bytes)
        return receipt.approximate ? L.f("约 %@", value) : value
    }
    private var footer: some View {
        HStack(alignment: .bottom, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "rectangle.stack").font(.system(size: 24, weight: .light)).foregroundStyle(.white)
                        .frame(width: 46, height: 46).background(Palette.primary, in: RoundedRectangle(cornerRadius: 12))
                    Text(L.t("相册清理")).font(.system(size: 20, weight: .semibold))
                }
                Text(Launch.freePeriod ? L.t("无广告 · 照片不上传") : L.t("一次买断 · 无广告 · 照片不上传"))
                    .font(.system(size: 17)).foregroundStyle(Palette.sub).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
            downloadArea
        }
    }
    private var downloadArea: some View {
        Group {
            if let qr = QRCode.image() {
                Image(uiImage: qr).interpolation(.none).resizable().scaledToFit().padding(10).background(.white)
            } else {
                Text(L.t("在 App Store 搜索「相册清理」"))
                    .font(.system(size: 17, weight: .medium)).minimumScaleFactor(0.8).multilineTextAlignment(.center)
                    .padding(10).frame(maxWidth: .infinity, maxHeight: .infinity).background(.white)
            }
        }.frame(width: 140, height: 140).clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Palette.line, lineWidth: 1))
    }
}

