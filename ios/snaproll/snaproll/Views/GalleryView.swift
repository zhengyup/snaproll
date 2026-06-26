import SwiftUI

struct GalleryView: View {
    let roll: Roll
    let photoItems: [RevealPhotoItem]
    let isLoading: Bool
    let isExporting: Bool
    let onClose: () -> Void
    let onExportRoll: () -> Void
    let onShareRoll: () -> Void
    let onExportPhoto: (RevealPhotoItem) -> Void
    let onSharePhoto: (RevealPhotoItem) -> Void

    @State private var selectedIndex: Int?

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if isLoading {
                loadingState
            } else if photoItems.isEmpty {
                emptyState
            } else if let selectedIndex {
                singlePhotoView(selectedIndex: selectedIndex)
                    .transition(.opacity)
            } else {
                contactSheetView
                    .transition(.opacity)
            }
        }
    }

    private var contactSheetView: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(contactSheetTitle)
                            .font(.system(size: 30, weight: .bold, design: .serif))
                            .italic()
                            .foregroundStyle(AppTheme.creamText)

                        Text(roll.film.displayName)
                            .font(.headline)
                            .foregroundStyle(AppTheme.color(from: roll.film.accentHex))

                        Text("\(roll.shotLimit) Exposures")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.softText)
                    }

                    Spacer()

                    HStack(spacing: 10) {
                        circleButton(symbol: "chevron.left") {
                            onClose()
                        }

                        Menu {
                            Button("Export Roll") {
                                onExportRoll()
                            }

                            Button("Share Roll") {
                                onShareRoll()
                            }
                        } label: {
                            circleButtonLabel(symbol: "ellipsis")
                        }
                    }
                }

                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(Array(photoItems.enumerated()), id: \.element.id) { index, item in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedIndex = index
                            }
                        } label: {
                            ContactSheetCell(item: item, exposureNumber: index + 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 28)
        }
    }

    private func singlePhotoView(selectedIndex: Int) -> some View {
        let currentItem = photoItems[selectedIndex]

        return VStack(spacing: 0) {
            HStack {
                circleButton(symbol: "chevron.left") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        self.selectedIndex = nil
                    }
                }

                Spacer()

                Text("\(selectedIndex + 1) of \(photoItems.count)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.creamText)

                Spacer()

                Menu {
                    Button(isExporting ? "Exporting..." : "Export Photo") {
                        onExportPhoto(currentItem)
                    }
                    .disabled(isExporting)

                    Button("Share Photo") {
                        onSharePhoto(currentItem)
                    }
                } label: {
                    circleButtonLabel(symbol: "ellipsis")
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)

            Spacer(minLength: 28)

            TabView(selection: Binding(
                get: { selectedIndex },
                set: { self.selectedIndex = $0 }
            )) {
                ForEach(Array(photoItems.enumerated()), id: \.element.id) { index, item in
                    selectedPhotoPage(item: item)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            Spacer(minLength: 18)

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(contactSheetTitle)
                        .font(.headline)
                        .foregroundStyle(AppTheme.creamText)

                    Text(roll.film.displayName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.color(from: roll.film.accentHex))
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    Text("\(selectedIndex + 1) of \(photoItems.count)")
                        .font(.headline)
                        .foregroundStyle(AppTheme.creamText)

                    Text(capturedText(for: currentItem))
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.softText)
                }
            }
            .padding(.horizontal, 24)

            pageDots(currentIndex: selectedIndex)
                .padding(.top, 16)
                .padding(.bottom, 28)
        }
    }

    private func selectedPhotoPage(item: RevealPhotoItem) -> some View {
        GeometryReader { geometry in
            VStack {
                Spacer(minLength: 0)

                if let image = item.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: geometry.size.width, maxHeight: geometry.size.height)
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
                    .frame(maxWidth: geometry.size.width, maxHeight: geometry.size.height * 0.72)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
        }
    }

    private func circleButton(symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            circleButtonLabel(symbol: symbol)
        }
        .buttonStyle(.plain)
    }

    private func circleButtonLabel(symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.headline.weight(.semibold))
            .foregroundStyle(AppTheme.creamText)
            .frame(width: 42, height: 42)
            .background(Color.white.opacity(0.08))
            .clipShape(Circle())
    }

    private func pageDots(currentIndex: Int) -> some View {
        HStack(spacing: 7) {
            ForEach(photoItems.indices, id: \.self) { index in
                Circle()
                    .fill(index == currentIndex ? AppTheme.creamText : Color.white.opacity(0.18))
                    .frame(width: 6, height: 6)
            }
        }
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

    private var contactSheetTitle: String {
        roll.name
    }

    private func capturedText(for item: RevealPhotoItem) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy  h:mm a"
        return formatter.string(from: item.photo.createdAt)
    }
}

private struct ContactSheetCell: View {
    let item: RevealPhotoItem
    let exposureNumber: Int

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.black)

                if let image = item.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "photo")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.softText)
                }
            }
            .frame(height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

            Text("\(exposureNumber)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.softText)
        }
    }
}

struct GalleryView_Previews: PreviewProvider {
    static var previews: some View {
        GalleryView(
            roll: Roll.placeholder.markingRevealed(),
            photoItems: [],
            isLoading: false,
            isExporting: false,
            onClose: {},
            onExportRoll: {},
            onShareRoll: {},
            onExportPhoto: { _ in },
            onSharePhoto: { _ in }
        )
    }
}
