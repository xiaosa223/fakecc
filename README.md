# fakecc

Windows 上的 Claude Code 本地配置助手。推荐路线：准备网络 → 官方 Claude Code → `claude setup-token` → 本机保护 token → 进入项目。

**[下载最新版 fakecc.exe](https://github.com/xiaosa223/fakecc/releases/latest/download/fakecc.exe)** · [全部版本](https://github.com/xiaosa223/fakecc/releases) · [配置 Skill](https://github.com/xiaosa223/claude-code-setup)

首页提供配置、启动和环境检查入口。token 只在独立终端中输入，使用当前 Windows 用户 DPAPI 加密保存；认证和代理只注入本次启动的进程。身份、浏览器和系统功能保留在高级工具中。

## 安装与更新

从 Releases 下载 `fakecc.exe`，对照同一版本的 `SHA256SUMS` 检查完整性，再运行安装器。当前支持 Windows x64；缺少 WebView2 时安装器会下载微软运行时。

新版本仍下载同名 `fakecc.exe` 安装覆盖。应用内目前使用手动更新，不会静默安装 GitHub 上的文件。安装器尚未 Authenticode 签名；已有本地检查不代替干净系统和真实账号验收。

## 本地开发

需要 Bun 1.3.11、Python 3.13、Rust MSVC 1.93.1、Visual Studio C++ 构建工具和 WebView2。

```powershell
bun install --frozen-lockfile
bun test
bun run build:custom
bun run build:windows
bun run release:verify
```

首次构建会下载固定版本、固定 SHA-256 的配套浏览器引擎；大文件和生成产物不提交 Git。Windows 终端向导已包含在 `terminal-setup/`，构建不需要仓库之外的文件。

检查界面：先运行 `python scripts/fetch-browser.py` 准备引擎，再运行 `bun run test:ui`。截图使用隔离的测试数据，不读取真实账号。

## 发布新版本

运行以下命令后，GitHub 会自动检查、构建并发布新版本：

```powershell
python scripts/versioning.py set 0.2.1
git add package.json src-tauri/tauri.conf.json src-tauri/Cargo.toml src-tauri/Cargo.lock
git commit -m "Release 0.2.1"
git tag v0.2.1
git push --atomic origin main v0.2.1
```

版本脚本同步四处版本号；标签与源码版本不一致时发布会停止。也可以在 Actions → Windows release 手动运行，仅构建预览包，或勾选发布。已经发布的版本保留原文件，修改内容应使用新版本号。

每个 Release 包含 `fakecc.exe`、`SHA256SUMS` 和 `verification.json`。详情见 [发布说明](docs/releases.md)。

## 可选资源

| 服务 | 文案 | 入口 |
| --- | --- | --- |
| DMIT | VPS 服务器 · 返佣推广 | [访问](https://www.dmit.io/aff.php?aff=30283) |
| Webshare | 代理资源 · 返佣推广 | [访问](https://www.webshare.io/?referral_code=5hr8v0sunytu) |
| 代充站 | 低价源头代充 · 推广 | [xiaosa.win](https://xiaosa.win) |
| API 中转站 | 不降智稳定中转站 · 推广 | [api.lsidestudio.com](https://api.lsidestudio.com) |

已有线路可直接使用，购买不是配置前提；商业服务与官方订阅授权分开。

## 许可

项目保留 [LICENSE](LICENSE) 和 [第三方说明](NOTICE.md)。第三方材料适用其各自条款；其中已记录的许可缺口不会因为建立仓库而自动消失。
