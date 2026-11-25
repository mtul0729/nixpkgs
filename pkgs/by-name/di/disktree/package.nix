{
  lib,
  rustPlatform,
  fetchFromGitHub,
  nix-update-script,
  pkg-config,
  desktop-file-utils,
  makeBinaryWrapper,
  fontconfig,
  freetype,
  libGL,
  libxcb,
  libxkbcommon,
  openssl,
  vulkan-loader,
  wayland,
  gitMinimal,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "disktree";
  version = "1.0.0";

  strictDeps = true;
  __structuredAttrs = true;

  src = fetchFromGitHub {
    owner = "tobi";
    repo = "disktree";
    rev = "v${finalAttrs.version}";
    hash = "sha256-NXX4XPGIrVFfKEO9uQMlCKyLqRSFh2JXcvjLhaQmgcw=";
  };

  cargoHash = "sha256-si9d+0sNZZwz91tmWBrnhL2Lkhy25G2o/kIvTobG09M=";

  nativeBuildInputs = [
    pkg-config
    desktop-file-utils
    makeBinaryWrapper
  ];

  buildInputs = [
    fontconfig
    freetype
    libGL
    libxcb
    libxkbcommon
    openssl
    vulkan-loader
    wayland
  ];

  cargoBuildFlags = [ "--package=disktree-app" ];

  doCheck = false;

  postInstall = ''
    install -Dm644 assets/disktree.svg \
      "$out/share/icons/hicolor/scalable/apps/disktree.svg"
    install -d "$out/share/applications"
    substitute packaging/disktree.desktop.in \
      "$out/share/applications/disktree.desktop" \
      --replace-fail '@BINDIR@' "$out/bin" \
      --replace-fail '@VERSION@' '${finalAttrs.version}'
    desktop-file-validate "$out/share/applications/disktree.desktop"
  '';

  postFixup = ''
    patchelf "$out/bin/disktree" --add-rpath ${
      lib.makeLibraryPath [
        libGL
        vulkan-loader
        wayland
      ]
    }
    wrapProgram "$out/bin/disktree" \
      --prefix PATH : ${lib.makeBinPath [ gitMinimal ]}
  '';

  passthru.updateScript = nix-update-script { };

  meta = {
    description = "Disk usage treemap for finding and removing files";
    homepage = "https://github.com/tobi/disktree";
    changelog = "https://github.com/tobi/disktree/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [
      domenkozar
      kleinbem
    ];
    mainProgram = "disktree";
    platforms = lib.platforms.linux;
  };
})
