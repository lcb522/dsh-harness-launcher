# dsh-harness-launcher · DeepSeek Harness 桌面一键启动器

把 DeepSeek Harness（DSH）Web GUI 变成**桌面双击即用**的便携启动器：
一键安装脚本会在桌面创建带彩色图标的 `harness` 快捷方式，双击后自动启动服务并打开浏览器。

## 包内容

| 文件 | 说明 |
|---|---|
| `setup-new-pc.ps1` | **一键安装脚本**（在新电脑上运行这个） |
| `start-harness.ps1` | 启动器（安装脚本会自动复制到位，无需手动动它） |
| `update-plugins.ps1` | 插件自动更新脚本（start-harness.ps1 每次启动调用） |
| `deepseek-color.ico` / `.png` | 桌面图标文件 |
| `make-icon-from-png.ps1` | 从 PNG 重新生成 ico 的工具脚本（可选） |
| `harness-portable.zip` | 以上安装文件的打包版，方便直接传输 |
| `README-新电脑安装.md` | 精简版安装说明（可随包一起拷走） |

## 每次启动自动更新（默认开启）

双击图标后，启动器在拉起服务前会自动做三级更新检查（`-SkipUpdate` 可跳过）：

| 对象 | 策略 |
|---|---|
| **Harness 本体**（全局安装） | 每次启动检测 npm latest；落后就**同步更新完再启动**（本次即最新）；180 秒硬超时，失败不阻塞启动 |
| **插件全家桶**（`@linxin666/dsh-web-ui-all`） | 每次启动检测；有新版时同步等待最多 20 秒（`-PluginUpdateBudgetSec` 可调）：**预算内完成 → 本次生效**；**超时 → 先启动服务，更新转后台，下次启动生效** |
| **本地 junction 插件**（如 `dsh-sync-panel`） | 每次启动扫描 profile `node_modules` 里的 junction/symlink 条目，对其源码 git 仓库 fetch 比对；落后且**工作区干净**才 `pull --ff-only`（本次启动即生效）；有未提交改动则跳过不动 |

安全设计：
- 服务**已在运行**时只开浏览器，不做任何更新动作（避免动运行中的文件）
- 后台更新等**服务就绪后**才启动，不会和服务抢 `node_modules`
- 版本比较用语义化版本规则（支持 `0.1.1-rc.2` 预发布号），**只升不降**
- 网络检查 15 秒超时，离线时快速跳过
- 日志：`launcher\plugin-update.log`（插件）与 `~/.dsh/logs/autoupdate.log`（Harness）

```powershell
# 紧急排查：跳过更新启动
powershell -ExecutionPolicy Bypass -File start-harness.ps1 -SkipUpdate
# 手动立即更新插件
powershell -ExecutionPolicy Bypass -File update-plugins.ps1
```

## 安装（新电脑）

1. **克隆或下载本仓库**：

   ```powershell
   git clone https://github.com/lcb522/dsh-harness-launcher.git
   ```

   或直接下载 ZIP（绿色 Code 按钮 → Download ZIP）后解压。

2. **以管理员身份打开 PowerShell**（搜索 PowerShell → 右键 → 管理员身份运行），执行：

   ```powershell
   powershell -ExecutionPolicy Bypass -File "setup-new-pc.ps1 的完整路径"
   ```

   > 网络传输的文件先右键 → 属性 → 勾选"解除锁定"，或直接用上面的 Bypass 命令。

3. 完成。桌面会出现 **harness** 快捷方式（彩色鲸鱼图标），双击即可。

## 使用

- 双击桌面 **harness** 图标 → 自动启动服务（首次约几秒到十几秒）并打开
  `http://127.0.0.1:3080`。
- 首次启动网页会要求填写一次 API 密钥，之后永久记住。
- 关闭启动窗口即停止服务；再次双击图标若服务已在运行，则直接打开浏览器。

## 前提条件

- **Node.js LTS**：https://nodejs.org（没装也能先跑安装脚本，它会提示装好 Node 后直接双击图标）

## 自定义

- 工作区默认建在 `桌面\DeepSeek workSpace`，想放别处：

  ```powershell
  powershell -ExecutionPolicy Bypass -File setup-new-pc.ps1 -Workspace "D:\my-workspace"
  ```

## 工作原理

`start-harness.ps1` 在工作区目录下执行 `npx -y @deepseek-ai/dsh web --port 3080`，
轮询 `http://127.0.0.1:3080` 就绪后自动唤起默认浏览器。
