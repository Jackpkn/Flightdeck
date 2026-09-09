import CoreText
import Foundation

/// Registers the real Inter + JetBrains Mono variable fonts bundled with the app —
/// the actual typefaces Raycast's own site uses (verified from their shipped CSS),
/// not a system-font stand-in.
enum FontLoader {
    static func registerBundledFonts() {
        register(name: "Inter-Variable")
        register(name: "JetBrainsMono-Variable")
        register(name: "Orbitron-Variable")
    }

    private static func register(name: String) {
        guard let url = Bundle.module.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts") else {
            print("FontLoader: could not locate \(name).ttf in bundle")
            return
        }
        var error: Unmanaged<CFError>?
        let ok = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        if !ok, let error {
            print("FontLoader: failed to register \(name): \(error.takeRetainedValue())")
        }
    }
}
