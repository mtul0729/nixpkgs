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
  # PR #107 head, which sits on main after v0.11.0 — the patch does not apply to the tag.
  version = "0.11.0-unstable-2026-10-15";

  __structuredAttrs = true;

  src = fetchFromGitHub {
    owner = "tobi";
    repo = "disktree";
    rev = "aae91c592b15a025f7c665195974eecce4ed241c";
    hash = "sha256-kReob+bD3iymVl+GFuO6yU/dUj++/UDY9We90Z7Vpm4=";
  };

  cargoHash = "sha256-k+iLvOS+6o5oC+JcG9BJ3UUAzZAQpcpNelKCXsDx0Fw=";

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
  cargoTestFlags = [ "--package=disktree-core" ];

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
    maintainers = with lib.maintainers; [ domenkozar ];
    mainProgram = "disktree";
    platforms = lib.platforms.linux;
  };
})
