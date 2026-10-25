# strata：GTK4 文件管理器的 Nix 打包

目标：把 [lgse/strata](https://github.com/lgse/strata) 1.1.0 加进 fork，保持默认功能可用，
同时让由 Nix 管理的安装不要把应用内更新误判成 AUR 更新。包位于
`pkgs/by-name/st/strata/`，另带一个小补丁 `nix-update.patch`。

## 上游事实

- Rust + GTK4 的键盘优先文件管理器，MIT，只支持 Linux。
- 默认 Cargo feature `rar` 依赖非自由 UnRAR 源码；Nix 包使用
  `buildNoDefaultFeatures = true`，因此不编 RAR 支持。
- 普通安装的更新方式包括应用内替换二进制、AUR、Omarchy 和 pacman。上游原本把任何
  `install-source.toml` marker 都当成包管理器安装，随后按 AUR 处理。
- 更新检查、安装器和设置界面中有若干 `UpdateMethod` 穷尽匹配；增加 Nix 分支时必须一起
  处理，否则编译会在非穷尽匹配处失败。
- 沙箱相关路径在编译期读取环境变量并嵌入二进制，运行时不需要把工具目录塞进
  `PATH`。`STRATA_TRUSTED_COMMAND_PATH` 也必须指向 store 里的真实可执行文件，不能指向
  运行时才构造的 FHS 路径。

## 打包决策

### 构建与依赖

- 使用 `rustPlatform.buildRustPackage`、`cargoHash` 和 `wrapGAppsHook4`，避免 IFD。
- `src` 哈希：
  `sha256-FoYYsjvWY+1SuZtvxancdVR6h7iFmnbtHXW2eTlVCJI=`
- `cargoHash`：
  `sha256-U52ypUksrz/2G8apmyh7x9c+47ZBStT1lHIWso7KfU4=`
- GTK 运行时需要 GStreamer 插件；在 `preFixup` 把
  `GST_PLUGIN_SYSTEM_PATH_1_0` 追加到 `gappsWrapperArgs`，确保插件进入 wrapper 的闭包。
- `gnome._gdkPixbufCacheBuilder_DO_NOT_USE` 只为沙箱子进程生成带 librsvg loader 的
  pixbuf cache。不要把 LibRaw 的 `out` 加进沙箱 `PATH`：Nixpkgs 的 `libraw` 没有
  `bin/`，缩略图所需的 LibRaw 支持已经由 ImageMagick 带入。

### 桌面集成

- 上游没有安装 desktop 文件和 icon，包在 `postInstall` 手动安装：
  `share/applications/io.github.lgse.Strata.desktop` 与
  `share/icons/hicolor/scalable/apps/io.github.lgse.Strata.svg`。
- FileManager1 的 per-user D-Bus service 只作为模板放进 `share/strata/`，不放进
  `share/dbus-1/services/`。否则仅安装包就会声明该 bus name，改变用户默认文件管理器。
  模板中的 `/usr/bin/strata` 会替换成 `$out/bin/strata`。

### 应用内更新器

安装时写入：

```toml
manager = "Nix"
package = "strata"
channel = "stable"
```

上游补丁增加 `UpdateMethod::Nix`：

- marker 为 `Nix`（忽略大小写和空白）时识别为 Nix，其余 marker 仍按 AUR 处理。
- Nix 模式的更新检查直接返回 `UpToDate`，不查询 AUR。
- 拒绝应用内替换 Nix 拥有的二进制；更新对话框只显示由包管理器管理并提供关闭操作，
  不启动终端或包管理器。
- 增加 marker 识别测试和 Nix 更新对话框测试。

这是有意的最小补丁。伪造 pacman 或 AUR 会让应用声称一个并不存在的所有者，也会把用户
引向错误的更新路径。

## 验证

已在本地完成：

```bash
nix-instantiate --eval --strict --option allow-import-from-derivation false \
  -A strata.drvPath
nix build --no-link .#strata.cargoDeps
nix build --no-link .#strata.src
nix fmt
git diff --check
```

`drvPath` 为
`/nix/store/pwjmzaidj8xl1c52kjihqgpcgx4klg8s-strata-1.1.0.drv`。完整的
`nix build .#strata` 本地太慢，按仓库规则改由 fork CI 编译，不在本地继续跑。

包设置 `doCheck = false`。上游测试套件需要完整桌面会话，以及 xattr、setgid 目录和
GIO Trash 等 Nix 构建沙箱不提供的宿主文件系统能力；按 fork 的 `pkg/` 策略，构建期
不运行测试。若以后准备向上游提 PR，测试要求和策略应在单独的 PR 分支中重新处理。

## CI 结果

`build-branch` 运行
[40170888757](https://github.com/mtul0729/nixpkgs/actions/runs/40170888757)
于 21 分 34 秒内通过。构建产物为：

```text
/nix/store/4w0z3mzd5s1y385qipr2r2schzar15k6-strata-1.1.0
```

该路径已推送到 `mtul.cachix.org`；NAR hash 为
`sha256:0lb7hycjhvfn6j02q66rqxvyscafnj3hq106aqr09lqiwlasv0mv`。日志确认执行了
IFD 检查、完整构建、`installPhase`、GTK wrapper 和缓存推送。构建只产生三个上游
warning，没有测试失败，因为测试按上面的 `pkg/` 策略关闭。

## 分支与登记

正式长期分支为 `pkg/strata`，与通过 CI 的 `test/strata-init` 指向同一提交
`a95241a3`。`pkg/strata` 已加入 `nixpkgs-ci/branches.txt`；临时
`test/strata-init` 不再是长期分支，可在确认无其他用途后删除。
