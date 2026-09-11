# Homebrew formula — builds Flightdeck from source on the user's own machine.
#
# This is the free distribution path, and it is better than a signed download,
# not a workaround for the lack of one. `com.apple.quarantine` is applied by
# whatever fetched a file, so a locally compiled binary never carries it and
# Gatekeeper never engages. No Developer ID certificate is involved at any point.
#
# Install:
#   brew tap Jackpkn/flightdeck
#   brew install flightdeck
#
# Requires the source to be fetchable, so `url` must point at a public tarball.
class Flightdeck < Formula
  desc "macOS activity monitor and Claude Code cockpit"
  homepage "https://github.com/Jackpkn/Flightdeck"
  url "https://github.com/Jackpkn/Flightdeck/archive/refs/tags/v0.1.0.tar.gz"
  # Replace with: shasum -a 256 on the release tarball
  sha256 "REPLACE_WITH_TARBALL_SHA256"
  license "MIT"
  head "https://github.com/Jackpkn/Flightdeck.git", branch: "main"

  depends_on xcode: ["15.0", :build]
  depends_on macos: :sonoma
  depends_on :macos

  def install
    # Universal so the same formula serves Apple silicon and Intel.
    system "swift", "build",
           "--disable-sandbox",
           "-c", "release",
           "--arch", "arm64",
           "--arch", "x86_64"

    binary = `swift build -c release --arch arm64 --arch x86_64 --show-bin-path`.strip
    app = "#{buildpath}/Flightdeck.app"

    # A bare SPM executable has no Info.plist and no main menu, and on macOS
    # SwiftUI routes .keyboardShortcut through the main menu — so the command-key
    # shortcuts silently do nothing unbundled. Always assemble the bundle.
    system "./scripts/make-app.sh", "#{binary}/Flightdeck", app, version.to_s, "brew"

    prefix.install app
    bin.write_exec_script "#{prefix}/Flightdeck.app/Contents/MacOS/Flightdeck"
  end

  def caveats
    <<~EOS
      Flightdeck was compiled on this machine, so macOS does not quarantine it and
      Gatekeeper will not prompt you.

      Launch it from Applications or Spotlight:
        open #{prefix}/Flightdeck.app

      Everything it reads stays on this Mac. To let it see live context and tool
      activity it can add a statusline and hooks to ~/.claude/settings.json — it
      asks first, shows you the change, and backs the file up.
    EOS
  end

  test do
    assert_predicate prefix/"Flightdeck.app/Contents/MacOS/Flightdeck", :executable?
    assert_match "arm64", shell_output("lipo -archs #{prefix}/Flightdeck.app/Contents/MacOS/Flightdeck")
  end
end
