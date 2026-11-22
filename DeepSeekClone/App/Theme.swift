import SwiftUI
import UIKit

/// 全局设计令牌：尽量贴近 DeepSeek 官方 App 的观感（品牌蓝 #4D6BFE、大圆角、克制留白）。
enum DSTheme {
    static let accent = Color(red: 0.302, green: 0.420, blue: 0.996)
    static let accentDeep = Color(red: 0.196, green: 0.239, blue: 0.902)

    static var background: Color { Color(uiColor: .systemBackground) }

    static var surface: Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0.125, green: 0.133, blue: 0.153, alpha: 1)
                : UIColor(red: 0.961, green: 0.965, blue: 0.976, alpha: 1)
        })
    }

    static var surfaceStrong: Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0.169, green: 0.180, blue: 0.204, alpha: 1)
                : UIColor(red: 0.925, green: 0.933, blue: 0.949, alpha: 1)
        })
    }

    static var sidebar: Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0.071, green: 0.075, blue: 0.094, alpha: 1)
                : UIColor(red: 0.973, green: 0.976, blue: 0.984, alpha: 1)
        })
    }

    static var textPrimary: Color { Color(uiColor: .label) }
    static var textSecondary: Color { Color(uiColor: .secondaryLabel) }
    static var hairline: Color { Color(uiColor: .separator) }

    static let bubbleRadius: CGFloat = 20
    static let cardRadius: CGFloat = 16

    static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        if Calendar.current.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
        } else if Calendar.current.isDateInYesterday(date) {
            return "昨天"
        } else {
            formatter.dateFormat = "M月d日"
        }
        return formatter.string(from: date)
    }
}

/// DeepSeek 小鲸鱼风格头像。
struct AssistantAvatar: View {
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: "fish.fill")
            .font(.system(size: size * 0.46, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(
                    colors: [DSTheme.accent, DSTheme.accentDeep],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: Circle()
            )
    }
}
