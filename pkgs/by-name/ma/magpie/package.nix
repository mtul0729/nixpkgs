# Every AI coding agent's model settings, in one dropdown (menubar / TUI / local
# gateway).
#
# Built from source: the upstream install.sh fetches an FHS-linked prebuilt
# binary that looks for /lib64/ld-linux-x86-64.so.2 and expects a distro
# WebKitGTK, neither of which exists on NixOS.
#
# The desktop window is Wails v3 + cgo on Linux, whose default backend is
# GTK 4 / WebKitGTK 6. The gtk3 tag in the Makefile is a compatibility switch
# for older distros and is deliberately not used here: under a COSMIC Wayland
# session that path renders nothing but the top strip of UI with the rest black,
# and neither WEBKIT_DISABLE_DMABUF_RENDERER=1 nor WEBKIT_DISABLE_COMPOSITING_MODE=1
# helps, while GTK 4 / WebKitGTK 6 works natively on Wayland.
#
# Upstream ships a bare binary on Linux with no .desktop file (only the macOS
# Info.plist and the Windows winres); the entry is written by the installer or
# on first run. This package supplies the system-wide copy plus the icon from
# build/windows, and patches out the two side effects of that first run:
#
#   no-self-desktop-file.patch
#     Stops magpie from writing ~/.local/share/applications/magpie.desktop.
#     That copy pins Exec to os.Executable(), a per-version /nix/store path,
#     and the XDG user directory outranks the system one, so after an upgrade
#     the launcher would keep starting whichever version wrote it first -- and
#     that version writes itself back. Self-locking.
#
#   no-double-tray-item-cosmic.patch
#     COSMIC's StatusNotifier watcher files an item under the sender's own name
#     and keeps it when the well-known name is released, so upstream's
#     re-registration adds a second icon instead of replacing the first.
#
# The same first-run path also runs `xdg-mime default` to claim magpie://.
# Declaring the type is reasonable and kept in MimeType below; deciding the
# user's default handler for them is not.
{
  lib,
  buildGoModule,
  bun,
  fetchFromGitHub,
  gtk4,
  makeDesktopItem,
  makeWrapper,
  nix-update-script,
  pkg-config,
  webkitgtk_6_0,
}:

let
  desktopItem = makeDesktopItem {
    name = "magpie";
    desktopName = "magpie";
    comment = "Every agent's model, one place";
    exec = "magpie %U";
    icon = "magpie";
    categories = [
      "Development"
      "Utility"
    ];
    startupWMClass = "magpie";
    terminal = false;
    mimeTypes = [ "x-scheme-handler/magpie" ];
  };
in
buildGoModule (finalAttrs: {
  pname = "magpie";
  version = "0.1.1322";

  src = fetchFromGitHub {
    owner = "yetone";
    repo = "magpie";
    rev = "v0.1.1322";
    hash = "sha256-CJO1YNyeFL1Ijmbol/WUluZ3Pamnr8u0QPGzraY2u2s=";
  };

  vendorHash = "sha256-pBk3sQZ9/1sVdz2ZteBGgQrI49fDfgsQ8ur7pzM477A=";

  # `production` is a Makefile convention only -- there is no //go:build
  # production in the source. It is used to stay identical to what upstream
  # releases. No gtk3, see the header.
  tags = [ "production" ];

  patches = [
    ./no-self-desktop-file.patch
    ./no-double-tray-item-cosmic.patch
  ];

  ldflags = [
    "-s"
    "-w"
    "-X main.version=v${finalAttrs.version}"
  ];

  nativeBuildInputs = [
    makeWrapper
    pkg-config
  ];

  buildInputs = [
    gtk4
    webkitgtk_6_0
  ];

  postInstall = ''
    install -Dm644 build/windows/icon-256.png $out/share/icons/hicolor/256x256/apps/magpie.png
    install -Dm644 ${desktopItem}/share/applications/magpie.desktop \
      $out/share/applications/magpie.desktop
  '';

  # 插件用 Bun 安装和运行。上游默认在运行时自己下载并自动更新
  # (internal/plugin/bun.go, bunupdate.go)；这里指向 nixpkgs 的 bun，插件安装
  # 因此离线可用，也不再跟着上游自动升级。--set-default: 显式设了 MAGPIE_BUN
  # 的用户不受影响。
  postFixup = ''
    wrapProgram $out/bin/magpie \
      --set-default MAGPIE_BUN ${lib.getExe bun}
  '';

  # Upstream CI already exercises this tag; the package layer need not repeat
  # the full suite.
  doCheck = false;

  # nixpkgs 的标准升级入口：`nix-update -u magpie`（或
  # `nix-shell maintainers/scripts/update.nix --argstr package magpie`）会用它。
  # --version-regex 是必要的：上游 release feed 里混着 pf-v1 这种非版本 tag，
  # 不带正则时 nix-update 会把它当成最新版。
  passthru.updateScript = nix-update-script {
    extraArgs = [
      "--version-regex"
      "v([0-9.]+)"
    ];
  };

  meta = {
    description = "Every agent's model, one place";
    homepage = "https://usemagpie.ai";
    license = lib.licenses.mit;
    mainProgram = "magpie";
    maintainers = [ lib.maintainers.myul ];
    platforms = lib.platforms.linux;
  };
})
