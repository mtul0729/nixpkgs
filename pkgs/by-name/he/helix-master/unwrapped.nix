{
  lib,
  rustPlatform,
  fetchFromGitHub,
  runCommand,
  installShellFiles,
  git,
}:

rustPlatform.buildRustPackage (
  finalAttrs:
  let
    # Tracking helix master; update.sh bumps this via
    # `nix-update helix-master.unwrapped --version=branch=master`.
    rev = "4b7d101f3ccb0b274be5d5434fa540ed967a239c";

    defaultRuntimeDir = runCommand "helix-master-default-runtime" { } ''
      cp -r --no-preserve=mode ${finalAttrs.src}/runtime $out
      rm -rf $out/grammars $out/queries
    '';
  in
  {
    pname = "helix-master-unwrapped";
    # nixpkgs convention (pkgs/README.md): packages tracking an upstream
    # commit use <latest upstream release>-unstable-<commit date>, as a
    # literal maintained by nix-update (--version=branch=master).
    version = "25.07.1-unstable-2026-11-10";

    src = fetchFromGitHub {
      owner = "helix-editor";
      repo = "helix";
      inherit rev;
      hash = "sha256-sqLXoVk8jneQ6SOZA5uEvmBXlzJSaU6Z1HX0l8IEnxs=";
    };

    cargoHash = "sha256-kJP6LMcx5z91XzO4PNbNvSSWOjVvJW35O7Z4uW9J+m8=";

    doCheck = false;

    nativeBuildInputs = [
      installShellFiles
      git
    ];

    env = {
      # disable fetching and building of tree-sitter grammars in the helix-term build.rs
      HELIX_DISABLE_AUTO_GRAMMAR_BUILD = "1";
      HELIX_DEFAULT_RUNTIME = defaultRuntimeDir;
      # So `hx --version` shows the commit it was built from.
      HELIX_NIX_BUILD_REV = finalAttrs.src.rev;
    };

    postInstall = ''
      installShellCompletion contrib/completion/hx.{bash,fish,zsh}
      mkdir -p $out/share/{applications,icons/hicolor/256x256/apps}
      cp contrib/Helix.desktop $out/share/applications/Helix.desktop
      cp contrib/helix.png $out/share/icons/hicolor/256x256/apps/helix.png
    '';

    # NB: no versionCheckHook — hx --version prints the upstream version
    # ("helix 25.7.1 (rev)"), which can never contain our -unstable-<date>
    # suffix, so the check would always fail.

    meta = {
      description = "Post-modern modal text editor";
      homepage = "https://helix-editor.com";
      changelog = "https://github.com/helix-editor/helix/blob/${finalAttrs.src.rev}/CHANGELOG.md";
      license = lib.licenses.mpl20;
      mainProgram = "hx";
      maintainers = with lib.maintainers; [
        aciceri
        yusdacra
      ];
      platforms = lib.platforms.unix;
    };
  }
)
