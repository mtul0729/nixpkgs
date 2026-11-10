# aw-server-rust, aw-client-rust and aw-webui follow serverVersion below. The
# Python components stay pinned to the 0.13.2 bundle: 0.14.1 rewrote aw-notify
# from Python to Rust (aw-notify-rs), so ${sources}/aw-notify no longer contains
# a Python package. Move them over once the Rust notifier is packaged.
{
  lib,
  fetchFromGitHub,
  rustPlatform,
  makeWrapper,
  pkg-config,
  perl,
  openssl,
  rust-jemalloc-sys,
  sqlite,
  python3,
  python3Packages,
  qt6,
  xdg-utils,
  replaceVars,
  nodejs_22,
  buildNpmPackage,
  stdenv,
  removeReferencesTo,
}:

let
  version = "0.13.2";
  sources = fetchFromGitHub {
    owner = "ActivityWatch";
    repo = "activitywatch";
    rev = "v${version}";
    sha256 = "sha256-Z3WAg3b1zN0nS00u0zIose55JXRzQ7X7qy39XMY7Snk=";
    fetchSubmodules = true;
  };

  serverVersion = "0.14.2";
  serverSources = fetchFromGitHub {
    owner = "ActivityWatch";
    repo = "activitywatch";
    rev = "v${serverVersion}";
    sha256 = "sha256-lAE9pTC9tGB0mIuYOPcsWyv66aOov/5uA8QblvmlrOw=";
    fetchSubmodules = true;
  };
in
rec {
  aw-watcher-afk = python3Packages.buildPythonApplication {
    pname = "aw-watcher-afk";
    inherit version;

    src = "${sources}/aw-watcher-afk";

    pyproject = true;
    build-system = [ python3Packages.poetry-core ];

    dependencies = with python3Packages; [
      aw-client
      python-xlib
      pynput
    ];

    pythonRelaxDeps = [
      "python-xlib"
    ];

    pythonImportsCheck = [ "aw_watcher_afk" ];

    meta = {
      description = "Watches keyboard and mouse activity to determine if you are AFK or not (for use with ActivityWatch)";
      homepage = "https://github.com/ActivityWatch/aw-watcher-afk";
      maintainers = with lib.maintainers; [ huantian ];
      mainProgram = "aw-watcher-afk";
      license = lib.licenses.mpl20;
    };
  };

  aw-watcher-window = python3Packages.buildPythonApplication {
    pname = "aw-watcher-window";
    inherit version;

    src = "${sources}/aw-watcher-window";

    pyproject = true;
    build-system = [ python3Packages.poetry-core ];

    dependencies = with python3Packages; [
      aw-client
      python-xlib
    ];

    pythonRelaxDeps = [
      "python-xlib"
    ];

    pythonImportsCheck = [ "aw_watcher_window" ];

    meta = {
      description = "Cross-platform window watcher (for use with ActivityWatch)";
      homepage = "https://github.com/ActivityWatch/aw-watcher-window";
      maintainers = with lib.maintainers; [ huantian ];
      mainProgram = "aw-watcher-window";
      license = lib.licenses.mpl20;
      badPlatforms = lib.platforms.darwin; # requires pyobjc-framework
    };
  };

  aw-qt = python3Packages.buildPythonApplication {
    pname = "aw-qt";
    inherit version;

    src = "${sources}/aw-qt";

    pyproject = true;
    build-system = [
      python3Packages.poetry-core
      python3Packages.setuptools
    ];

    dependencies = with python3Packages; [
      aw-core
      qt6.qtbase
      qt6.qtsvg # Rendering icons in the trayicon menu
      pyqt6
      click
    ];

    nativeBuildInputs = [
      qt6.wrapQtAppsHook
    ];

    # Prevent double wrapping
    dontWrapQtApps = true;

    makeWrapperArgs = [
      "--suffix"
      "PATH"
      ":"
      (lib.makeBinPath [ xdg-utils ])
    ];

    postInstall = ''
      install -D resources/aw-qt.desktop $out/share/applications/aw-qt.desktop

      # For the actual tray icon, see
      # https://github.com/ActivityWatch/aw-qt/blob/8ec5db941ede0923bfe26631acf241a4a5353108/aw_qt/trayicon.py#L211-L218
      install -D media/logo/logo.png $out/${python3.sitePackages}/media/logo/logo.png

      # For .desktop file and your desktop environment
      install -D media/logo/logo.svg $out/share/icons/hicolor/scalable/apps/activitywatch.svg
      install -D media/logo/logo.png $out/share/icons/hicolor/512x512/apps/activitywatch.png
      install -D media/logo/logo-128.png $out/share/icons/hicolor/128x128/apps/activitywatch.png
    '';

    preFixup = ''
      makeWrapperArgs+=(
        "''${qtWrapperArgs[@]}"
      )
    '';

    pythonImportsCheck = [ "aw_qt" ];

    meta = {
      description = "Tray icon that manages ActivityWatch processes, built with Qt";
      homepage = "https://github.com/ActivityWatch/aw-qt";
      maintainers = with lib.maintainers; [ huantian ];
      mainProgram = "aw-qt";
      license = lib.licenses.mpl20;
      badPlatforms = lib.platforms.darwin; # requires pyobjc-framework
    };
  };

  aw-notify = python3Packages.buildPythonApplication {
    pname = "aw-notify";
    inherit version;

    src = "${sources}/aw-notify";

    pyproject = true;
    build-system = [ python3Packages.poetry-core ];

    patches = [
      # Backport desktop-notifier 6 / rubicon-objc 0.5 support.
      # https://github.com/ActivityWatch/aw-notify/pull/10
      ./aw-notify-desktop-notifier-6.patch
    ];

    dependencies = with python3Packages; [
      aw-client
      desktop-notifier
    ];

    pythonRelaxDeps = [
      "desktop-notifier"
    ];

    pythonImportsCheck = [ "aw_notify" ];

    meta = {
      description = "Desktop notification service for ActivityWatch";
      homepage = "https://github.com/ActivityWatch/aw-notify";
      maintainers = with lib.maintainers; [ huantian ];
      mainProgram = "aw-notify";
      license = lib.licenses.mpl20;
    };
  };

  aw-client-rust = rustPlatform.buildRustPackage {
    pname = "aw-client-rust";
    version = serverVersion;

    src = "${serverSources}/aw-server-rust";

    buildAndTestSubdir = "aw-client-rust";
    buildFeatures = [ "cli" ];
    checkFeatures = [ "cli" ];

    cargoHash = "sha256-8qbH7jlduLQhfrGMbpvZYs/BMojzaGOIa3+Prv0tlO0=";

    # See aw-server-rust: cargo-auditable panics on the workspace's
    # `cli = [ "dep:clap" ]` features.
    auditable = false;

    doCheck = false;

    passthru.updateScript = ./update.sh;

    meta = {
      description = "Command-line client for ActivityWatch, written in Rust";
      homepage = "https://github.com/ActivityWatch/aw-server-rust";
      maintainers = with lib.maintainers; [ huantian ];
      mainProgram = "aw-client";
      platforms = lib.platforms.linux;
      license = lib.licenses.mpl20;
    };
  };

  aw-server-rust = rustPlatform.buildRustPackage {
    pname = "aw-server-rust";
    version = serverVersion;

    src = "${serverSources}/aw-server-rust";

    cargoHash = "sha256-8qbH7jlduLQhfrGMbpvZYs/BMojzaGOIa3+Prv0tlO0=";

    # cargo-auditable 0.7.6 panics on this workspace's `cli = [ "dep:clap" ]`
    # features ("does not have feature clap" during cargo metadata).
    auditable = false;

    patches = [
      # aw-server's Cargo.toml still says 0.14.0 at the 0.14.1 tag; report the
      # release version from the API instead.
      (replaceVars ./override-version.patch {
        version = "v${serverVersion}";
      })
    ];

    nativeBuildInputs = [
      makeWrapper
      pkg-config
      perl
    ];

    buildInputs = [
      openssl
      rust-jemalloc-sys
      sqlite
    ];

    # build.rs hands this path to rust-embed, which compiles the frontend into
    # the binary; there is no runtime asset directory.
    env.AW_WEBUI_DIR = "${aw-webui}";

    doCheck = false;

    # One of the crates bakes the compiler it was built with into aw-sync.
    # Nothing reads it at runtime, but the reference drags gcc (~280 MiB) into
    # the closure of every machine that runs the server.
    postFixup = ''
      for f in $out/bin/*; do
        ${removeReferencesTo}/bin/remove-references-to -t ${stdenv.cc} "$f"
      done
    '';

    passthru.updateScript = ./update.sh;

    meta = {
      description = "High-performance implementation of the ActivityWatch server, written in Rust";
      homepage = "https://github.com/ActivityWatch/aw-server-rust";
      maintainers = with lib.maintainers; [ huantian ];
      mainProgram = "aw-server";
      platforms = lib.platforms.linux;
      license = lib.licenses.mpl20;
    };
  };

  aw-webui = buildNpmPackage {
    pname = "aw-webui";
    version = serverVersion;

    src = "${serverSources}/aw-server-rust/aw-webui";

    nodejs = nodejs_22;
    npmDepsHash = "sha256-XJuIBFNdm8he7OF3X6Szxo74/usfIcwtrLPPY3HYnlU=";

    makeCacheWritable = true;
    npmFlags = [ "--legacy-peer-deps" ];

    patches = [
      # Hardcode version to avoid the need to have the Git repo available at build time.
      (replaceVars ./commit-hash.patch {
        commit_hash = serverSources.rev;
      })
    ];

    installPhase = ''
      runHook preInstall
      mv dist $out
      mv media/logo/logo.{png,svg} $out
      runHook postInstall
    '';

    doCheck = true;
    checkPhase = ''
      runHook preCheck
      npm test
      runHook postCheck
    '';

    meta = {
      description = "Web-based UI for ActivityWatch, built with Vue.js";
      homepage = "https://github.com/ActivityWatch/aw-webui/";
      maintainers = with lib.maintainers; [ huantian ];
      license = lib.licenses.mpl20;
    };
  };
}
