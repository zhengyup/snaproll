import SwiftUI
import UIKit

protocol V2GalleryDisplayItem {
    var id: UUID { get }
    var exposureNumber: Int { get }
    var image: UIImage? { get }
    var pixelWidth: CGFloat { get }
    var pixelHeight: CGFloat { get }
}

extension V2PersonalRevealGalleryViewModel.GalleryItem: V2GalleryDisplayItem {}
extension V2SharedRevealGalleryViewModel.GalleryItem: V2GalleryDisplayItem {}

struct V2GalleryDiagnosticLine: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    var isError = false
}

struct V2GalleryFullscreenSelection: Identifiable {
    let index: Int
    var id: Int { index }
}

struct V2GalleryThumbnail<Item: V2GalleryDisplayItem>: View {
    let item: Item
    let placeholderText: String
    let showsDiagnostics: Bool
    let diagnostics: [V2GalleryDiagnosticLine]
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                GeometryReader { geometry in
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(.black.opacity(0.32))

                        if let image = item.image {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(
                                    width: geometry.size.width,
                                    height: geometry.size.height
                                )
                        } else {
                            VStack(spacing: 5) {
                                Image(systemName: "photo")
                                    .font(.headline)
                                Text(placeholderText)
                                    .font(.caption2)
                                    .multilineTextAlignment(.center)
                            }
                            .foregroundStyle(.white.opacity(0.66))
                            .padding(10)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .aspectRatio(
                    V2GalleryImageLayout.aspectRatio(width: item.pixelWidth, height: item.pixelHeight),
                    contentMode: .fit
                )

                HStack(spacing: 4) {
                    Text("\(item.exposureNumber)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.82))

                    Spacer(minLength: 0)
                }

                if showsDiagnostics {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(diagnostics) { line in
                            Text("\(line.title): \(line.value)")
                                .font(.caption2.monospaced())
                                .foregroundStyle(line.isError ? .red.opacity(0.82) : .white.opacity(0.62))
                                .lineLimit(2)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .padding(7)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(.white.opacity(0.075))
                    .overlay {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .strokeBorder(.white.opacity(0.10), lineWidth: 1)
                    }
            )
        }
        .buttonStyle(.plain)
    }
}

struct V2GalleryFullscreenViewer: View {
    let title: String
    let filmLabel: String
    let items: [any V2GalleryDisplayItem]
    let selectedIndex: Int
    let participantName: String?
    let onDismiss: () -> Void

    @State private var currentIndex: Int

    init(
        title: String,
        filmLabel: String,
        items: [any V2GalleryDisplayItem],
        selectedIndex: Int,
        participantName: String?,
        onDismiss: @escaping () -> Void
    ) {
        self.title = title
        self.filmLabel = filmLabel
        self.items = items
        self.selectedIndex = selectedIndex
        self.participantName = participantName
        self.onDismiss = onDismiss
        _currentIndex = State(initialValue: selectedIndex)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                TabView(selection: $currentIndex) {
                    ForEach(items.indices, id: \.self) { index in
                        imagePage(for: items[index])
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                footer
            }
        }
    }

    private var topBar: some View {
        HStack {
            Button(action: onDismiss) {
                Image(systemName: "chevron.left")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(.white.opacity(0.10))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            Text("\(currentIndex + 1) of \(items.count)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.88))

            Spacer()

            Color.clear.frame(width: 42, height: 42)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
    }

    private func imagePage(for item: any V2GalleryDisplayItem) -> some View {
        GeometryReader { geometry in
            VStack {
                Spacer(minLength: 0)

                if let image = item.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(
                            maxWidth: geometry.size.width,
                            maxHeight: geometry.size.height
                        )
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "photo")
                            .font(.largeTitle)
                        Text("This exposure is unavailable.")
                            .font(.headline)
                    }
                    .foregroundStyle(.white.opacity(0.70))
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var footer: some View {
        let item = items[currentIndex]

        return HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)

                Text(filmLabel)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.66))

                if let participantName {
                    Text(participantName)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.50))
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 5) {
                Text("Exposure \(item.exposureNumber)")
                    .font(.headline)
                    .foregroundStyle(.white)

                Text("\(Int(item.pixelWidth)) x \(Int(item.pixelHeight))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.48))
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
    }
}
