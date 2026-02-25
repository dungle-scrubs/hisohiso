class Hisohiso < Formula
  desc "Local-first macOS dictation app with multi-backend transcription"
  homepage "https://github.com/dungle-scrubs/hisohiso"
  url "https://github.com/dungle-scrubs/hisohiso/archive/refs/tags/v0.2.1.tar.gz"
  sha256 "fa10f3c3c0d1f0f787f6722d109f0a31f1e90f823dfed1e33f523ca77d3abed9"
  license "MIT"

  depends_on :macos
  depends_on macos: :sonoma
  depends_on xcode: ["15.0", :build]
  depends_on arch: :arm64

  def install
    system "swift", "build", "-c", "release", "--disable-sandbox"
    bin.install ".build/release/Hisohiso" => "hisohiso"
  end

  def caveats
    <<~EOS
      Hisohiso requires the following macOS permissions:
        • Accessibility (for Globe key capture and text insertion)
        • Input Monitoring (for keyboard events)
        • Microphone (for audio recording)

      Grant permissions in System Settings → Privacy & Security.

      Set Globe key to "Do Nothing" in System Settings → Keyboard
      to prevent conflicts.

      Transcription models (~2.6 GB) are downloaded on first run.
    EOS
  end

  test do
    # GUI app — verify binary exists and is executable
    assert_predicate bin/"hisohiso", :executable?
  end
end
