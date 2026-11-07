# The NSH toolchain `nsh package` needs: the CLI plus the Linux GTK 4 runtime
# it copies into the bundle. Noop's release workflow pins it through NSH_REF in
# .github/workflows/release.yml; the app and the framework are not released in
# lockstep, so bump this pin (and both hashes) whenever upstream bumps theirs.
{
  lib,
  stdenv,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  makeWrapper,
  gtk4,
  pango,
  cairo,
  gdk-pixbuf,
  glib,
  graphene,
  harfbuzz,
  fontconfig,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "nsh";
  version = "0.4.0-unstable-2026-11-05";

  src = fetchFromGitHub {
    owner = "longbridge";
    repo = "nsh";
    rev = "e1af8c6c3c8e7c704266bcf6bb388a229f29b108";
    hash = "sha256-MHVLmxk/f7gy0+47gesMfBv5MYRMAAFnDFi3ba2mMyw=";
  };

  cargoHash = "sha256-JZphwopbAlaKURmIcVp5KOPY/kUzgrGgaYHOEAJhdUQ=";

  __structuredAttrs = true;
  strictDeps = true;

  # rquickjs enables its `bindgen` feature on native targets.
  nativeBuildInputs = [
    pkg-config
    makeWrapper
    rustPlatform.bindgenHook
  ];

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

  cargoBuildFlags = [
    "--locked"
    "-p"
    "nsh-cli"
  ];

  # The same runtime/features Noop's release workflow builds: JS apps only, no
  # web views, shaders, editor or math, so the runner needs GTK 4 alone.
  postBuild = ''
    cargo build --offline --release --locked \
      --target ${stdenv.hostPlatform.rust.rustcTargetSpec} \
      -p nsh-linux-app --no-default-features --features js
  '';

  installPhase = ''
    runHook preInstall

    # cargoBuildHook passes --target, so artifacts are under the triple.
    install -Dm755 target/${stdenv.hostPlatform.rust.rustcTargetSpec}/release/nsh \
      $out/lib/nsh/bin/nsh
    install -Dm755 target/${stdenv.hostPlatform.rust.rustcTargetSpec}/release/nsh-linux-app \
      $out/lib/nsh/runtime/linux/nsh-linux-app

    # The CLI finds the runtime at ../runtime next to its own path; the wrapper
    # only puts it on PATH.
    makeWrapper $out/lib/nsh/bin/nsh $out/bin/nsh \
      --set NSH_RUNTIME $out/lib/nsh/runtime

    runHook postInstall
  '';

  # The upstream suite needs the platform hosts and a display.
  doCheck = false;

  meta = {
    description = "Native UI framework's build tool and Linux runtime";
    homepage = "https://nsh.dev";
    license = lib.licenses.asl20;
    mainProgram = "nsh";
    platforms = lib.platforms.linux;
  };
})
