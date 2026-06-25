import SwiftUI

struct GalleryView: View {
    let roll: Roll
    let photoItems: [RevealPhotoItem]
    let isLoading: Bool

    @State private var selectedIndex: Int?

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Text("REVEALED")
                    .font(.system(size: 14, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(AppTheme.primaryAction)

                Text(roll.name)
                    .font(.system(size: 38, weight: .bold, design: .serif))
                    .italic()
                    .foregroundStyle(AppTheme.creamText)

                Text(subtitle)
                    .font(.title3)
                    .foregroundStyle(AppTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(AppTheme.primaryAction)
                        .scaleEffect(1.1)

                    Text("Developing your finished roll")
                        .font(.headline)
                        .foregroundStyle(AppTheme.softText)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
            } else {
                LazyVGrid(columns: columns, spacing: 14) {
                    if photoItems.isEmpty {
                        missingRollCard
                    } else {
                        ForEach(Array(photoItems.enumerated()), id: \.element.id) { index, item in
                            Button {
                                selectedIndex = index
                            } label: {
                                GalleryPhotoCell(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .fullScreenCover(isPresented: isPhotoViewerPresented) {
            if let selectedIndex {
                PhotoViewerView(
                    rollName: roll.name,
                    photoItems: photoItems,
                    selectedIndex: selectedIndex
                ) {
                    self.selectedIndex = nil
                }
            }
        }
    }

    private var subtitle: String {
        if photoItems.isEmpty {
            return "This roll has been opened, but some memories are missing."
        }

        return "\(photoItems.count) memories, captured in order."
    }

    private var missingRollCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "photo")
                .font(.title2)
                .foregroundStyle(AppTheme.primaryAction)

            Text("This roll is open, but its images could not be loaded.")
                .font(.headline)
                .foregroundStyle(AppTheme.creamText)

            Text("Missing photos stay graceful here so the reveal never crashes.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.softText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .leading)
        .background(SnaprollPanelBackground(cornerRadius: 22))
        .gridCellColumns(2)
    }

    private var isPhotoViewerPresented: Binding<Bool> {
        Binding(
            get: { selectedIndex != nil },
            set: { isPresented in
                if !isPresented {
                    selectedIndex = nil
                }
            }
        )
    }
}

private struct GalleryPhotoCell: View {
    let item: RevealPhotoItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Group {
                if let image = item.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    ZStack {
                        Rectangle()
                            .fill(Color.white.opacity(0.05))

                        Image(systemName: "photo")
                            .font(.title2)
                            .foregroundStyle(AppTheme.softText)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(item.aspectRatio, contentMode: .fit)
            .frame(minHeight: item.isLandscape ? 120 : 220)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text("Exposure \(item.photo.exposureNumber)")
                    .font(.headline)
                    .foregroundStyle(AppTheme.creamText)

                Text(capturedText)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.softText)
            }
        }
    }

    private var capturedText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: item.photo.createdAt)
    }
}

private struct PhotoViewerView: View {
    let rollName: String
    let photoItems: [RevealPhotoItem]
    let onClose: () -> Void

    @State private var selectedIndex: Int

    init(rollName: String, photoItems: [RevealPhotoItem], selectedIndex: Int, onClose: @escaping () -> Void) {
        self.rollName = rollName
        self.photoItems = photoItems
        self.onClose = onClose
        _selectedIndex = State(initialValue: selectedIndex)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            TabView(selection: $selectedIndex) {
                ForEach(Array(photoItems.enumerated()), id: \.element.id) { index, item in
                    ZStack {
                        Color.black.ignoresSafeArea()

                        if let image = item.image {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 110)
                        } else {
                            VStack(spacing: 12) {
                                Image(systemName: "photo")
                                    .font(.largeTitle)
                                    .foregroundStyle(AppTheme.softText)

                                Text("This exposure is unavailable.")
                                    .font(.headline)
                                    .foregroundStyle(AppTheme.creamText)
                            }
                        }
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            VStack(spacing: 18) {
                HStack {
                    Button {
                        onClose()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(AppTheme.creamText)
                            .frame(width: 42, height: 42)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }

                VStack(spacing: 8) {
                    Text(rollName)
                        .font(.system(size: 30, weight: .bold, design: .serif))
                        .italic()
                        .foregroundStyle(AppTheme.creamText)

                    Text("Exposure \(currentItem.photo.exposureNumber) of \(photoItems.count)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.softText)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)

            VStack {
                Spacer()

                Text(capturedText)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.softText)
                    .padding(.bottom, 34)
            }
        }
    }

    private var currentItem: RevealPhotoItem {
        photoItems[selectedIndex]
    }

    private var capturedText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: currentItem.photo.createdAt)
    }
}

struct GalleryView_Previews: PreviewProvider {
    static var previews: some View {
        GalleryView(
            roll: Roll.placeholder.markingRevealed(),
            photoItems: [],
            isLoading: false
        )
    }
}
