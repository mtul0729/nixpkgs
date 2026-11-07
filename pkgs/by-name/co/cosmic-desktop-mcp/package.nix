{
  lib,
  rustPlatform,
  fetchFromGitHub,
  makeWrapper,
  nix-update-script,
  wl-clipboard,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "cosmic-desktop-mcp";
  version = "0.5.0";

  src = fetchFromGitHub {
    owner = "mtul0729";
    repo = "cosmic-desktop-mcp";
    rev = "v${finalAttrs.version}";
    hash = "sha256-KM2hZtekIXewQbwdfivXfGv0yiBPlI95pqEnFGEqGF8=";
  };

  cargoHash = "sha256-IU1cuG1MWyK83II2n7JwGl5YiD96siuXW+eG7UDh5i4=";

  # The test suite needs a running COSMIC session.
  doCheck = false;

  nativeBuildInputs = [ makeWrapper ];

  postFixup = ''
    wrapProgram $out/bin/cosmic-desktop-mcp \
      --prefix PATH : ${lib.makeBinPath [ wl-clipboard ]}
  '';

  passthru.updateScript = nix-update-script { };

  meta = {
    description = "MCP server for driving a COSMIC/Wayland desktop";
    homepage = "https://github.com/mtul0729/cosmic-desktop-mcp";
    license = lib.licenses.mit;
    mainProgram = "cosmic-desktop-mcp";
    platforms = lib.platforms.linux;
    maintainers = with lib.maintainers; [ myul ];
  };
})
