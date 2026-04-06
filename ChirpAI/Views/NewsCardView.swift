import SwiftUI

struct NewsCardView: View {
    let news: NewsItem
    let onTap: () -> Void
    let onLike: () -> Void
    let onNeutral: () -> Void
    let onDislike: () -> Void
    let onLikeLongPress: () -> Void
    let onNeutralLongPress: () -> Void
    let onDislikeLongPress: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    
    private var currentAction: FeedbackAction? {
        // Find the first feedback associated with this news
        news.feedbacks.first?.feedbackAction
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            
            // 1. AI Reasoning Block
            if let reasoning = news.reasoning, !reasoning.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "sparkles")
                        .foregroundColor(.purple)
                        .font(.system(size: 14, weight: .semibold))
                    Text(reasoning)
                        .font(.system(.footnote, design: .rounded))
                        .fontWeight(.medium)
                        .foregroundColor(Color.purple.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.purple.opacity(0.1))
                .cornerRadius(10)
            }
            
            // 2. Title
            Text(news.title)
                .font(.system(.title3, design: .default))
                .fontWeight(.bold)
                .lineLimit(3)
                .foregroundColor(.primary)
            
            // 3. Summary
            Text(news.summary)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(4)
                .lineSpacing(4)
            
            // 4. Source & Metadata
            HStack {
                Text(news.sourceName)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Capsule())
                
                Spacer()
                
                Text(news.publishedAt, style: .relative)
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.8))
            }
            .padding(.top, 4)
            
            Divider()
                .padding(.vertical, 4)
            
            // 5. Action Buttons (Modern Glassmorphic Style)
            HStack(spacing: 0) {
                ActionButton(
                    icon: "hand.thumbsup.fill",
                    text: "赞",
                    color: .green,
                    isActive: currentAction == .like,
                    action: {
                        playHaptic()
                        onLike()
                    },
                    longPressAction: {
                        playHaptic(heavy: true)
                        onLikeLongPress()
                    }
                )
                
                Spacer()
                
                ActionButton(
                    icon: "eyes",
                    text: "一般",
                    color: .gray,
                    isActive: currentAction == .neutral,
                    action: {
                        playHaptic()
                        onNeutral()
                    },
                    longPressAction: {
                        playHaptic(heavy: true)
                        onNeutralLongPress()
                    }
                )
                
                Spacer()
                
                ActionButton(
                    icon: "hand.thumbsdown.fill",
                    text: "踩",
                    color: .red,
                    isActive: currentAction == .dislike,
                    action: {
                        playHaptic()
                        onDislike()
                    },
                    longPressAction: {
                        playHaptic(heavy: true)
                        onDislikeLongPress()
                    }
                )
            }
        }
        .padding(16)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.2 : 0.06), radius: 10, x: 0, y: 4)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
    
    private func playHaptic(heavy: Bool = false) {
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: heavy ? .heavy : .light)
        generator.impactOccurred()
        #endif
    }
}

struct ActionButton: View {
    let icon: String
    let text: String
    let color: Color
    let isActive: Bool
    let action: () -> Void
    let longPressAction: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                Text(text)
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundColor(isActive ? .white : color)
            .padding(.vertical, 8)
            .padding(.horizontal, 24)
            .background(isActive ? color : color.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(BorderlessButtonStyle())
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in
                    longPressAction()
                }
        )
    }
}
