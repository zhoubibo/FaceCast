import SwiftUI

enum StudioPalette {
    static let paper = Color(red: 0.98, green: 0.96, blue: 0.92)
    static let ink = Color(red: 0.12, green: 0.12, blue: 0.14)
    static let mutedInk = Color(red: 0.40, green: 0.38, blue: 0.35)
    static let card = Color.white.opacity(0.88)
    static let stroke = Color.white.opacity(0.72)
    static let accent = Color(red: 0.95, green: 0.39, blue: 0.31)
    static let accentDeep = Color(red: 0.79, green: 0.18, blue: 0.13)
    static let gold = Color(red: 0.95, green: 0.76, blue: 0.33)
    static let success = Color(red: 0.18, green: 0.66, blue: 0.42)
    static let warning = Color(red: 0.92, green: 0.56, blue: 0.20)
}

struct StudioPanelBackground: ViewModifier {
    func body(content: Content) -> some View {
        ZStack {
            LinearGradient(
                colors: [
                    StudioPalette.paper,
                    Color(red: 0.99, green: 0.92, blue: 0.86)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(StudioPalette.gold.opacity(0.16))
                .frame(width: 220, height: 220)
                .blur(radius: 6)
                .offset(x: 150, y: -170)

            Circle()
                .fill(StudioPalette.accent.opacity(0.14))
                .frame(width: 260, height: 260)
                .blur(radius: 12)
                .offset(x: -170, y: 210)

            content
        }
    }
}

extension View {
    func studioPanelBackground() -> some View {
        modifier(StudioPanelBackground())
    }
}

struct StudioCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(StudioPalette.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(StudioPalette.stroke, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 22, x: 0, y: 10)
    }
}

struct StudioPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: [StudioPalette.accent, StudioPalette.accentDeep],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: StudioPalette.accent.opacity(0.26), radius: 18, x: 0, y: 10)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct StudioSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(StudioPalette.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.94 : 0.78))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.84), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct StudioTag: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.12))
            .clipShape(Capsule())
    }
}

struct StudioMetric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.1)
                .foregroundStyle(StudioPalette.mutedInk)

            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(StudioPalette.ink)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct StudioInlineMetric: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1)
                .foregroundStyle(StudioPalette.mutedInk)

            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(StudioPalette.ink)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct StudioWaveform: View {
    let isActive: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.12, paused: !isActive)) { context in
            let time = context.date.timeIntervalSinceReferenceDate

            HStack(alignment: .center, spacing: 4) {
                ForEach(0..<9, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [StudioPalette.accent, StudioPalette.gold],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(width: 4, height: barHeight(index: index, time: time))
                }
            }
            .frame(height: 26)
        }
    }

    private func barHeight(index: Int, time: TimeInterval) -> CGFloat {
        guard isActive else { return 6 }
        let phase = time * 4.8 + Double(index) * 0.55
        let wave = (sin(phase) + cos(phase * 0.72)) * 0.5
        return 8 + CGFloat(abs(wave)) * 16
    }
}
