{
  lib,
  stdenv,
  rustPlatform,
  fetchFromGitHub,
  fontconfig,
  installShellFiles,
  libGL,
  libx11,
  libxcursor,
  libxi,
  libxkbcommon,
  pkg-config,
  curl,
  libssh2,
  openssl,
  sqlite,
  aws-lc,
  wayland,
  writableTmpDirAsHomeHook,
  versionCheckHook,
  nix-update-script,
  withTerminal ? !stdenv.hostPlatform.isStatic,
  withWebServer ? true,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "zellij-unwrapped";
  version = "0.46.1";
  __structuredAttrs = true;

  src = fetchFromGitHub {
    owner = "zellij-org";
    repo = "zellij";
    tag = "v${finalAttrs.version}";
    hash = "sha256-sLH3ox4DY6JkrQAaI8IxnA7or1458gF4nEKBuPuQPI8=";
  };

  cargoHash = "sha256-qkXg4Vt+x3r1zka5htPtlO28B6bh+oiKGsinCdBASFA=";

  # Omit vendored_curl to link against libcurl from nixpkgs.
  buildNoDefaultFeatures = true;
  buildFeatures = [
    "plugins_from_target"
  ]
  ++ lib.optional withTerminal "terminal"
  ++ lib.optional withWebServer "web_server_capability";

  # The scene renderer treated a cursor cell as one column, so a block cursor on a
  # wide glyph (CJK, emoji, joined groups) covered only half of it. Applied here
  # rather than through `patches`: nix-update probes `patches` by unpacking the new
  # source before it updates `cargoHash`, which fails for rustPlatform packages, and
  # the probe's default patch fuzz can also mistake a patch for one that was merged
  # upstream and silently drop it. Drop this patch once a release contains the fix.
  postPatch = ''
    patch -p1 < ${./wide-cursor.patch}
  '';

  env.LIBSSH2_SYS_USE_PKG_CONFIG = 1;
  env.OPENSSL_NO_VENDOR = 1;

  nativeBuildInputs = [
    installShellFiles
    pkg-config
    (lib.getDev curl)
  ];

  # aws-lc-sys is forced onto the system library by the nixpkgs crate
  # override (AWS_LC_SYS_USE_SYSTEM=1) and does not find it unless it is here.
  buildInputs = [
    aws-lc
    curl
    libssh2
    openssl
    sqlite
  ];

  nativeCheckInputs = [
    writableTmpDirAsHomeHook
  ];

  nativeInstallCheckInputs = [
    versionCheckHook
  ];
  doInstallCheck = true;

  # Ensure that we don't vendor curl, but instead link against the libcurl from nixpkgs
  installCheckPhase = lib.optionalString (stdenv.hostPlatform.libc == "glibc") ''
    runHook preInstallCheck

    ldd "$out/bin/zellij" | grep libcurl.so

    runHook postInstallCheck
  '';

  postInstall =
    lib.optionalString (withTerminal && stdenv.hostPlatform.isLinux) ''
      install -Dm644 assets/dev.zellij.Zellij.desktop -t $out/share/applications
      install -Dm644 assets/dev.zellij.Zellij.metainfo.xml -t $out/share/metainfo

      for size in 128 256 512 1024; do
        install -Dm644 zellij-utils/assets/icons/logo$size.png \
          $out/share/icons/hicolor/''${size}x''${size}/apps/dev.zellij.Zellij.png
      done
    ''
    + lib.optionalString (stdenv.buildPlatform.canExecute stdenv.hostPlatform) ''
      installShellCompletion --cmd zellij \
        --bash <($out/bin/zellij setup --generate-completion bash) \
        --fish <($out/bin/zellij setup --generate-completion fish) \
        --zsh <($out/bin/zellij setup --generate-completion zsh)
    '';

  postFixup = lib.optionalString (withTerminal && stdenv.hostPlatform.isLinux) ''
    # winit/glutin and system font discovery load these libraries with dlopen.
    patchelf --add-rpath ${
      lib.makeLibraryPath [
        fontconfig
        libGL
        libx11
        libxcursor
        libxi
        libxkbcommon
        wayland
      ]
    } $out/bin/zellij
  '';

  passthru.updateScript = nix-update-script { };

  meta = {
    description = "Terminal workspace with batteries included";
    homepage = "https://zellij.dev/";
    changelog = "https://github.com/zellij-org/zellij/blob/v${finalAttrs.version}/CHANGELOG.md";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [
      therealansh
      _0x4A6F
      abbe
      matthiasbeyer
      ryan4yin
    ];
    mainProgram = "zellij";
  };
})
