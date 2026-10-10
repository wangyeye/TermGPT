Configuration backup and restore are available in Settings. Export bookmarks, folders, notes, commands, saved chats, preferences and window layout. Restore previews the backup, saves a local recovery copy first, and keeps current connections open. Imported window layout applies at the next launch.

Manual exports can include saved passwords and API keys with password encryption (AES-256-GCM, PBKDF2-HMAC-SHA256, 310,000 iterations). ChatGPT account tokens and SSH private key file contents are never exported. Default exports omit credentials.

Choose an iCloud Drive folder for automatic backups. macOS handles cloud synchronization; TermGPT reports successful local writes. Each Mac retains up to 30 daily automatic snapshots. Manual backups are not automatically deleted. Automatic backups omit saved credentials; text in notes, commands and saved chats is copied as written. This is backup and restore, not live configuration synchronization between Macs.

Validation: 82 tests, zero failures, one optional environment-dependent skip. Encryption tests cover wrong or missing passwords, damaged files, unsupported formats and credential exclusion. ARM and Intel packages are ad-hoc signed, not notarized; physical Intel testing remains pending. Personal configuration and credentials are excluded from release assets.

Actual macOS GUI validation: exported and restored configuration with identical fingerprints, created restricted-permission recovery copies, selected an iCloud Drive folder, enabled automatic backup, verified a configuration save updated the daily snapshot, and created a separate manual snapshot. Restart preserved the folder and automatic setting and successfully wrote another snapshot. Backup files were verified as readable, private-permission files without a credential store. Cloud upload completion was not independently verified.

---

设置中新增配置备份与恢复，包含书签、文件夹、笔记、常用命令、已保存聊天、设置与窗口布局。恢复前显示摘要并保存本机副本，可回退；现有连接保持打开，导入的窗口布局在下次启动应用。

手动导出可选择携带保存的密码和 API Key，必须设置备份密码加密。使用 AES-256-GCM 与 PBKDF2-HMAC-SHA256（310,000 次）；默认不包含凭据，ChatGPT 登录 Token 和 SSH 私钥文件内容永不导出。

选择 iCloud Drive 文件夹即可开启自动备份，由 macOS 同步到云端；应用仅报告本机写入成功。每台 Mac 最多保留 30 个每日自动快照，手动备份不会自动删除。自动备份不包含保存的凭据，笔记、命令及聊天中的文字原样备份。此功能提供备份与恢复，不会实时同步多台 Mac 的配置。

验证：82 项测试通过，1 项按环境条件跳过。覆盖错误或缺失密码、损坏文件、不支持的格式及凭据排除。ARM / Intel 安装包已临时签名，尚未公证，Intel 真机验证待完成。发行包不包含个人配置与凭据。

macOS 实际点击验证：导出并恢复配置，校验摘要完全一致；生成限制权限的恢复前副本；选择 iCloud Drive 文件夹并启用自动备份，保存设置后当天快照更新，立即备份另存独立文件。重启后文件夹与自动开关保留，仍能成功写入快照。备份文件可读、权限受限，且不含凭据库。未独立验证云端上传完成。
