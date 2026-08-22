# harness 快捷方式 · 新电脑安装说明

## 安装包内容
- `setup-new-pc.ps1`     一键安装脚本（在新电脑上运行这个）
- `start-harness.ps1`    启动器（安装脚本会自动复制到位，不用手动动它）
- `update-plugins.ps1`   插件自动更新脚本（start-harness.ps1 会调用它）
- `deepseek-color.ico`   图标文件

## 每次启动自动更新（默认开启）
- **Harness 本体**：检测到 npm 有新版 → 同步更新完再启动（本次即最新）
- **插件全家桶**：检测到新版 → 20 秒内更完就本次生效；超时则先启动服务、更新转后台（下次启动生效）
- 紧急排查可跳过更新：`powershell -ExecutionPolicy Bypass -File start-harness.ps1 -SkipUpdate`
- 日志：`launcher\plugin-update.log` 与 `~/.dsh/logs/autoupdate.log`

## 步骤

1. **把整个文件夹**（或里面的 3 个文件）拷到新笔记本上
   （OneDrive、U盘、微信传文件都行）

2. 在新笔记本上，**以管理员身份打开 PowerShell**（搜索 PowerShell → 右键 → 管理员身份运行），执行：

   ```powershell
   powershell -ExecutionPolicy Bypass -File "setup-new-pc.ps1 的完整路径"
   ```

   > 如果文件是网上传来的，先右键文件 → 属性 → 勾选"解除锁定"，或者直接用上面的 Bypass 命令。

3. 完成。桌面上会出现 **harness** 快捷方式（彩色鲸鱼图标），双击即可。

## 前提条件

- 新笔记本需要安装 **Node.js LTS**：https://nodejs.org
  （没装也能先跑安装脚本，它会提示你装好 Node 后直接双击图标即可）
- 首次双击启动时，网页会要求填写一次 API 密钥，之后永久记住，不用再填。

## 自定义

- 工作区默认建在 `桌面\DeepSeek workSpace`，想放别处：

  ```powershell
  powershell -ExecutionPolicy Bypass -File setup-new-pc.ps1 -Workspace "D:\my-workspace"
  ```
