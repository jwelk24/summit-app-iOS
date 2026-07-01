import SwiftUI

/// Opt-in merchant logos. This is the ONLY Summit feature that reaches the
/// network with any user-derived data, so it's gated behind an explicit consent
/// toggle (`merchantLogosEnabled`, off by default). Uses a keyless favicon
/// service on a best-guess domain; swap in a dedicated logo API later if desired.
enum MerchantLogo {
    static func url(for merchant: String) -> URL? {
        let cleaned = MerchantCleaner.clean(merchant)
        let compact = cleaned.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
        guard compact.count >= 2 else { return nil }
        return URL(string: "https://www.google.com/s2/favicons?sz=128&domain=\(compact).com")
    }
}

/// Shows a merchant logo when enabled, falling back to the category dot while
/// loading or if the logo can't be found.
struct MerchantLogoView: View {
    let merchant: String
    let fallbackColor: Color
    let ringColor: Color?
    var size: CGFloat = 28

    var body: some View {
        if let url = MerchantLogo.url(for: merchant) {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(width: size, height: size)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(.white.opacity(0.08), lineWidth: 0.5)
                        )
                } else {
                    fallback
                }
            }
        } else {
            fallback
        }
    }

    private var fallback: some View {
        SummitCategoryDot(color: fallbackColor, ringColor: ringColor, size: 12)
            .frame(width: size, height: size)
    }
}
