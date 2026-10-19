# Album Manager

Windows / macOS / Linux 专辑库管理工具（Flutter + Rust），适用于 CD 抓轨与数字资源混合的收藏。

- **专辑库**：封面墙 / 列表，搜索、筛选、排序
- **专辑详情**：曲目、抓轨日志校验、扫图、文件
- **时间线 / 统计**：按年份浏览，来源、音质、格式分布
- **健康检查**：缺封面、CUE 编码与引用、抓轨错误、缺日志

## 结构

```
crates/
  album-model/     数据类型
  album-formats/   CUE、抓轨日志、音频、文本编码解析
  album-core/      扫描、分析、缓存、缩略图
app/               Flutter 应用（rust/ 为 flutter_rust_bridge 桥接层）
```

## 开发

需要 Flutter 3.47.6（Dart 3.13.5）或兼容版本，以及 Rust stable / Cargo。
各平台的桌面应用需要在对应系统上构建，Rust 桥接库由 Cargokit 自动编译。

- Windows：安装 Visual Studio 的“使用 C++ 的桌面开发”工作负载。
- macOS：安装 Xcode、命令行工具和 CocoaPods，最低运行版本为 macOS 12。
- Linux（Ubuntu）：安装以下依赖：

```sh
sudo apt-get install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libstdc++-12-dev libfontconfig1-dev libfreetype6-dev xdg-utils
```

```powershell
cd app
flutter pub get
flutter_rust_bridge_codegen generate   # 修改 Rust 接口后
flutter run -d windows
# macOS: flutter run -d macos
# Linux: flutter run -d linux

cargo test --workspace                 # 在仓库根目录
```

发布构建使用 `flutter build windows --release`、`flutter build macos --release`
或 `flutter build linux --release`。Linux 分发时需保留完整的 `bundle` 目录。
GitHub Actions 的 Desktop 工作流会在三个系统上运行 Rust 测试、Flutter 静态分析和发布构建。

macOS 当前采用直接分发模式，关闭 App Sandbox，以便 Rust 扫描器能在重启后继续访问已保存的专辑库路径；
尚未配置 Mac App Store 沙箱书签、Developer ID 签名或公证。
在文件管理器中定位文件时，Windows/macOS 会选中文件，Linux 打开其所在目录（需要 `xdg-open`）。

## 发布

将代码提交并推送后，推送版本标签即可触发 Release 工作流：

```sh
git tag v0.1.0
git push origin v0.1.0
```

标签格式为 `v主版本.次版本.修订号`；例如 `v0.2.0-rc.1` 会发布为 GitHub 预发布版本。
应用的构建版本使用标签中的三段数字，构建号使用工作流运行编号。
工作流先执行 Rust 测试和 Flutter 静态分析，再构建并发布：

- `AlbumManager-<标签>-windows-x64.zip`：完整应用目录，解压后运行 `album_manager.exe`。
- `AlbumManager-<标签>-macos-universal.zip`：包含 Intel / Apple Silicon 通用 `.app`，未进行 Developer ID 签名和公证。
- `AlbumManager-<标签>-linux-x64.tar.gz`：完整 bundle，保留目录结构后运行 `./album_manager`；构建基于 Ubuntu 24.04，目标系统需提供兼容的 GTK 3、Fontconfig、FreeType 和 `xdg-utils`。
- `SHA256SUMS.txt`：以上三个压缩包的 SHA-256 校验值。

只有全部平台成功后才发布 Release。上传失败时会保留草稿，可以重跑工作流继续上传；
已公开发布的版本不会被重跑覆盖，应推送新版本标签。发布使用内置 `GITHUB_TOKEN`，无需额外配置令牌。
普通分支推送与 PR 仍由 Desktop 工作流检查，标签推送只运行 Release 工作流。

## 许可证

[MIT](LICENSE)。内置的 HarmonyOS Sans 字体（`app/assets/fonts/`）遵循其自身的许可协议。
