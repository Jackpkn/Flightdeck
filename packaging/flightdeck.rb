# Homebrew formula for Flightdeck.
#
# This is a formula and not a cask on purpose. macOS applies
# `com.apple.quarantine` at *download* time, and only browsers (and Homebrew's
# own cask installer) do it. Homebrew formulas fetch with curl, which does not,
# so the app installed by this formula is never quarantined and Gatekeeper never
# engages — no certificate, no dialog, no `xattr` command for the user.
#
# A cask cannot do the same job: Homebrew 6 removed `--no-quarantine`, so casks
# always quarantine and an un-notarised app installed by one would be blocked.
#
#   brew tap Jackpkn/flightdeck
#   brew install flightdeck
class Flightdeck < Formula
  desc "macOS activity monitor that measures what your Claude Code spend produced"
  homepage "https://github.com/Jackpkn/Flightdeck-releases"
  url "https://github.com/Jackpkn/Flightdeck-releases/releases/download/v0.1.0/Flightdeck-0.1.0-universal.tar.gz"
  sha256 "fbf17125cd74a1b005c10b2533866a585a12ecbbd7303b80bfddc401bca6449a"
  version "0.1.0"
  license "MIT"

  depends_on macos: :sonoma

  def install
    prefix.install "Flightdeck.app"
    # So `flightdeck` works from a terminal as well as from the Dock.
    bin.write_exec_script "#{prefix}/Flightdeck.app/Contents/MacOS/Flightdeck"
  end

  def caveats
    <<~EOS
      Run it now:
        flightdeck

      Homebrew installed this rather than a browser downloading it, so macOS did
      not attach a quarantine flag and Gatekeeper will not prompt you — even
      though Flightdeck is not notarised with a paid Apple Developer certificate.

      Optional, to get it in Spotlight and the Dock (Homebrew sandboxes the
      install, so it cannot make this link itself):
        ln -sfn #{opt_prefix}/Flightdeck.app /Applications/Flightdeck.app

      Everything it reads stays on this Mac. To see live context and tool activity
      it can add a statusline and hooks to ~/.claude/settings.json — it asks first,
      shows you the change, and backs the file up.

      Press Shift-Command-P for presentation mode before screensharing: it masks
      project names and paths, and never masks a number.
    EOS
  end

  test do
    app = prefix/"Flightdeck.app/Contents/MacOS/Flightdeck"
    assert_predicate app, :executable?
    assert_match "arm64", shell_output("lipo -archs #{app}")
    # The whole point of this formula: no quarantine flag on what it installed.
    refute_match "com.apple.quarantine", shell_output("xattr #{prefix}/Flightdeck.app 2>&1")
  end
end
