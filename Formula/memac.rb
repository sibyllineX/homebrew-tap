# Homebrew formula for memac — local-first memory for AI coding agents (Apple Silicon only).
#
# PREBUILT BINARY BOTTLE. The `url` is a release-hosted tarball of already-built binaries + the
# vendored runtime assets (bge model, sqlite-vec dylib, the zsh capture hook). There is NO build
# step here: no git clone, no `git lfs pull`, no cargo/npm, no network beyond fetching the tarball
# (which Homebrew does pre-sandbox). This sidesteps Homebrew's build sandbox entirely — the reason
# an asset-heavy, private-LFS project could never `git lfs pull` inside `install`.
#
# Principle V (local-first, no egress): the model/dylib ride INSIDE the tarball, sha256-verified by
# Homebrew on download and again by the daemon at load. Nothing is fetched from a model hub, ever.
#
# INSTALL COMMAND: `HOMEBREW_NO_SANDBOX=1 brew install sibyllinex/tap/memac`.
# The `NO_SANDBOX` is required so `post_install` may write OUTSIDE the Homebrew prefix — it stages
# the runtime assets into `~/Library/Application Support/mem-mac` and wires the Claude Code hook +
# MCP into `~/.claude/settings.json` and the shell-capture block into `~/.zshrc`. Homebrew sandboxes
# post_install by default, which silently blocks those home-dir writes.
#
# Naming: the package/command is `memac`; the binaries are still `memmac*` — `bin.install_symlink`
# aliases `memac` -> `memmac`. The Claude Code hook + MCP keys stay `memmac`.
class Memac < Formula
  desc "Local-first memory layer for AI coding agents"
  homepage "https://github.com/sibyllineX/memac"
  url "https://github.com/sibyllineX/memac/releases/download/v0.1.1/memac-0.1.1.arm64.tar.gz"
  sha256 "5b01913e95b277a5cc290fe5fb209bda0f75aa2dfc2fd540ef326ce204317fa0"
  version "0.1.1"
  license any_of: ["MIT", "Apache-2.0"]

  depends_on arch: :arm64
  depends_on :macos
  depends_on "node" # post_install wires ~/.claude/settings.json via the tested TS installer

  def data_root
    Pathname.new(Dir.home)/"Library/Application Support/mem-mac"
  end

  def install
    # Prebuilt binaries — just place them. `memac` is the command; the crates stay `memmac*`.
    bin.install "bin/memmacd", "bin/memmac", "bin/memmac-mcp", "bin/memmac-hook"
    bin.install_symlink "memmac" => "memac"
    # The compiled TS installer + the runtime assets (model, dylib, zsh capture hook), stashed for
    # post_install. `memmac-hook.zsh` MUST ship here: the zshrc block `source`s it by this path.
    libexec.install "dist"
    (libexec/"assets").install "assets/models", "assets/sqlite-vec", "assets/memmac-hook.zsh"
  end

  def post_install
    # Runs with the REAL user HOME (not a build home), so this stages to the actual data dir and
    # wires the actual ~/.claude/settings.json + ~/.zshrc. Requires HOMEBREW_NO_SANDBOX=1 (writes
    # outside the Homebrew prefix).
    assets = data_root/"assets"
    assets.mkpath
    (data_root/"data").mkpath
    (data_root/"logs").mkpath
    cp_r libexec/"assets/models", assets, remove_destination: true
    cp_r libexec/"assets/sqlite-vec", assets, remove_destination: true

    # Idempotent: preserves your other hooks/servers, and wires the shell-capture block into
    # ~/.zshrc pointing at libexec/assets/memmac-hook.zsh (the tested TS merge).
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
      memac (Apple Silicon, prebuilt bottle) is installed.

      If you did NOT install with `HOMEBREW_NO_SANDBOX=1`, the hook wiring was likely blocked by
      Homebrew's post_install sandbox. Wire it manually (idempotent):
        node #{opt_libexec}/dist/cli.js install-hooks --bin-dir #{opt_bin}

      Start the memory daemon (a per-user LaunchAgent):
        brew services start memac

      Then open a NEW Claude Code session in your repo. Verify any time with:
        memac doctor

      Homebrew cannot run scripts on `brew uninstall`, so remove the Claude Code hook + MCP entry
      first (and stop the daemon with `brew services stop memac`):
        node #{opt_libexec}/dist/cli.js uninstall-hooks
    EOS
  end

  test do
    assert_path_exists bin/"memmacd"
    assert_match "ladder", shell_output("#{bin}/memac doctor 2>&1 || true")
  end
end
