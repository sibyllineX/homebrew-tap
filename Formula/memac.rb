# Homebrew formula for memac — local-first memory for AI coding agents (Apple Silicon only).
#
# Install path is the SOURCE FORMULA, pinned to a tag+revision: `brew install --no-sandbox` builds
# from the git checkout (`--no-sandbox` because the in-build `git lfs pull` needs network to
# materialize the vendored model/dylib/engine — a tarball carries only LFS pointers). A pre-built,
# release-hosted binary bottle (fast, sandbox-clean pour) is a planned follow-up; the prior bottle
# was machine-local + stale and was removed here so `brew install` always reflects the tagged code.
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
  url "https://github.com/sibyllineX/memac.git", using: :git, tag: "v0.1.1",
      revision: "52af186f6fc6a2a6bbce57bd0e490e095f2f4de1"
  version "0.1.1"
  license any_of: ["MIT", "Apache-2.0"]

  depends_on "git-lfs" => :build
  depends_on "rust" => :build
  depends_on arch: :arm64
  depends_on :macos
  depends_on "node" # post_install reuses the tested TS installer to wire ~/.claude/settings.json

  def data_root
    Pathname.new(Dir.home)/"Library/Application Support/mem-mac"
  end

  def install
    # Materialize the LFS-vendored assets (the engine .a + model + dylib); a tarball has pointers.
    #
    # AUTH INSIDE THE ISOLATED BUILD STEP. Homebrew runs `install` in an isolated environment that
    # does NOT reliably see the user's global git/ssh config — no url rewrites, no `gh` credential
    # helper, possibly not even ~/.ssh/config. The source *clone* succeeds (it runs pre-sandbox in
    # the normal shell); but `git lfs pull` runs HERE, isolated, and can't reach the PRIVATE repo's
    # LFS objects over HTTPS. So arrange auth LOCALLY in this checkout: rewrite `origin` to SSH, and
    # point SSH at the key by ABSOLUTE path — the ssh-agent is empty on this machine, so we can't
    # lean on it, and the build step's HOME may be scrubbed, so we can't lean on ~/.ssh/config
    # either. `Dir.home` resolves the real user home in the formula even when the subprocess env is
    # scrubbed, giving a path that works regardless of isolation. `accept-new` handles a build HOME
    # with no known_hosts; `IdentitiesOnly` avoids "too many auth failures" from other offered keys.
    system "git", "remote", "set-url", "origin", "git@github.com:sibyllineX/memac.git"
    ssh_key = "#{Dir.home}/.ssh/id_ed25519"
    ENV["GIT_SSH_COMMAND"] =
      "ssh -i #{ssh_key} -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"
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
