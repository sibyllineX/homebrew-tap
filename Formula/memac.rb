# Homebrew formula for memac — local-first memory for AI coding agents (Apple Silicon only).
#
# Primary install path is the BINARY BOTTLE (assets baked in, no in-build network, no
# `--no-sandbox`). The git `url` below is the source-build fallback only; on this private repo it
# needs auth, but a normal `brew install` pours the bottle and never fetches it.
#
# Principle V (local-first, no egress): NOTHING is fetched from a model hub at build OR run time.
# ONNX Runtime is linked statically; the daemon loads the bge model + sqlite-vec only from the
# sha256-verified, locally-staged assets.
#
# Naming: the package/command is `memac`; the binaries are still `memmac*` — `bin.install_symlink`
# aliases `memac` -> `memmac`. The Claude Code hook + MCP keys stay `memmac`.
class Memac < Formula
  desc "Local-first memory layer for AI coding agents"
  homepage "https://github.com/sibyllineX/memac"
  url "https://github.com/sibyllineX/memac.git", using: :git, tag: "v0.1.0",
      revision: "53a283bf363a306f426ac62cee1798f6221aad0a"
  version "0.1.0"
  license any_of: ["MIT", "Apache-2.0"]

  bottle do
    root_url "file:///Users/tanujsharma/.memac-bottles"
    sha256 cellar: :any, arm64_tahoe: "247bec25fa86f26bf5cf8340aba730d55e8b3dd294c5bef208ad78e4b3656f7f"
  end

  depends_on "git-lfs" => :build
  depends_on "rust" => :build
  depends_on arch: :arm64
  depends_on :macos
  depends_on "node" # post_install reuses the tested TS installer to wire ~/.claude/settings.json

  def data_root
    Pathname.new(Dir.home)/"Library/Application Support/mem-mac"
  end

  def install
    # Materialize the LFS-vendored assets (source-build fallback only; the bottle bakes them in).
    system "git", "lfs", "install", "--local"
    system "git", "lfs", "pull"

    system "cargo", "build", "--release", "--locked"
    bin.install "target/release/memmacd", "target/release/memmac",
                "target/release/memmac-mcp", "target/release/memmac-hook"
    bin.install_symlink "memmac" => "memac"

    cd "installer" do
      system "npm", "install"
      system "npm", "run", "build"
    end
    libexec.install "installer/dist"
    (libexec/"assets").install "assets/models", "assets/sqlite-vec"
  end

  def post_install
    assets = data_root/"assets"
    assets.mkpath
    (data_root/"data").mkpath
    (data_root/"logs").mkpath
    cp_r libexec/"assets/models", assets, remove_destination: true
    cp_r libexec/"assets/sqlite-vec", assets, remove_destination: true

    system "node", libexec/"dist/cli.js", "install-hooks", "--bin-dir", opt_bin
  end

  service do
    run [opt_bin/"memmacd", "--data-dir", "#{Dir.home}/Library/Application Support/mem-mac/data"]
    keep_alive true
    run_at_load true
    working_dir Dir.home
    log_path "#{Dir.home}/Library/Application Support/mem-mac/logs/memmacd.out.log"
    error_log_path "#{Dir.home}/Library/Application Support/mem-mac/logs/memmacd.err.log"
  end

  def caveats
    <<~EOS
      memac (Apple Silicon) is installed.

      Start the memory daemon (a per-user LaunchAgent):
        brew services start memac

      Then open a NEW Claude Code session in your repo — the SessionStart hook injects your
      memories. Verify any time with:
        memac doctor

      Homebrew cannot run scripts on `brew uninstall`, so remove the Claude Code hook + MCP
      entry first (and stop the daemon with `brew services stop memac`):
        node #{opt_libexec}/dist/cli.js uninstall-hooks
    EOS
  end

  test do
    assert_path_exists bin/"memmacd"
    # Exit-code-agnostic: doctor is `ready` (exit 0) on a wired+running install, `not ready`
    # (exit 1) otherwise — both print the ladder. We assert the ladder renders, not the state.
    assert_match "ladder", shell_output("#{bin}/memac doctor 2>&1 || true")
  end
end
