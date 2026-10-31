{
  lib,
  stdenv,
  bubblewrap,
  cairo,
  coreutils,
  desktop-file-utils,
  fetchFromGitHub,
  ffmpeg,
  ffmpegthumbnailer,
  fontconfig,
  gdk-pixbuf,
  glib,
  gnome,
  graphene,
  gst_all_1,
  gtk4,
  gtksourceview5,
  gvfs,
  imagemagick,
  librsvg,
  nix-update-script,
  pango,
  pkg-config,
  poppler,
  rustPlatform,
  squashfs-tools,
  util-linux,
  wrapGAppsHook4,
  xdg-utils,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "strata";
  version = "1.1.1";

  src = fetchFromGitHub {
    owner = "lgse";
    repo = "strata";
    rev = "v${finalAttrs.version}";
    hash = "sha256-mWFYDKlVR6/LytRBGmgZlWX70N+Qlt3Ev5W5TmJ8UdE=";
  };

  cargoHash = "sha256-+8Ztfdf/523VTH4nozy9b5Fde+GTk0xWRMbBUBA5rKs=";

  patches = [
    # Make Nix-owned installs defer updates to Nix instead of querying the AUR.
    ./nix-update.patch
  ];

  # The default `rar` feature requires the non-free UnRAR source.
  buildNoDefaultFeatures = true;
  __structuredAttrs = true;
  strictDeps = true;

  # The upstream suite assumes a full desktop session and host filesystem
  # features such as xattrs, setgid directories and GIO Trash.
  doCheck = false;

  nativeBuildInputs = [
    pkg-config
    wrapGAppsHook4
  ];

  buildInputs = [
    cairo
    fontconfig
    gdk-pixbuf
    glib
    graphene
    gst_all_1.gstreamer
    gst_all_1.gst-plugins-base
    gtk4
    gtksourceview5
    gvfs
    librsvg
    pango
    poppler
  ];

  env = {
    STRATA_BUILD_COMMIT = finalAttrs.src.rev;
    STRATA_TRUSTED_COMMAND_PATH = lib.makeBinPath [
      bubblewrap
      coreutils
      desktop-file-utils
      util-linux
      xdg-utils
      ffmpeg
      ffmpegthumbnailer
      imagemagick
      squashfs-tools
    ];
    STRATA_SANDBOX_PATH = lib.makeBinPath [
      coreutils
      util-linux
      ffmpeg
      ffmpegthumbnailer
      imagemagick
      squashfs-tools
    ];
    STRATA_SANDBOX_ROOT = "/nix/store";
    STRATA_SANDBOX_PRLIMIT = "${util-linux}/bin/prlimit";
    STRATA_SANDBOX_GDK_PIXBUF_MODULE_FILE = gnome._gdkPixbufCacheBuilder_DO_NOT_USE {
      extraLoaders = [ librsvg ];
    };
  };

  # Make the wrapped GTK application expose the GStreamer plugins in its closure.
  preFixup = ''
    gappsWrapperArgs+=(
      --prefix GST_PLUGIN_SYSTEM_PATH_1_0 : "$GST_PLUGIN_SYSTEM_PATH_1_0"
    )
  '';

  postInstall = ''
    install -Dm644 data/io.github.lgse.Strata.desktop \
      $out/share/applications/io.github.lgse.Strata.desktop
    install -Dm644 data/icons/scalable/apps/io.github.lgse.Strata.svg \
      $out/share/icons/hicolor/scalable/apps/io.github.lgse.Strata.svg

    # Keep the per-user FileManager1 service as an opt-in template rather than
    # claiming the session-bus name merely by installing Strata.
    install -Dm644 data/io.github.lgse.Strata.FileManager1.service \
      $out/share/strata/io.github.lgse.Strata.FileManager1.service
    substituteInPlace $out/share/strata/io.github.lgse.Strata.FileManager1.service \
      --replace-fail /usr/bin/strata $out/bin/strata

    install -Dm644 /dev/stdin $out/share/strata/install-source.toml <<'EOF'
    manager = "Nix"
    package = "strata"
    channel = "stable"
    EOF
  '';

  passthru.updateScript = nix-update-script { };

  meta = {
    description = "Fast, keyboard-first file manager for Linux";
    homepage = "https://github.com/lgse/strata";
    changelog = "https://github.com/lgse/strata/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ myul ];
    mainProgram = "strata";
    platforms = lib.platforms.linux;
  };
})
