import SwiftUI

struct OpenOatsProminentButtonStyle: ButtonStyle {
    var color: Color = .accentColor

    func makeBody(configuration: Configuration) -> some View {
        ProminentButtonBody(configuration: configuration, color: color)
    }
}

private struct ProminentButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let color: Color

    @Environment(\.controlSize) private var controlSize
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .foregroundStyle(.white)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(color)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.88 : 1.0) : 0.5)
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var horizontalPadding: CGFloat {
        switch controlSize {
        case .mini:
            return 8
        case .small:
            return 10
        case .large:
            return 14
        case .regular, .extraLarge:
            return 12
        @unknown default:
            return 12
        }
    }

    private var verticalPadding: CGFloat {
        switch controlSize {
        case .mini:
            return 4
        case .small:
            return 6
        case .large:
            return 9
        case .regular, .extraLarge:
            return 7
        @unknown default:
            return 7
        }
    }

    private var cornerRadius: CGFloat {
        switch controlSize {
        case .mini:
            return 6
        case .small:
            return 7
        case .large:
            return 10
        case .regular, .extraLarge:
            return 8
        @unknown default:
            return 8
        }
    }
}
