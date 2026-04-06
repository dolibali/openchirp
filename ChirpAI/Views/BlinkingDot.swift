import SwiftUI

/// 一个自包含的呼吸灯小圆点，不受父组件重新渲染影响
struct BlinkingDot: View {
    @State private var opacity: Double = 1.0
    
    var body: some View {
        Circle()
            .fill(Color.accentColor)
            .frame(width: 5, height: 5)
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    opacity = 0.3
                }
            }
    }
}
