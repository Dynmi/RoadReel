# Privacy

RoadReel processes recordings entirely on your Mac.

- It does not create an account.
- It does not contain analytics, advertising, crash-reporting, or tracking SDKs.
- It checks a signed update feed on GitHub at launch and every six hours while running. GitHub receives normal connection information such as your IP address and the updater's user agent. Update checks do not include recordings, folder paths, or a system profile.
- Updates are downloaded from GitHub only after you click Update. The app verifies the update signature before installing and reopening. The GitHub link opens the project in your browser.
- It looks for TeslaCam folders on mounted drives and reads recordings from the active source, subject to macOS file-access permissions. You can also choose a folder manually.
- Exported clips are written only to the destination you choose.
- Trim & Replace writes a verified, shortened project to the original location and moves the original recordings to macOS Trash.
- Deleted recordings are moved to macOS Trash rather than permanently erased.
- Your selected folder is remembered with a macOS security-scoped bookmark stored in local app preferences.

You can revoke file access by removing RoadReel and its preferences from your Mac.

## 中文摘要

RoadReel 在本机处理录像，不包含账号、广告、分析、崩溃上报或跟踪 SDK。应用会在启动时及运行期间每六小时访问 GitHub 检查更新；GitHub 可见 IP 地址和更新器 User-Agent 等正常连接信息，但不会收到录像、文件夹路径或系统画像。只有点击“更新”后才下载、验证并安装更新，随后自动重启。GitHub 入口会在浏览器打开项目。

应用会在已挂载的磁盘中查找 TeslaCam 文件夹，并在 macOS 文件访问权限允许的范围内读取当前来源的录像；你也可以手动选择文件夹。导出文件只写入你选择的位置；截取替换会将验证后的短片项目写回原位置，并将原录像移入 macOS 废纸篓；删除操作同样移入废纸篓。
