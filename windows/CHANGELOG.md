# Windows Codex Dream Skin — 更新日志

## Unreleased

### Fixed

- 重启 Codex 时只会关闭官方 `OpenAI.Codex` 包中的 `ChatGPT.exe`，不再误伤其他同名应用进程。
- CDP 连接会验证监听端口所属 PID 与官方 Codex 进程树，拒绝伪造的本机调试端点。
- 为 CDP HTTP 探测、WebSocket 建连和命令响应增加超时，失败时能够退出并清理 injector。

### Added

- Windows 主题现在会根据所选背景图自动分析明暗，切换浅色或深色的中性透明玻璃界面。
- 换图后背景会覆盖主要工作区并保持 `cover` 比例，不再固定使用粉色渐变、闪光、蝴蝶结或图片的 300% 裁切。
- 修复热重应用时复用旧图片对象的问题；重新选择图片后会立即使用当前主题图片。
- 新安装的 Windows 基础壳改用中性 Slate 色，不再把官方 chrome 预设为粉色。
- 新增 `windows/DreamSkin.exe` 桌面控制器，可选择背景图片与自适应、浅色、深色三种玻璃风格，并调用现有 CDP 脚本应用或恢复主题。
- `DreamSkin.exe` 使用项目中的 `image-studio-task-mrmx8vxv-ngo98z5.png` 作为嵌入式应用图标。
- 修复桌面控制器在应用或恢复主题时因同步等待 PowerShell/CDP 而显示未响应的问题；脚本现在异步执行并有超时，验证失败时会清理后台 injector。

### 改进

- CDP WebSocket 现在只接受 loopback 地址，并要求端口与启动参数一致。
- 注入前会检查 Codex renderer 的原生 shell、侧栏和 composer 标记，拒绝不匹配的 `app://` 页面。
- 启动和恢复时会校验 injector 的 PID、启动时间、可执行文件和命令行，避免 PID 复用导致误杀。
- 增加 `windows/assets/theme.json` 主题协议，Windows injector 支持主题图片和推广标题/副标题，并提供离线 payload 检查。
- 新增“Codex Dream Skin - 换图”快捷方式，可选择 PNG/JPG/JPEG/WebP 图片并立即应用到用户主题目录，不覆盖仓库素材。
- 修复换图脚本的 PowerShell 字符串解析、内置 `$PID` 参数冲突和 UTF-8 BOM 主题读取问题。
