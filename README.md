# Album Manager

Windows / macOS / Linux 专辑库管理工具（Flutter + Rust），适用于 CD 抓轨与数字资源混合的收藏。

- **专辑库**：封面墙 / 列表，搜索、筛选、排序、收藏
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
scripts/           Windows 打包脚本
```

## 开发

```sh
cd app
flutter pub get
flutter_rust_bridge_codegen generate   # 修改 Rust 接口后
flutter run -d windows                 # 或 macos / linux

cargo test --workspace                 # 在仓库根目录
```

## 发布

推送版本标签即触发 Release 工作流，在三个系统上测试、构建并发布：

```sh
git tag v0.1.0
git push origin v0.1.0
```

产物包括 Windows ZIP 与安装程序、macOS 通用 `.app`、Linux `tar.gz` 及 SHA-256 校验文件，均未代码签名。

## 许可证

[MIT](LICENSE)
