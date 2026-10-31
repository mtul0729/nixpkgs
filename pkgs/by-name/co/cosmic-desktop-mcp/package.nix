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
  version = "0.4.0";

  src = fetchFromGitHub {
    owner = "mtul0729";
    repo = "cosmic-desktop-mcp";
    rev = "v${finalAttrs.version}";
    hash = "sha256-ZTFshNWf3Dagy/AJQi6dkjFy4j2UYFE4V3QGKQue9I8=";
  };

  cargoHash = "sha256-X9vqhu/zo1FNaIUFYJjk68vfjMa6g4GBwmpVO2vN7yA=";

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
