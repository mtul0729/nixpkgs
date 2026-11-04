{
  lib,
  rustPlatform,
  fetchFromGitHub,
  nix-update-script,
}:

rustPlatform.buildRustPackage {
  pname = "helix-fcitx-focus";
  version = "0-unstable-2026-11-04";

  src = fetchFromGitHub {
    owner = "mtul0729";
    repo = "helix-fcitx-focus";
    rev = "d27d781a2fb7595b81beff6153a9144f13025b8a";
    hash = "sha256-BHu3F3exOK/+2VJFmtsSBuaC4ZzYv+CgFQCsnlvj/WA=";
  };

  cargoLock = {
    lockFile = ./Cargo.lock;
    outputHashes = {
      # Must match the steel-core rev in steelix's Cargo.lock: Steel loads this
      # dylib through abi_stable and refuses a mismatched build at runtime.
      "steel-core-0.8.3" = "sha256-o8/8x5B+ZXOBlf3+s74hvN/pDXl0ed2xKyYh9hs5aRI=";
    };
  };

  installPhase = ''
    runHook preInstall

    install -Dm755 "$(find target -name libhelix_fcitx_focus.so -type f | head -n 1)" \
      "$out/lib/libhelix_fcitx_focus.so"
    install -Dm644 cog.scm "$out/share/steel/cogs/helix-fcitx-focus/cog.scm"
    cp -r cogs "$out/share/steel/cogs/helix-fcitx-focus/"

    runHook postInstall
  '';

  passthru.updateScript = nix-update-script { extraArgs = [ "--version=branch=main" ]; };

  meta = {
    description = "Steel plugin that keeps fcitx5 in English outside Helix insert mode";
    homepage = "https://github.com/mtul0729/helix-fcitx-focus";
    license = with lib.licenses; [
      mit
      asl20
    ];
    maintainers = [ lib.maintainers.myul ];
    platforms = lib.platforms.linux;
  };
}
