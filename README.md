# Album Manager

Windows 专辑库管理工具（Flutter + Rust），适用于 CD 抓轨与数字资源混合的收藏。

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

```powershell
cd app
flutter_rust_bridge_codegen generate   # 修改 Rust 接口后
flutter run -d windows

cargo test --workspace                 # 在仓库根目录
```

## 许可证

[MIT](LICENSE)。内置的 HarmonyOS Sans 字体（`app/assets/fonts/`）遵循其自身的许可协议。
