import SwiftUI
import Foundation

public struct JellyfinAsyncImage: View {
    let url: URL?
    let fallback: LinearGradient

    public init(url: URL?, fallback: LinearGradient) {
        self.url = url
        self.fallback = fallback
    }

    public var body: some View {
        if let url {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .failure, .empty:
                    fallback
                @unknown default:
                    fallback
                }
            }
        } else {
            fallback
        }
    }
}
