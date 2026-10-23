# mtul0729/nixpkgs

A personal fork of [nixpkgs](https://github.com/NixOS/nixpkgs) that carries the packages I
maintain and that are not in nixpkgs yet. They are packaged in nixpkgs' `pkgs/by-name`
layout so they can be sent upstream as a PR — several already are.

Looking for nixpkgs itself? You want [NixOS/nixpkgs](https://github.com/NixOS/nixpkgs).

## Packages

| Attribute | What it is |
| --- | --- |
| `magpie` | Desktop client for "every agent's model, one place" |
| `dashbeam` | P2P file transfer with NAT hole punching, built on iroh |
| `helix` | Post-modern modal text editor, packaged from upstream `master` |
| `cosmic-desktop-mcp` | MCP server for driving a COSMIC/Wayland desktop |
| `activitywatch` | Automatic time tracker: `aw-server-rust`, `aw-webui` and the watchers |
| `fcitx5-vinput` | Voice input addon for Fcitx5, local or cloud ASR |
| `siyuan` | Privacy-first personal knowledge management system |
| `disktree` | Disk usage treemap for finding and removing files |

## Use it

### One-off, nothing to configure

```bash
nix shell 'github:mtul0729/nixpkgs/integration#legacyPackages.x86_64-linux.magpie'
```

### As a flake input

```nix
{
  inputs.integration.url = "github:mtul0729/nixpkgs/integration";
  # no `inputs.nixpkgs.follows` here — on purpose, see "Binary cache" below
}
```

Take attributes directly:

```nix
environment.systemPackages = [
  inputs.integration.legacyPackages.${pkgs.stdenv.hostPlatform.system}.magpie
];
```

Or overlay them onto your own `pkgs`:

```nix
nixpkgs.overlays = [
  (final: prev: {
    inherit (inputs.integration.legacyPackages.${final.stdenv.hostPlatform.system})
      magpie
      dashbeam
      helix
      cosmic-desktop-mcp
      activitywatch
      fcitx5-vinput
      siyuan
      disktree;
  })
];
```

### Binary cache

```bash
cachix use mtul
```

CI builds every package on `integration` and pushes it to that cache, so using it is normally
a download instead of a compile. This is also why the input deliberately does **not** follow
your nixpkgs: the cache is keyed by derivation, and only evaluating against the nixpkgs the
CI used produces the derivation that is in the cache. Following your own nixpkgs would give
you different derivations and you would build everything from source.

## Branches

| Branch | What it is |
| --- | --- |
| `master` | `nixos-unstable` plus the CI and docs commits. No packages. |
| `pkg/<name>` | One package per branch, in `pkgs/by-name/...` |
| `pr/<name>-<version>` | The same tree staged for an upstream PR |
| `integration` | All `pkg/*` branches rebased onto today's `nixos-unstable`, built and cached. **This is the branch to use.** |

`integration` is regenerated every hour. If one branch conflicts with upstream it is skipped
and named in the log; the rest still get merged and published, so one broken package does not
take the cache down for the others.

## Updates

Packages that declare `passthru.updateScript` are bumped automatically: CI checks upstream
every hour, runs `nix-update`, builds, and pushes to the package branch only if the build
passes. `integration` is regenerated right after. Packages without an update script are
pinned by hand.

## Issues

Open an issue here, not upstream — unless the problem is in nixpkgs itself.
