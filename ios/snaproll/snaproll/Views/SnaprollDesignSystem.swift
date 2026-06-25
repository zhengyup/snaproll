import SwiftUI

struct SnaprollScreenBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    AppTheme.background,
                    Color(red: 0.09, green: 0.08, blue: 0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(AppTheme.backgroundGlow.opacity(0.22))
                .frame(width: 320, height: 320)
                .blur(radius: 90)
                .offset(x: -80, y: -240)

            Circle()
                .fill(AppTheme.backgroundGlow.opacity(0.10))
                .frame(width: 260, height: 260)
                .blur(radius: 100)
                .offset(x: 130, y: 220)
        }
    }
}

struct SnaprollPanelBackground: View {
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(AppTheme.surface.opacity(0.92))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(AppTheme.border, lineWidth: 1)
            )
    }
}

struct FilmCanisterView: View {
    enum Size {
        case small
        case large

        var width: CGFloat {
            switch self {
            case .small: return 54
            case .large: return 138
            }
        }

        var height: CGFloat {
            switch self {
            case .small: return 78
            case .large: return 196
            }
        }

        var fontSize: CGFloat {
            switch self {
            case .small: return 9
            case .large: return 17
            }
        }
    }

    let film: FilmStock
    let size: Size

    var body: some View {
        let accent = AppTheme.color(from: film.accentHex)
        let secondary = AppTheme.color(from: film.secondaryHex)

        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: size == .small ? 10 : 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.black.opacity(0.88), Color(red: 0.18, green: 0.16, blue: 0.13)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: size.width, height: size.height)
                .overlay(
                    VStack(spacing: 0) {
                        RoundedRectangle(cornerRadius: size == .small ? 6 : 14, style: .continuous)
                            .fill(Color.black.opacity(0.85))
                            .frame(width: size.width * 0.72, height: size.height * 0.13)
                            .padding(.top, size == .small ? 4 : 10)

                        Spacer()

                        VStack(spacing: 0) {
                            Rectangle()
                                .fill(accent)
                                .frame(height: size.height * 0.17)

                            Rectangle()
                                .fill(secondary)
                                .frame(height: size.height * 0.42)
                                .overlay(
                                    VStack(spacing: size == .small ? 2 : 4) {
                                        Text(film.shortBrand)
                                            .font(.system(size: size.fontSize, weight: .heavy))
                                            .tracking(size == .small ? 1 : 2)
                                            .foregroundStyle(.white)

                                        Text(shortTitle)
                                            .font(.system(size: size == .small ? 5 : 10, weight: .medium))
                                            .foregroundStyle(.white.opacity(0.9))
                                    }
                                )

                            Rectangle()
                                .fill(accent)
                                .frame(height: size.height * 0.17)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: size == .small ? 5 : 10, style: .continuous))
                        .padding(.horizontal, size == .small ? 5 : 12)
                        .padding(.bottom, size == .small ? 6 : 14)
                    }
                )
                .shadow(color: Color.black.opacity(0.32), radius: 18, y: 10)

            RoundedRectangle(cornerRadius: size == .small ? 6 : 14, style: .continuous)
                .fill(Color(red: 0.30, green: 0.22, blue: 0.10).opacity(0.82))
                .frame(width: size.width * 0.36, height: size.height * 0.46)
                .offset(x: size.width * 0.14, y: -size.height * 0.09)
                .overlay(
                    HStack(spacing: size == .small ? 3 : 6) {
                        Circle()
                            .fill(Color.black.opacity(0.35))
                            .frame(width: size == .small ? 3 : 6, height: size == .small ? 3 : 6)
                        Circle()
                            .fill(Color.black.opacity(0.35))
                            .frame(width: size == .small ? 3 : 6, height: size == .small ? 3 : 6)
                    }
                    .offset(y: -size.height * 0.12)
                )
                .zIndex(-1)
        }
        .frame(width: size.width + size.width * 0.20, height: size.height)
    }

    private var shortTitle: String {
        switch film {
        case .kodakGold200:
            return "GOLD 200"
        case .fujifilmSuperia400:
            return "SUPERIA 400"
        case .ilfordHP5Plus:
            return "HP5 PLUS"
        }
    }
}
