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
  version = "0.2.2";

  src = fetchFromGitHub {
    owner = "mtul0729";
    repo = "cosmic-desktop-mcp";
    tag = "v${finalAttrs.version}";
    hash = "sha256-F0CZWHHYW8uwLb5V5fLZmoVjxqg4qxL3KKb2JaDZIV4=";
  };

  cargoHash = "sha256-4EqaMUh7PaFHV57bdvp1YmBHDDMZupCSBHMvPXLCfz0=";

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
