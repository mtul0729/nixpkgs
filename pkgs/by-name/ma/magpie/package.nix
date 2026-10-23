# magpie is a Wails v3 app: Go with cgo, GTK 4 and WebKitGTK 6 on Linux.
# Upstream's install.sh ships an FHS-linked prebuilt binary, so this builds
# from source; `production` is the GUI and `nogui` the terminal build.
#
# Three things are Nix-specific, each explained where it happens:
#
#   tags            Upstream's Makefile adds gtk3 on Linux for older
#                   distributions. It is not used here: under a COSMIC
#                   Wayland session that path paints the top strip of the
#                   window and leaves the rest black, while GTK 4 /
#                   WebKitGTK 6, the Makefile's default, works.
#   nix-support.patch
#                   The program behaves like something a package manager
#                   installed: it does not update itself, its login entry
#                   names the wrapper and is repointed after an upgrade, one
#                   instance lock covers every version, and it writes no
#                   entry into $HOME.
#   no-double-tray-item-cosmic.patch
#                   COSMIC keeps the item it filed under the well-known name
#                   after that name is released, so registering again adds a
#                   second icon instead of taking its place.
{
  lib,
  stdenv,
  fetchFromGitHub,
  buildGoModule,
  pkg-config,
  wrapGAppsHook4,
  gtk4,
  webkitgtk_6_0,
  xdg-utils,
  glib-networking,
  bun,
  makeBinaryWrapper,
  copyDesktopItems,
  makeDesktopItem,
  nix-update-script,
  versionCheckHook,
  # False builds the terminal-only magpie-cli.
  withGui ? true,
}:

buildGoModule (finalAttrs: {
  pname = "magpie" + lib.optionalString (!withGui) "-cli";
  version = "0.1.1340";

  __structuredAttrs = true;

  src = fetchFromGitHub {
    owner = "yetone";
    repo = "magpie";
    tag = "v${finalAttrs.version}";
    hash = "sha256-rK39jWab1tMTqeaLPUe+JZOz4tSnAyy0GJQ+6kKbDHw=";
  };

  vendorHash = "sha256-pBk3sQZ9/1sVdz2ZteBGgQrI49fDfgsQ8ur7pzM477A=";

  subPackages = [ "." ];

  # See nix-support.patch for the Nix-specific behaviour.
  patches = [
    ./nix-support.patch
    ./no-double-tray-item-cosmic.patch
  ];

  env = {
    CGO_ENABLED = if withGui then "1" else "0";
  }
  // lib.optionalAttrs (withGui && stdenv.hostPlatform.isDarwin) {
    CGO_CFLAGS = "-mmacosx-version-min=${stdenv.hostPlatform.darwinMinVersion}";
    CGO_LDFLAGS = "-mmacosx-version-min=${stdenv.hostPlatform.darwinMinVersion}";
  };

  # `production` is the GUI, which on Linux is Wails v3's GTK 4 and
  # WebKitGTK 6 backend. The `gtk3` tag upstream keeps for older
  # distributions is not used: under a COSMIC Wayland session that path
  # renders the top strip of the window and leaves the rest black, and
  # neither WEBKIT_DISABLE_DMABUF_RENDERER nor WEBKIT_DISABLE_COMPOSITING_MODE
  # helps, while GTK 4 / WebKitGTK 6 works natively. `nogui` is the
  # terminal-only build.
  tags = if withGui then [ "production" ] else [ "nogui" ];

  # The autostart entry has to name the wrapper, which only exists at build
  # time, so it is passed in rather than read from os.Executable().
  ldflags = [
    "-s"
    "-w"
    "-X=main.version=${finalAttrs.version}"
    "-X=github.com/yetone/magpie/internal/autostart.nixSelf=${placeholder "out"}/bin/magpie"
    "-X=github.com/yetone/magpie/internal/update.NixBuild=1"
  ];

  nativeBuildInputs =
    lib.optionals (withGui && stdenv.hostPlatform.isLinux) [
      pkg-config
      wrapGAppsHook4
      copyDesktopItems
    ]
    # The Linux GUI is wrapped by wrapGAppsHook4; everything else needs a
    # wrapper of its own for MAGPIE_BUN (and xdg-open on Linux).
    ++ lib.optionals (!withGui || stdenv.hostPlatform.isDarwin) [ makeBinaryWrapper ];

  buildInputs = lib.optionals (withGui && stdenv.hostPlatform.isLinux) [
    gtk4
    webkitgtk_6_0
    # libsoup's HTTPS is the GIO TLS module. Without it the window loads
    # local pages, then fails every remote image and request.
    glib-networking
  ];

  # Tests need a real GUI and keychain; versionCheckHook runs the binary.
  doCheck = false;

  # The entry and icons magpie would otherwise write into $HOME on first start.
  desktopItems = lib.optionals (withGui && stdenv.hostPlatform.isLinux) [
    (makeDesktopItem {
      name = "magpie";
      desktopName = "magpie";
      genericName = "Model picker";
      comment = "Every agent's model. One place.";
      exec = "magpie %u";
      icon = "magpie";
      terminal = false;
      categories = [
        "Development"
        "Utility"
      ];
      mimeTypes = [ "x-scheme-handler/magpie" ];
      startupWMClass = "magpie";
    })
  ];

  postInstall =
    lib.optionalString (withGui && stdenv.hostPlatform.isLinux) ''
      install -Dm644 internal/gui/icon-256.png \
        "$out/share/icons/hicolor/256x256/apps/magpie.png"
      install -Dm644 internal/gui/icon-1024.png \
        "$out/share/icons/hicolor/1024x1024/apps/magpie.png"
      install -Dm644 build/icon/magpie.svg \
        "$out/share/icons/hicolor/scalable/apps/magpie.svg"
    ''
    # The URL scheme, autostart and bundle layout `make app` produces.
    + lib.optionalString (withGui && stdenv.hostPlatform.isDarwin) ''
      app="$out/Applications/magpie.app"
      mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
      mv "$out/bin/magpie" "$app/Contents/MacOS/magpie"
      ln -s "$app/Contents/MacOS/magpie" "$out/bin/magpie"
      cp build/darwin/magpie.icns build/darwin/Assets.car \
        "$app/Contents/Resources/"
      substitute build/darwin/Info.plist "$app/Contents/Info.plist" \
        --replace-fail '@VERSION@' '${finalAttrs.version}' \
        --replace-fail \
          '<key>LSMinimumSystemVersion</key><string>12.0</string>' \
          '<key>LSMinimumSystemVersion</key><string>${stdenv.hostPlatform.darwinMinVersion}</string>'
    ''
    + ''
      install -Dm644 LICENSE "$out/share/licenses/${finalAttrs.pname}/LICENSE"
    '';

  # wrapGAppsHook3 only collects gappsWrapperArgs; wrapping happens below.
  dontWrapGApps = withGui && stdenv.hostPlatform.isLinux;

  postFixup =
    lib.optionalString (withGui && stdenv.hostPlatform.isLinux) ''
      wrapProgram "$out/bin/magpie" "''${gappsWrapperArgs[@]}" \
        --prefix PATH : ${lib.makeBinPath [ xdg-utils ]} \
        --set MAGPIE_BUN ${lib.getExe bun}
      chmod +w "$out/share/applications/magpie.desktop"
      substituteInPlace "$out/share/applications/magpie.desktop" \
        --replace-fail 'Exec=magpie %u' "Exec=$out/bin/magpie %u"
    ''
    + lib.optionalString (withGui && stdenv.hostPlatform.isDarwin) ''
      wrapProgram "$out/Applications/magpie.app/Contents/MacOS/magpie" \
        --set MAGPIE_BUN ${lib.getExe bun}
      # A linker signature does not seal Info.plist or the resources.
      /usr/bin/codesign --force --sign - "$out/Applications/magpie.app"
    ''
    + lib.optionalString (!withGui) ''
      wrapProgram "$out/bin/magpie" \
        --set MAGPIE_BUN ${lib.getExe bun} \
        ${lib.optionalString stdenv.hostPlatform.isLinux "--prefix PATH : ${lib.makeBinPath [ xdg-utils ]}"}
    '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];

  passthru = {
    updateScript = nix-update-script { };
  };

  meta = {
    description = "Local gateway that picks the model for each AI coding agent";
    homepage = "https://usemagpie.ai/";
    changelog = "https://github.com/yetone/magpie/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    mainProgram = "magpie";
    mainDarwinApp = "magpie.app";
    maintainers = with lib.maintainers; [
      _27Aaron
      myul
    ];
    # bun is both a build input and the plugin runtime the wrapper points
    # at, and it exists on three platforms. Claiming the rest of
    # lib.platforms.linux makes `nix-env -iA nixpkgs.magpie` on them fail to
    # evaluate, because the bun attribute itself does not exist there.
    platforms = lib.intersectLists (with lib.platforms; darwin ++ linux) bun.meta.platforms;
  };
})
