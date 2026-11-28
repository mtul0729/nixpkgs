# sherpa-onnx：2.0.3、上游 PR 与自动更新

这份文档是这条线的入口。上游 PR
[#594460](https://github.com/NixOS/nixpkgs/pull/594460) 已经开着（`ready for review`，
没有 reviewer）；fork 侧的 `pkg/sherpa-onnx` 带着同一份内容，另外多一个自动更新脚本，
等 PR 合入后再单独提。

## 东西在哪

| 用途 | 位置 |
| --- | --- |
| 上游 PR | `pr/sherpa-onnx-2.0.3` @ `46565696dd30`，基于 `upstream/master` |
| PR 的后续改动（`update.sh`） | `test/sherpa-update-script` @ `8ac85cff75a4`，基于 `nixos-unstable`，只用于 `build-branch` 验证 |
| fork 包分支 | `pkg/sherpa-onnx` @ `e2733b58a3bb`：PR 内容 + 脚本 + 本目录的 `README.md` |
| 打包约束与取舍 | 分支里的 `pkgs/by-name/sh/sherpa-onnx/README.md` |
| 发 PR / 跟 PR 的流程 | [`nixpkgs-ci/upstream.md`](../upstream.md) §4、§6 |

表里的 SHA 是 2026-11-28 的快照。分支会被 CI 改写（`update` 每次都会 rebase 候选），
按分支名找，别按 SHA 找。

`pkg/sherpa-onnx` 在 `nixpkgs-ci/branches.toml` 里排在 `pkg/fcitx5-vinput` 之前：后者依赖
前者，顺序是这里唯一的堆叠机制。

## 2.0.3 为什么连带这么多改动

- 上游删掉了 espeak-ng / piper-phonemize 这套 TTS 栈，`espeak.patch` 存在的理由随之消失
  （那个补丁只是在压 `-Werror=format-security`）。
- FetchContent 的依赖集变了：新增 `kaldi-hmm-gmm`、`kaldi-native-io`、`utf8proc`，
  `cargs` 随 espeak-ng 一起消失，`kaldi-native-fbank` / `kaldifst` / `kaldi-decoder` 换了版本。
- 压缩包必须按 CMake 探测的名字放进源码根，`kaldi_native_io` 是**下划线**。

## 为什么需要 `update.sh`

每个依赖钉在自己的 `cmake/<dep>.cmake` 里：

```cmake
set(<dep>_URL  "https://...")
set(<dep>_HASH "SHA256=<hex>")
```

而且 `.../Downloads/<file>` 的文件名是硬编码的。三样东西都随 release 走，`nix-update`
只能改 `version` 和源码 hash，改不了这份列表 —— 用默认 `nix-update-script` 的话，下一个版本
会拿旧依赖集去构建。`generate-cache.py` 就是把这些 `.cmake` 解析成 `package.nix` 里
`# BEGIN/END generated cache` 之间的列表。

生成时跳过两类：`cmake/onnxruntime*.cmake`（nixpkgs 通过 `onnxruntime_SOURCE_DIR` 提供）
和 `portaudio`（构建里关掉了）。

## 两个坑

1. **`nix-update -u` 的 cwd 是 nixpkgs 根，脚本本体在 store 里。** 它走
   `maintainers/scripts/update.nix`，以 `cwd=<被更新的树>` 执行 store 里的那份脚本，所以
   `$BASH_SOURCE/../../../..` 会解析到 `/nix`。路径要按 cwd 写，shebang 带 `-I nixpkgs=.`
   （`he/helix` 同款）。只测"直接执行"会漏掉这条：旧版脚本的 ls-remote fast path 正好把它
   掩盖了，是走 `nix-update -u` 才暴露的。
2. **别自己解析 tag。** 直接调 `nix-update`，比较调用前后的 `version`；变了才重新生成。
   自己抓 tag 列表等于把 tag 命名规则抄一遍，上游换个命名就坏。

## 验证过什么（2026-11-28）

- 2.0.2 起跑：生成结果与手写的那份**逐字节相同**；直接执行和 `nix-update -u`（1.16.0，
  CI 用的版本）两条路径都是。
- no-op 约 8 秒，`package.nix` 一个字节都不动。
- 脚本本身不进 drv（`passthru` 而已），所以换脚本不触发重建。
- CI：`build-branch` 46124760777（脚本版）、46127990208（`pkg/sherpa-onnx` 新 tip），
  `sherpa-onnx` 与 `sherpa-onnx.tests.offlineRecognition` 都过。
- PR 的 `nixpkgs-review`：46117491064（`x86_64-linux` + `aarch64-linux`，各 5 个包）、
  46121259236（`aarch64-darwin` relaxed，4 个包）。`x86_64-darwin` 不跑 —— 那个 runner
  永远不接单，`macos-latest` 是 Apple Silicon。

## 已知取舍

生成列表是平的，`asio` / `websocketpp` 不再包在 `lib.optionals websocketSupport` 里。
默认 `websocketSupport = true` 时集合与手写版一致；`false` 时只是多取两个不参与编译的
固定输出包。要保留条件，就得继续手写"哪些依赖属于 websocket"。

## 下一步

1. **#594460 合入后**：`pkg/sherpa-onnx` 按 §6 收线 —— `git rebase upstream/nixos-unstable`
   时上游那条提交会自己掉出去，只剩脚本和 `README.md`。合入的版本若与携带的不同，直接取上游
   的、删掉我们的，不要逐行消解。
2. **另开 follow-up PR**：从 `upstream/master` 取 `test/sherpa-update-script` 的那一个提交
   （§4，别把 `pkg/*` 当 PR 分支），commit 带 `Assisted-by:`，再跑两批
   `nixpkgs-review`：先 Linux 两平台，再 `aarch64-darwin=yes_sandbox_relaxed`。
3. **两个 PR 都进 `nixos-unstable` 之后**，删掉 `pkgs/by-name/sh/sherpa-onnx/README.md` ——
   那时目录里只剩 delta 的规则就不需要它了。
4. **fcitx5-vinput** 的 flake 还钉着 `sherpa-onnx-flake`（2.0.1），可以在合适的时候提议去掉；
   不在这两个 PR 的范围里。
