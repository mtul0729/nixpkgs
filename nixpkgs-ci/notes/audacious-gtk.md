# audacious：把 GTK 后端开回来

目标：让 nixpkgs 的 `audacious` 同时编 GTK 与 Qt。上游 issue
[NixOS/nixpkgs#566392](https://github.com/NixOS/nixpkgs/issues/566392)（2026-09-24 开，仍 open）
已经把论据写完；这份文档记录**上游 PR 需要的全部事实 + 实测踩到的两个坑**，PR 本身暂时搁置
（2026-10-21：先在 fork 上修好实测）。

## 现状

- `pkgs/by-name/au/audacious-bare/package.nix`：mesonFlags `-Dgtk=false`（另有 `-Dbuildstamp=NixOS`）
- `pkgs/by-name/au/audacious-plugins/package.nix`：mesonFlags `-Dgtk=false`
- 全树只有这两处 `-Dgtk`
- 包装：`pkgs/top-level/all-packages.nix` 里 `audacious = audacious-bare.override { withPlugins = true; };`
- 反向依赖只有 `libaudclient`、`vgmstream`、`all-packages`，不是 mass rebuild

## 为什么是 `-Dgtk=false`：三次机械继承，没有任何文字理由

| 时间 | 提交 | 做了什么 |
| --- | --- | --- |
| 2020-07 | `7f64f213`，PR **#93240**（gebner）`audacious: 3.9 -> 4.0.5` | 把源码从 `audacious-…-gtk3.tar.bz2` 换成 Qt tarball，理由是「4.0 起 Qt 是默认，GTK 的开发似乎已经停止」 |
| 2021-11 | `ee718148`，PR #147247 | 加 `configureFlags = [ "--disable-gtk" ]` |
| 2022-08 | `b8dc7a5e`，PR **#185165**（thiagokokada）meson 移植 | 直译成 `mesonFlags = [ "-Dgtk=false" … ]`，沿用至今 |

`git log --grep=gtk -i` 在这两个路径上**没有任何提交说明过 GTK**。除了 2020 年那句「开发似乎已停止」，
没有别的记录下来的理由 —— PR 的说服力就在这里：支撑这个 flag 的是 6 年前的一句推测。

## 上游（audacious-media-player）现在的状态

- **4.3** 恢复 GTK 3 支持（2018 年被砍掉的）
- **4.4**（2024）发布说明：Qt 6 与 GTK 3 都是默认，**「GTK support is no longer considered legacy」**
- **4.5 / 4.6** 仍在给 GTK 修 bug、补插件（`gtkui: Fix slider knob click behavior`、`Port Playback History plugin to GTK`、`Require GTK >= 3.24`）
- meson 默认 `gtk=true` **且** `qt=true`（BLFS 也是这么编）—— **是 nixpkgs 在偏离上游默认**
- `--gtk` / `--qt` 只在 `USE_QT && USE_GTK` 同时成立时才编译进二进制（`src/audacious/main.cc`）
- `use_qt` 配置键默认 TRUE → **双后端构建默认仍进 Qt 界面**，GTK 是 opt-in，不改变用户默认体验
- 无 GTK 4；GTK 3 要求 >= 3.24

## 关掉 GTK 的代价

16 个插件消失（对比 4.6.1 的 `-Dgtk=true` 构建）：

- General：`albumart` `aosd` `filebrowser` `gtkui` `hotkey` `lyrics-gtk` `playback-history` `playlist-manager` `search-tool` `skins` `statusicon`
- Effect：`ladspa`
- Visualization：`blur_scope` `cairo-spectrum` `gl-spectrum` `vumeter`

（`skins` 是 Winamp 皮肤界面，和已经在的 `skins-qt` 不是同一个。）

## 改法与代价

两个包**必须一起改** —— 它们共享插件 ABI，只改一个会 ABI 不匹配。

- `audacious-bare`：`-Dgtk=true`，buildInputs 加 `gtk3`
- `audacious-plugins`：`-Dgtk=true`，buildInputs 加 `gtk3` 和 `json-glib`（`lyrics-gtk` 需要；
  少了它 meson 直接 `Dependency "json-glib-1.0" not found`）
- 闭包 +1.72 MiB（4.6.1 实测：`audacious` +863 KiB、`audacious-plugins` +899 KiB）
- `vgmstream` 作为 `audacious-bare` 的反向依赖重建

## 坑一：只翻 `-Dgtk=true`，GTK 界面一开文件对话框就崩

2026-10-21 实测（fork 分支只翻了 flag、没补包装时）：

```
systemd-coredump: Process 11612 (.audacious-wrap) of user 1000 dumped core  (SIGABRT)
  gtk_menu_shell_activate_item
  -> gtk_widget_activate -> gtk_widget_show -> gtk_window_map
  -> gtk_file_chooser_widget_map -> settings_load
  -> _gtk_file_chooser_get_settings_for_widget      (libgtk-3.so.0)
```

`settings_load` 里是 `g_settings_new("org.gtk.Settings.FileChooser")`。NixOS 上 gsettings schema
只存在于 store 路径（`gtk3` 的 `share/gsettings-schemas/gtk+3-*/glib-2.0/schemas/`，**确实在闭包里**），
没有 `GSETTINGS_SCHEMA_DIR` 就找不到 → GLib 直接 abort。而 audacious 的二进制是裸 ELF，只被
`qt6.wrapQtAppsHook` 包过，没人设这个变量。

修法（nixpkgs 里 Qt + GTK 混用的通行写法，见 `brewtarget`、`beamerpresenter`）：

```nix
nativeBuildInputs = [ … qt6.wrapQtAppsHook wrapGAppsHook3 ];
dontWrapGApps = true;
preFixup = ''
  qtWrapperArgs+=("''${gappsWrapperArgs[@]}")
'';
```

**这条是 PR 的一部分，不是可选项** —— 少了它，PR 就是给上游送一个默认崩溃的 GTK 界面。

## 坑二：`wrapGAppsHook` 已经改名叫 `wrapGAppsHook3`

2025-10-27 起 `wrapGAppsHook` 是 throw 别名（`aliases.nix`）：

```
error: 'wrapGAppsHook' has been renamed to/replaced by 'wrapGAppsHook3'
```

CI 第一版就是这么红的，一秒就失败，不用等构建。

## 状态

- fork 分支 `pkg/audacious`：`2d130824` 起带 `-Dgtk=true` + `wrapGAppsHook3`
- 待实测：系统切到这份构建后，GTK 界面点 File → Open Files 应当正常弹出对话框
- 上游 PR：搁置。要开时还需要
  - `nixpkgs-review`（`meta.platforms = linux`，跑 x86_64-linux / aarch64-linux，不开 darwin）
  - release note：`doc/release-notes/rl-2611.section.md` 的 *Other Notable Changes* 加一条
  - AI 披露：commit 带 `Assisted-by:` trailer，PR 描述里单独再写一次（CONTRIBUTING.md 的
    Automation/AI policy，第 896 行起）
  - 链接 `Fixes #566392`，并 @ 维护者（thiagokokada 是 #185165 的作者）

## 一个工具限制（省得下次再踩）

cosmic-desktop MCP 的 EIS 只能把**指针移动**送进桌面（能触发焦点跟随），按钮按下和按键事件到不了
目标窗口 —— 试过点击菜单、点工具栏、点关闭按钮、按 Alt+F、按空格，窗口像素级零变化。所以
「点 File → Open Files」这类验证只能人工做，别再花时间用 MCP 点。
