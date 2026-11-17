import SwiftUI
import UIKit

enum Palette {
    static let primary = Color(red: 34/255, green: 48/255, blue: 74/255)
    static let accent = adaptive(0x22304A, 0xB7C9E8)
    static let ink = adaptive(0x22304A, 0xF1F2F4)
    static let background = adaptive(0xF7F6F3, 0x121417)
    static let card = adaptive(0xFFFFFF, 0x1D2025)
    static let sub = adaptive(0x6C7079, 0xA5ABB5)
    static let line = adaptive(0xE8E6E1, 0x34383F)
    static let ringPhoto = adaptive(0x22304A, 0xB7C9E8)
    static let ringVideo = adaptive(0x6F86AE, 0x829CC4)
    static let ringScreenshot = adaptive(0xB9C6DB, 0x526783)
    static let ringTrack = adaptive(0xEEECE8, 0x34383F)
    static let photoPlaceholder = adaptive(0xD5DDD9, 0x38434B)
    static let delete = Color(red: 181/255, green: 82/255, blue: 59/255)
    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        func value(_ hex: UInt32) -> UIColor { UIColor(red: CGFloat((hex >> 16) & 255)/255, green: CGFloat((hex >> 8) & 255)/255, blue: CGFloat(hex & 255)/255, alpha: 1) }
        return Color(UIColor { $0.userInterfaceStyle == .dark ? value(dark) : value(light) })
    }
}

struct SolidButton: ButtonStyle {
    var destructive = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).frame(maxWidth: .infinity).padding(.vertical, 17).padding(.horizontal, 14)
            .background(destructive ? Palette.delete : Palette.primary, in: RoundedRectangle(cornerRadius: 17))
            .foregroundStyle(.white).opacity(configuration.isPressed ? 0.75 : 1)
    }
}
struct QuietButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).frame(maxWidth: .infinity).padding(.vertical, 17).padding(.horizontal, 14)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 17))
            .overlay(RoundedRectangle(cornerRadius: 17).stroke(Palette.line, lineWidth: 1))
            .foregroundStyle(Palette.ink).opacity(configuration.isPressed ? 0.6 : 1)
    }
}
extension View {
    func panel() -> some View { padding(20).background(Palette.card, in: RoundedRectangle(cornerRadius: 22)).overlay(RoundedRectangle(cornerRadius: 22).stroke(Palette.line, lineWidth: 0.5)) }
    func largeNumber(_ size: CGFloat = 56) -> some View { font(.system(size: size, weight: .bold, design: .rounded)).monospacedDigit() }
}

struct EmptyState: View {
    let title: String
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle").font(.system(size: 44, weight: .light)).foregroundStyle(Palette.accent)
            Text(title).font(.title3.bold()).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.vertical, 60).accessibilityIdentifier("emptyState")
    }
}

struct StorageLine: View {
    let fraction: Double
    var height: CGFloat = 3
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.primary.opacity(0.10))
                Capsule().fill(Palette.accent).frame(width: geometry.size.width * CGFloat(min(1, max(0, fraction))))
            }
        }.frame(height: height).accessibilityHidden(true)
    }
}

struct StorageComparison: View {
    let before: Int64
    let removed: Int64
    var poster = false
    private var after: Int64 { max(0, before - max(0, removed)) }
    var body: some View {
        VStack(spacing: poster ? 12 : 10) {
            row(L.t("整理前"), bytes: before, fraction: 1, muted: true)
            row(L.t("整理后"), bytes: after, fraction: Double(after) / Double(max(1, before)), muted: false)
        }.font(poster ? .system(size: 17, weight: .medium) : .footnote)
            .accessibilityElement(children: .combine)
    }
    private func row(_ title: String, bytes: Int64, fraction: Double, muted: Bool) -> some View {
        VStack(spacing: poster ? 8 : 6) {
            HStack { Text(title); Spacer(); Text(Bytes.format(bytes)).monospacedDigit() }
                .foregroundStyle(poster ? Palette.primary : Palette.ink)
            StorageLine(fraction: fraction, height: poster ? 8 : 5).opacity(muted ? 0.25 : 1)
        }
    }
}

struct PhotoStackIllustration: View {
    var locked = false
    var body: some View {
        ZStack {
            card.rotationEffect(.degrees(-13)).offset(x: -12, y: -5).opacity(0.35)
            card.rotationEffect(.degrees(8)).offset(x: 10, y: -2).opacity(0.6)
            card.overlay {
                Image(systemName: "photo").font(.system(size: 34, weight: .ultraLight)).foregroundStyle(Palette.accent)
            }
            Image(systemName: locked ? "lock.fill" : "checkmark")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.accent)
                .frame(width: 30, height: 30).background(Palette.card, in: Circle())
                .overlay(Circle().stroke(Palette.line, lineWidth: 0.5)).offset(x: 43, y: 31)
        }.frame(width: 140, height: 108).accessibilityHidden(true)
    }
    private var card: some View {
        RoundedRectangle(cornerRadius: 12).fill(Palette.card).frame(width: 90, height: 72)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.accent.opacity(0.6), lineWidth: 1))
    }
}
