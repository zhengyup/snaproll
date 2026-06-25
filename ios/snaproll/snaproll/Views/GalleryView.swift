import SwiftUI

struct GalleryView: View {
    let roll: Roll
    let photoItems: [RevealPhotoItem]
    let isLoading: Bool
    let onClose: () -> Void

    @State private var selectedIndex = 0

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()

                if isLoading {
                    loadingState
                } else if photoItems.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 0) {
                        topChrome
                            .padding(.horizontal, 24)
                            .padding(.top, 18)

                        Spacer(minLength: 28)

                        selectedPhotoView(maxWidth: geometry.size.width)

                        Spacer(minLength: 28)

                        thumbnailStrip
                            .padding(.horizontal, 18)
                            .padding(.bottom, 28)
                    }
                }
            }
        }
        .onAppear {
            clampSelection()
        }
        .onChange(of: photoItems.count) {
            clampSelection()
        }
    }

    private var topChrome: some View {
        HStack(spacing: 16) {
            Button {
                onClose()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppTheme.creamText)
                    .frame(width: 42, height: 42)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: 4) {
                Text(roll.name)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.creamText)
                    .lineLimit(1)

                Text(headerDateText)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.softText)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.08))
            .clipShape(Capsule())

            Spacer()

            Circle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 42, height: 42)
                .overlay(
                    Image(systemName: "ellipsis")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(AppTheme.creamText)
                )
        }
    }

    private func selectedPhotoView(maxWidth: CGFloat) -> some View {
        let currentItem = photoItems[selectedIndex]

        return VStack(spacing: 0) {
            if let image = currentItem.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: maxWidth, alignment: .center)
                    .background(Color.black)
            } else {
                ZStack {
                    Rectangle()
                        .fill(Color.black)

                    VStack(spacing: 12) {
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundStyle(AppTheme.softText)

                        Text("This exposure is unavailable.")
                            .font(.headline)
                            .foregroundStyle(AppTheme.creamText)
                    }
                }
                .frame(width: maxWidth, height: maxWidth * 0.75)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var thumbnailStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(photoItems.enumerated()), id: \.element.id) { index, item in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedIndex = index
                            }
                            proxy.scrollTo(item.id, anchor: .center)
                        } label: {
                            thumbnail(for: item, isSelected: index == selectedIndex)
                        }
                        .buttonStyle(.plain)
                        .id(item.id)
                    }
                }
                .padding(.horizontal, 4)
            }
            .onAppear {
                guard photoItems.indices.contains(selectedIndex) else {
                    return
                }

                proxy.scrollTo(photoItems[selectedIndex].id, anchor: .center)
            }
            .onChange(of: selectedIndex) {
                guard photoItems.indices.contains(selectedIndex) else {
                    return
                }

                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(photoItems[selectedIndex].id, anchor: .center)
                }
            }
        }
    }

    private func thumbnail(for item: RevealPhotoItem, isSelected: Bool) -> some View {
        Group {
            if let image = item.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: thumbnailWidth(for: item), height: 66)
            } else {
                ZStack {
                    Rectangle()
                        .fill(Color.white.opacity(0.06))

                    Image(systemName: "photo")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.softText)
                }
                .frame(width: thumbnailWidth(for: item), height: 66)
            }
        }
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(isSelected ? AppTheme.creamText : Color.white.opacity(0.08), lineWidth: isSelected ? 2 : 1)
        )
        .opacity(isSelected ? 1 : 0.8)
    }

    private func thumbnailWidth(for item: RevealPhotoItem) -> CGFloat {
        let clampedRatio = min(max(item.aspectRatio, 0.56), 1.8)
        return 66 * clampedRatio
    }

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(AppTheme.primaryAction)
                .scaleEffect(1.1)

            Text("Developing your finished roll")
                .font(.headline)
                .foregroundStyle(AppTheme.softText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo")
                .font(.largeTitle)
                .foregroundStyle(AppTheme.softText)

            Text("This roll has been opened, but its images could not be loaded.")
                .font(.headline)
                .foregroundStyle(AppTheme.creamText)
                .multilineTextAlignment(.center)

            Button {
                onClose()
            } label: {
                Text("Back")
                    .font(.headline)
                    .foregroundStyle(Color.black.opacity(0.9))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(AppTheme.primaryAction)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var headerDateText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yy"
        return formatter.string(from: roll.createdAt)
    }

    private func clampSelection() {
        guard !photoItems.isEmpty else {
            selectedIndex = 0
            return
        }

        selectedIndex = min(selectedIndex, photoItems.count - 1)
    }
}

struct GalleryView_Previews: PreviewProvider {
    static var previews: some View {
        GalleryView(
            roll: Roll.placeholder.markingRevealed(),
            photoItems: [],
            isLoading: false,
            onClose: {}
        )
    }
}
