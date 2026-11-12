# 版本管理

源码仓库为 `xiaosa223/fakecc`，Skill 单独维护在 `xiaosa223/claude-code-setup`。

## 日常修改

提交 `main` 或创建 PR 后，Checks 会验证前端测试、类型/生产构建、四处版本一致性、版本脚本回归，以及使用临时数据的 Windows 终端向导。

## 版本发布

1. 执行 `python scripts/versioning.py set 0.2.1`，同步 package.json、Tauri 配置、Cargo.toml 和 Cargo.lock 中的应用版本。依赖版本不随之修改。
2. 提交后创建匹配的 `v0.2.1` 标签，并推送提交和标签。
3. Windows release 检查版本、前端与终端，准备固定摘要的浏览器，执行 UI 验收，再生成 NSIS 安装器。
4. 安装载荷检查核对程序架构、引擎/前端/终端文件和许可资源，生成 `fakecc.exe`、`SHA256SUMS`、`verification.json`。
5. 检查和构建成功后，独立发布任务才获得写 Release 的权限。构建任务没有发布权限。

已存在的 Release 保留不变；不要重复使用同一版本号替换文件。Actions 手动运行默认只构建，勾选 publish 才创建新 Release。

首次 `v0.2.0` 发布当前已经核对过的本地预览安装包。后续标签版本由 GitHub 构建；初始预览和云端构建的二进制哈希不承诺一致。

## 更新边界

用户从 Releases 下载新安装包手动更新。当前没有配置应用内签名自动更新；不要把 GitHub 的 SHA-256 校验误称为 Windows 代码签名或 Tauri 更新签名。

真正启用应用内更新前，需要独立生成并妥善保管更新私钥，只把公钥和自有 HTTPS 清单配置进客户端，再测试旧版本升级。签名私钥、用户 token、真实线路配置和订阅不得进入公开仓库或 Release。

现有安装载荷核对不是运行安装器或真实账号端到端验收；首次公开版本仍属于预览版。原始第三方许可说明与缺口记录保留在 NOTICE.md。
