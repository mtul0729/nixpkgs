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
  version = "0.3.0";

  src = fetchFromGitHub {
    owner = "mtul0729";
    repo = "cosmic-desktop-mcp";
    tag = "v${finalAttrs.version}";
    hash = "sha256-w5zQbDbQ3xByiwj3aNylBRTDMk0QoC4BABkyUEaNuvU=";
  };

  cargoHash = "sha256-vXiS5pwY52/HChO+M/5f9RKq+TEdPb539Sr+GGoRy9g=";

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
