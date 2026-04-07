import SwiftUI
import Kingfisher

struct CachedStickerImage: View {
    let url: URL?
    let cacheKey: String
    let contentMode: SwiftUI.ContentMode
    private let placeholder: () -> AnyView
    private let failure: () -> AnyView

    @State private var didFail = false
    @State private var cacheStatusLabel = "loading"

    init<Placeholder: View, Failure: View>(
        url: URL?,
        cacheKey: String,
        contentMode: SwiftUI.ContentMode,
        @ViewBuilder placeholder: @escaping () -> Placeholder,
        @ViewBuilder failure: @escaping () -> Failure
    ) {
        self.url = url
        self.cacheKey = cacheKey
        self.contentMode = contentMode
        self.placeholder = { AnyView(placeholder()) }
        self.failure = { AnyView(failure()) }
    }

    var body: some View {
        if didFail || url == nil {
            failure()
        } else if let url {
            KFImage(source: .network(ImageResource(downloadURL: url, cacheKey: cacheKey)))
                .placeholder { placeholder() }
                .onSuccess { result in
                    let status = cacheLabel(for: result.cacheType)
                    cacheStatusLabel = status
                    #if DEBUG
                    print("[StickerCache] key=\(cacheKey) status=\(status)")
                    #endif
                }
                .onFailure { error in
                    didFail = true
                    cacheStatusLabel = "error"
                    #if DEBUG
                    print("[StickerCache] key=\(cacheKey) status=error reason=\(error.localizedDescription)")
                    #endif
                }
                .cancelOnDisappear(true)
                .cacheOriginalImage()
                .fade(duration: 0.15)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: contentMode)
                .overlay(alignment: .bottomTrailing) {
                    #if DEBUG
                    Text(cacheStatusLabel.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(6)
                    #endif
                }
        }
    }

    private func cacheLabel(for cacheType: CacheType) -> String {
        switch cacheType {
        case .none:
            return "network"
        case .memory:
            return "memory"
        case .disk:
            return "disk"
        }
    }
}
