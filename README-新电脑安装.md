# harness 快捷方式 · 新电脑安装说明

## 安装包内容
- `setup-new-pc.ps1`     一键安装脚本（在新电脑上运行这个）
- `start-harness.ps1`    启动器（安装脚本会自动复制到位，不用手动动它）
- `deepseek-color.ico`   图标文件

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
