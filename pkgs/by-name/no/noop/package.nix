{
  lib,
  stdenv,
  fetchFromGitHub,
  nix-update-script,
  callPackage,
  autoPatchelfHook,
  makeBinaryWrapper,
  wrapGAppsHook4,
  cairo,
  fontconfig,
  gdk-pixbuf,
  glib,
  graphene,
  gtk4,
  harfbuzz,
  pango,
}:

let
  # Not a top-level attribute: nixpkgs already has an unrelated `nsh` (the
  # nuta/nsh shell), and this toolchain only exists to package Noop.
  nsh = callPackage ./nsh-toolchain.nix { };
in
stdenv.mkDerivation (finalAttrs: {
  pname = "noop";
  version = "0.1.10";

  src = fetchFromGitHub {
    owner = "huacnlee";
    repo = "noop";
    rev = "v${finalAttrs.version}";
    hash = "sha256-VjhkM7celLkweAeUrU/mWcRElOCH2xJAA95DdVqRppI=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    makeBinaryWrapper
    wrapGAppsHook4
  ];

  # The runtime `nsh package` bundles is built from source, but it comes out of
  # the nsh derivation without an RPATH, hence autoPatchelfHook above.
  buildInputs = [
    cairo
    fontconfig
    gdk-pixbuf
    glib
    graphene
    gtk4
    harfbuzz
    pango
  ];

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild

    # `nsh package` bundles the TSX sources with NSH's own bundler; no Node or
    # Rust toolchain is involved at this point.
    pushd app
    ${nsh}/bin/nsh package --target linux --out package \
      --app-version ${finalAttrs.version} --build 1
    popd

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib $out/bin $out/share/applications \
      $out/share/icons/hicolor/1024x1024/apps

    cp -r app/package/Noop $out/lib/noop

    makeBinaryWrapper $out/lib/noop/Noop $out/bin/noop

    install -m644 $out/lib/noop/dev.noop.app.png \
      $out/share/icons/hicolor/1024x1024/apps/dev.noop.app.png
    substituteInPlace $out/lib/noop/dev.noop.app.desktop \
      --replace-fail "Exec=Noop" "Exec=$out/bin/noop"
    install -m644 $out/lib/noop/dev.noop.app.desktop \
      $out/share/applications/dev.noop.app.desktop

    runHook postInstall
  '';

  passthru.updateScript = nix-update-script { };

  meta = {
    description = "Desktop client for running a team of AI coding agents on your own machines";
    homepage = "https://huacnlee.github.io/noop/";
    changelog = "https://github.com/huacnlee/noop/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    maintainers = [ lib.maintainers.myul ];
    mainProgram = "noop";
    platforms = lib.platforms.linux;
  };
})
