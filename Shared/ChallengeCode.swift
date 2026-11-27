import Foundation

enum ChallengeCode {
    static let defaultGoal = 100
    static let goalRange = 1...10_000
    private static let prefix = "PC1."

    static func encode(goal: Int) -> String { prefix + String(goal) }

    static func decode(_ text: String) -> Int? {
        for line in text.split(whereSeparator: \.isNewline) {
            let token = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard token.hasPrefix(prefix) else { continue }
            let digits = token.dropFirst(prefix.count)
            guard (1...5).contains(digits.utf8.count), digits.first != "0",
                  digits.utf8.allSatisfy({ (48...57).contains($0) }),
                  let goal = Int(digits), goalRange.contains(goal) else { continue }
            return goal
        }
        return nil
    }

    static var title: String { L.t("30 天相册断舍离") }

    static func goalText(_ goal: Int) -> String {
        L.f("目标整理 %@ 张照片", goal.formatted())
    }

    static func invitation(goal: Int, downloadURL: URL?) -> String {
        [title, goalText(goal), L.t("复制口令，打开相册清理即可导入。"), encode(goal: goal),
         downloadURL?.absoluteString ?? L.t("在 App Store 搜索「相册清理」")].joined(separator: "\n")
    }
}
