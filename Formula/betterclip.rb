class Betterclip < Formula
  desc "Smart clipboard manager for macOS with snippets and history search"
  homepage "https://github.com/yarin-mag/BetterClip"
  license "MIT"

  version "1.0.1"
  url "https://github.com/yarin-mag/BetterClip/releases/download/v#{version}/BetterClip.dmg"
  sha256 "b1d1e6c1d8c8a1e8c1d8c1d8c1d8c1d8c1d8c1d8c1d8c1d8c1d8c1d8c1d8c1" # placeholder

  depends_on :macos => :monterey

  app "BetterClip.app"

  post_install do
    # Grant execute permissions if needed
    system("chmod", "+x", "#{appdir}/BetterClip.app/Contents/MacOS/BetterClip")
  end

  def caveats
    <<~EOS
      BetterClip has been installed! 🎉
      
      Global hotkey: ⌘⇧V (Command+Shift+V)
      
      To launch:
        open -a BetterClip
      
      To launch at login:
        Open BetterClip → Preferences → General → "Launch at login"
    EOS
  end
end
