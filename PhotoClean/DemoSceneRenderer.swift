import UIKit

enum DemoSceneRenderer {
    private struct Random {
        var state: UInt64
        mutating func next() -> CGFloat {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat((state >> 32) & 0xFFFF) / 65535
        }
    }
    nonisolated static func draw(_ appearance: DemoCatalog.Appearance, size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            let c = renderer.cgContext
            c.scaleBy(x: size.width / 300, y: size.height / 400)
            var random = Random(state: appearance.seed)
            let shift = (random.next() - 0.5) * 14
            func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> UIColor {
                UIColor(red: CGFloat((hex >> 16) & 255) / 255,
                        green: CGFloat((hex >> 8) & 255) / 255,
                        blue: CGFloat(hex & 255) / 255, alpha: alpha)
            }
            func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ hex: UInt32, _ alpha: CGFloat = 1) {
                c.setFillColor(color(hex, alpha).cgColor); c.fill(CGRect(x: x, y: y, width: w, height: h))
            }
            func ellipse(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ hex: UInt32, _ alpha: CGFloat = 1) {
                c.setFillColor(color(hex, alpha).cgColor); c.fillEllipse(in: CGRect(x: x, y: y, width: w, height: h))
            }
            func round(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ radius: CGFloat, _ hex: UInt32) {
                c.setFillColor(color(hex).cgColor)
                c.addPath(UIBezierPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: radius).cgPath); c.fillPath()
            }
            func gradient(_ top: UInt32, _ bottom: UInt32, from: CGFloat = 0, to: CGFloat = 400) {
                guard let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [color(top).cgColor, color(bottom).cgColor] as CFArray, locations: [0, 1]) else { return }
                c.saveGState(); c.clip(to: CGRect(x: 0, y: from, width: 300, height: to - from))
                c.drawLinearGradient(g, start: CGPoint(x: 0, y: from), end: CGPoint(x: 0, y: to), options: [])
                c.restoreGState()
            }
            func polygon(_ points: [CGPoint], _ hex: UInt32) {
                guard let first = points.first else { return }
                c.beginPath(); c.move(to: first)
                for p in points.dropFirst() { c.addLine(to: p) }
                c.closePath(); c.setFillColor(color(hex).cgColor); c.fillPath()
            }
            func line(_ x: CGFloat, _ y: CGFloat, _ endX: CGFloat, _ endY: CGFloat, _ width: CGFloat, _ hex: UInt32, _ alpha: CGFloat = 1) {
                c.setStrokeColor(color(hex, alpha).cgColor); c.setLineWidth(width); c.setLineCap(.round)
                c.move(to: CGPoint(x: x, y: y)); c.addLine(to: CGPoint(x: endX, y: endY)); c.strokePath()
            }
            func text(_ value: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ hex: UInt32, bold: Bool = false) {
                (value as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: [
                    .font: UIFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular), .foregroundColor: color(hex)])
            }
            if appearance.screenshot {
                rect(0, 0, 300, 400, 0xF1F2F6)
                text("9:41", 17, 12, 10, 0x253249, bold: true)
                for n in 0..<4 { rect(249 + CGFloat(n) * 4, 20 - CGFloat(n) * 2, 2, 3 + CGFloat(n) * 2, 0x253249) }
                round(271, 13, 17, 8, 2, 0x253249)
                let theme: UInt32 = appearance.seed % 2 == 0 ? 0x708CAD : 0x9E887A
                round(17, 48, 137, 14, 4, 0x253249)
                round(17, 73, 90, 5, 2, 0xA9B0BC)
                round(17, 99, 266, 30, 10, 0xE3E6ED)
                ellipse(29, 109, 9, 9, 0xABB4C2)
                round(48, 111, 121, 5, 2, 0xBBC2CD)
                for n in 0..<3 {
                    let y = 145 + CGFloat(n) * 73
                    round(17, y, 266, 61, 12, 0xFFFFFF)
                    round(29, y + 12, 38, 38, 9, theme)
                    round(79, y + 14, 89 + random.next() * 44, 7, 3, 0x626F85)
                    round(79, y + 29, 153, 4, 2, 0xD0D5DE)
                    round(79, y + 40, 108, 4, 2, 0xDFE2E8)
                }
                rect(0, 370, 300, 30, 0xFFFFFF)
                for n in 0..<4 { ellipse(38 + CGFloat(n) * 69, 380, 10, 10, n == 0 ? theme : 0xC6CCD6) }
                return
            }
            switch appearance.scene {
            case .sunset:
                gradient(0xF6D1A5, 0xDE947B, to: 222)
                ellipse(57 + shift, 114, 57, 57, 0xFFF1C3)
                gradient(0x71889A, 0x293E55, from: 222)
                for n in 0..<23 {
                    let y = 226 + CGFloat(n) * 6.8
                    let x = 42 + random.next() * 110
                    line(x, y, x + 35 + random.next() * 80, y, 1.1, 0xEAC6AE, 0.28)
                }
                polygon([CGPoint(x: 0, y: 365), CGPoint(x: 106, y: 352), CGPoint(x: 300, y: 391), CGPoint(x: 300, y: 400), CGPoint(x: 0, y: 400)], 0x243444)
            case .lake:
                gradient(0xBFDDEB, 0xE2E9DF, to: 218)
                ellipse(205 + shift, 76, 38, 38, 0xFFF3D4)
                polygon([CGPoint(x: 0, y: 195), CGPoint(x: 72, y: 123), CGPoint(x: 157, y: 209), CGPoint(x: 239, y: 146), CGPoint(x: 300, y: 206), CGPoint(x: 300, y: 252), CGPoint(x: 0, y: 252)], 0x87ABBC)
                gradient(0x668FA8, 0x224D68, from: 220)
                for n in 0..<19 {
                    let y = 235 + CGFloat(n) * 9
                    let x = random.next() * 220
                    line(x, y, x + 25 + random.next() * 50, y, 0.8, 0xDAE6E8, 0.32)
                }
                polygon([CGPoint(x: 0, y: 400), CGPoint(x: 0, y: 300), CGPoint(x: 78, y: 322), CGPoint(x: 131, y: 400)], 0x354E4D)
            case .stillLife:
                gradient(0xF6EDDF, 0xE2CFB5)
                polygon([CGPoint(x: 0, y: 276), CGPoint(x: 300, y: 236), CGPoint(x: 300, y: 400), CGPoint(x: 0, y: 400)], 0xD6BFA4)
                ellipse(48, 233, 208, 63, 0x9B8069, 0.16)
                ellipse(36, 202, 217, 73, 0xF8EFDF)
                ellipse(48, 209, 193, 54, 0xE4D7C3)
                ellipse(67 + shift, 184, 75, 69, 0xF0C4A9)
                ellipse(134 + shift, 174, 69, 66, 0xDFA58D)
                ellipse(74 + shift, 187, 37, 28, 0xF6D2BC, 0.7)
                line(163 + shift, 179, 168 + shift, 171, 2, 0x7A654D)
                ellipse(164 + shift, 167, 22, 8, 0x7F9471)
                round(196, 95, 43, 82, 6, 0xEDE2D1)
                ellipse(196, 91, 43, 10, 0xCFBFA7)
            case .hill:
                gradient(0xDFEBD8, 0xAFCCB4)
                ellipse(199 + shift, 67, 43, 43, 0xF6F0D0, 0.8)
                for layer in 0..<3 {
                    let y = 228 + CGFloat(layer) * 67
                    let p = UIBezierPath(); p.move(to: CGPoint(x: -10, y: y + 25))
                    p.addCurve(to: CGPoint(x: 310, y: y + 7), controlPoint1: CGPoint(x: 75 + shift, y: y - 140), controlPoint2: CGPoint(x: 162, y: y + 130))
                    p.addLine(to: CGPoint(x: 310, y: 400)); p.addLine(to: CGPoint(x: -10, y: 400)); p.close()
                    color([UInt32(0x91AF87), 0x668A64, 0x3E6553][layer]).setFill(); p.fill()
                }
                for n in 0..<12 {
                    let x = CGFloat(n) * 29 + shift
                    line(x, 350 + random.next() * 35, x + 4, 341 + random.next() * 34, 1.5, 0xB4C295, 0.4)
                }
            case .flower:
                gradient(0xF5EEE4, 0xE6D9C9)
                line(150 + shift, 228, 136 + shift, 400, 4, 0x7B9475)
                ellipse(139 + shift, 291, 68, 26, 0xA9B49A)
                ellipse(87 + shift, 323, 53, 22, 0x8C9F83)
                for n in 0..<7 {
                    let angle = CGFloat(n) * .pi * 2 / 7
                    let x = 129 + shift + cos(angle) * 41
                    let y = 169 + sin(angle) * 39
                    ellipse(x - 26, y - 32, 64, 72, n % 2 == 0 ? 0xE8ACBD : 0xF1C4CF)
                    ellipse(x - 14, y - 22, 40, 49, 0xF8DDE2, 0.6)
                }
                ellipse(118 + shift, 156, 43, 43, 0xDBBC83)
                for _ in 0..<19 { ellipse(124 + shift + random.next() * 28, 161 + random.next() * 28, 2, 2, 0xAE8C58) }
            case .city:
                gradient(0x343E60, 0xD29B81, to: 290)
                ellipse(226 + shift, 174, 30, 30, 0xF4D1A8)
                for n in 0..<9 {
                    let x = CGFloat(n) * 38 - 16
                    let top = 207 + random.next() * 70
                    rect(x, top, 32, 400 - top, n % 2 == 0 ? 0x293347 : 0x3D4257)
                    for row in 0..<7 {
                        for col in 0..<3 where random.next() > 0.38 {
                            rect(x + 5 + CGFloat(col) * 8, top + 12 + CGFloat(row) * 16, 3, 6, 0xE9C795, 0.8)
                        }
                    }
                }
                polygon([CGPoint(x: 115, y: 400), CGPoint(x: 164, y: 282), CGPoint(x: 187, y: 400)], 0x61545B)
            case .clouds:
                gradient(0x86ADC8, 0xD9E3E6)
                for n in 0..<7 {
                    let x = CGFloat(n % 3) * 119 - 45 + shift
                    let y = 75 + CGFloat(n / 3) * 99
                    for puff in 0..<4 {
                        ellipse(x + CGFloat(puff) * 23, y + random.next() * 14, 78, 35 + random.next() * 27, 0xFCFAF4, 0.7)
                    }
                }
                polygon([CGPoint(x: 0, y: 375), CGPoint(x: 112, y: 354), CGPoint(x: 300, y: 385), CGPoint(x: 300, y: 400), CGPoint(x: 0, y: 400)], 0xA1B3B6)
            case .food:
                gradient(0xCAA47D, 0xAD8060)
                for n in 0..<10 { line(CGFloat(n) * 35, 0, CGFloat(n) * 35 - 19, 400, 1.2, 0x79543B, 0.22) }
                polygon([CGPoint(x: 0, y: 55), CGPoint(x: 67, y: 29), CGPoint(x: 218, y: 400), CGPoint(x: 94, y: 400)], 0xDED2BB)
                ellipse(52, 146, 208, 193, 0x76563F, 0.23)
                ellipse(44, 133, 208, 193, 0xF5EDDB)
                ellipse(62, 150, 172, 159, 0xE2D8BD)
                for _ in 0..<29 {
                    let x = 91 + random.next() * 105, y = 183 + random.next() * 87
                    ellipse(x, y, 19 + random.next() * 17, 9 + random.next() * 13, random.next() > 0.5 ? 0x72905A : 0xA6AE6B)
                }
                for n in 0..<5 { ellipse(99 + CGFloat(n) * 21 + shift, 216 + CGFloat(n % 2) * 22, 21, 18, 0xC87752) }
                ellipse(207, 42, 70, 70, 0xEEE6D7)
                ellipse(214, 49, 56, 56, 0x775741)
                line(264, 151, 264, 312, 4, 0xD9D4CA)
                line(273, 151, 273, 312, 3, 0xE7E0D4)
            case .mountain:
                gradient(0xAFCBDD, 0xE9EEF0)
                polygon([CGPoint(x: 0, y: 324), CGPoint(x: 118 + shift, y: 107), CGPoint(x: 220, y: 318), CGPoint(x: 300, y: 188), CGPoint(x: 300, y: 400), CGPoint(x: 0, y: 400)], 0x8B9EAF)
                polygon([CGPoint(x: 49, y: 231), CGPoint(x: 118 + shift, y: 107), CGPoint(x: 180, y: 227), CGPoint(x: 141, y: 209), CGPoint(x: 111, y: 239), CGPoint(x: 88, y: 203)], 0xF5F4EB)
                polygon([CGPoint(x: 118 + shift, y: 107), CGPoint(x: 146, y: 288), CGPoint(x: 220, y: 318)], 0x697F96)
                polygon([CGPoint(x: 0, y: 332), CGPoint(x: 88, y: 280), CGPoint(x: 300, y: 351), CGPoint(x: 300, y: 400), CGPoint(x: 0, y: 400)], 0xDAE3E6)
                for n in 0..<8 {
                    let x = CGFloat(n) * 44 + shift, y = 336 + random.next() * 32
                    polygon([CGPoint(x: x - 7, y: y), CGPoint(x: x, y: y - 33), CGPoint(x: x + 7, y: y)], 0x496675)
                }
            case .night:
                gradient(0x172239, 0x4D5167)
                rect(0, 131, 68, 269, 0x1F2D41); rect(223, 114, 77, 286, 0x253044)
                polygon([CGPoint(x: 67, y: 400), CGPoint(x: 143, y: 235), CGPoint(x: 161, y: 235), CGPoint(x: 260, y: 400)], 0x444756)
                for side in 0..<2 {
                    for n in 0..<4 {
                        let depth = CGFloat(n), x = side == 0 ? 31 + depth * 30 : 277 - depth * 30
                        let y = 141 + depth * 32
                        line(x, y, x, y + 151 - depth * 22, 2.5, 0x8A8A8D)
                        ellipse(x - 17, y - 16, 34, 34, 0xECC588, 0.12)
                        ellipse(x - 5, y - 4, 10, 8, 0xFFE3A2)
                        line(x - 4, 354 - depth * 17, x + 5, 379 - depth * 23, 3, 0xD6B17F, 0.25)
                    }
                }
                for _ in 0..<11 { ellipse(115 + random.next() * 85, 258 + random.next() * 98, 4, 4, 0xF3C693, 0.7) }
            }
            for _ in 0..<220 {
                ellipse(random.next() * 300, random.next() * 400, 0.7, 0.7, 0xFFFFFF, 0.08)
            }
        }
    }
}
