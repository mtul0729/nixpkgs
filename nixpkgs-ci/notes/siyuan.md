# SiYuan：打包与服务端拆分经验

本文记录 `pkg/siyuan` 里不明显的约束和已经踩过的坑。部署策略、上游 issue 顺序和
当前运行状态在 sysadmin 仓库的
`systems/nixos/docs/services/siyuan.md`；
这里只写 nixpkgs 侧维护时容易再次踩到的东西。

## 产物结构

- `pkgs/by-name/si/siyuan/package.nix` 同时提供桌面客户端、`passthru.kernel`、
  `passthru.ui` 和 `passthru.server`。
- `siyuan-preview/package.nix` 通过 `siyuan.override { channel = "preview"; }` 选择
  `channels.json` 里的 preview pin。
- `passthru.server` 不包含 Electron，复用 `pkgs/by-name/si/siyuan` 中的 kernel 和
  静态 Web UI 构建。
- `passthru.tests.siyuan` 用 `extendNixOS` 强制 `services.siyuan.package` 指向当前
  server，不能让它悄悄测试默认的稳定版。

## fixed-port 能力判断

`--fixed-port=false` 从 `3.8.10-alpha.3` 开始可用。包通过
`passthru.fixedPortFlagSupported` 暴露能力，NixOS module 优先读这个属性，再回退到
版本判断。

不要把它简化成一个 `lib.versionAtLeast` 阈值。Nix 的版本比较把
`3.8.10-alpha.3` 视为高于 `3.8.10`，所以判断必须分开：

```nix
lib.versionAtLeast version "3.8.10"
|| (lib.versionOlder version "3.8.10"
    && lib.versionAtLeast version "3.8.10-alpha.3")
```

旧 kernel 依赖包内 `disable-fixed-port.patch` 和
`SIYUAN_DISABLE_FIXED_PORT=1`；支持的版本只用原生参数。修改这里时同时检查
`passthru.fixedPortFlagSupported`、module 生成的服务参数和 VM test。

## Electron 运行时目录冲突

从 `3.8.10-alpha.3` 开始，上游自己的 `build:electron` 会删除并重建
`app/electron-dist`。Nix 包还需要另一份 Electron 运行时交给
`electron-builder -c.electronDist=...`，不能也叫 `electron-dist`，否则
`pnpmBuildHook` 会在 electron-builder 之前删掉 Nix 运行时，最终表现为：

```text
ENOENT: no such file or directory, rename
'build/linux-unpacked/electron' -> 'build/linux-unpacked/siyuan'
```

运行时目录使用独立名称 `electron-runtime`。上游 `files` 里的 `electron-dist`
必须保持原样，它现在是应用自己的编译产物。

## 更新与构建

- 版本和 hash 由 `update.sh` / CI 更新，不手工猜版本。
- `channels.json` 的 stable 和 preview 是两个独立 pin；preview 更新不能顺手改 stable。
- `ocr-assets.json` 是上游 OCR 清单的逐字副本，版本变化时要同步刷新。
- 上游 `app/package.json` 使用 pnpm 12，但当前 `fetchPnpmDeps` 仍只能用 pnpm 11；
  升级 pnpm/fetcher 前不要假定可以照抄 upstream。

不要在本地编译大型客户端。先做无 IFD 求值，再交给 CI：

```bash
nix-instantiate --eval --strict --option allow-import-from-derivation false \
  -A siyuan-preview.drvPath \
  -A siyuan-preview.server.drvPath
```

验证 server 和 VM test 时，用 `build-branch` 指定内嵌属性：

```bash
gh workflow run build-branch.yml -R mtul0729/nixpkgs \
  -f branch=pkg/siyuan \
  -f attrs='siyuan-preview.server siyuan-preview.tests.siyuan'
```

VM test 覆盖服务启动、`6807`、`6806` 未监听、UI 资源和 `system` 代理模式。仅仅为了
验证这些端口行为，不需要把 alpha 包部署到用户的主机；主机等稳定版。

## 上游边界

- [issue 21133](https://github.com/siyuan-note/siyuan/issues/21133)：fixed-port 兼容监听，
  已在 alpha.3 提供原生开关。
- [issue 21167](https://github.com/siyuan-note/siyuan/issues/21167)：通用、只读的
  `conf.json` overlay 被关闭为 not planned；不要换标题重提。
- [issue 21170](https://github.com/siyuan-note/siyuan/issues/21170)：kernel 先监听端口，
  再初始化 appearance 资源；下游暂时用 `ExecStartPost` 有界等待。
- 浏览器 Web UI 的 ExportDocx 不是“少一个按钮”：浏览器构建会裁掉
  `app/src/protyle/export/index.ts`，现有导出流程依赖 Electron IPC 和目录选择器。
  当前使用 sysadmin 的 `systems/nixos/scripts/siyuan-export.py` 调 API。
