import SwiftUI

extension Font {
    static let displayKanji = Font.system(size: 96, weight: .regular, design: .serif)
    static let displayWord = Font.system(size: 72, weight: .regular, design: .serif)
    static let sentenceLarge = Font.system(size: 32, weight: .regular, design: .serif)
}

extension View {
    func cardChrome(cornerRadius: CGFloat = 20, padding: CGFloat = 24) -> some View {
        self
            .padding(padding)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 2)
    }
}
