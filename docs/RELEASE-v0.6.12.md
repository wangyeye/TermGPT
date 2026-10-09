TermGPT v0.6.12 adds terminal search, a local command library and workspace restoration.

- Command-F searches the terminal scrollback and highlights the selected match, with case-sensitive and regex modes, previous/next and refresh. Searches physical rows with up to 10,000 matches.
- Terminal → Command Library (Command-Shift-K) supports name, folder, command, notes, search, editing, deletion, copy and single-line insertion without execution. AI shell cards can be saved to the library.
- Workspace restoration defaults on and is configurable in Settings. Restores tab order, selected tab and saved layout. Tabs connect only when requested; terminal output and running sessions are not restored. Deleted bookmarks are skipped.

70 tests passed, including Unicode selection, scrollback search and persistence; one optional test skipped. Mac was locked during UI validation, so actual click verification remains pending. ARM/Intel packages are ad-hoc signed, not notarized; physical Intel testing is pending. Personal configuration, credentials and logs are excluded. Saved commands remain local plain text; avoid storing passwords.

---

新增终端搜索、常用命令库和工作区恢复。

- ⌘F 搜索终端历史并定位、高亮当前匹配，支持大小写、正则、上下切换和刷新；按物理行匹配，最多一万条。
- 终端 → 常用命令库（⌘⇧K）支持名称、文件夹、命令、备注、搜索、编辑、删除、复制和单行填入，不自动执行；AI 命令卡可收藏。
- 工作区恢复默认开启，可在设置关闭；恢复标签顺序、选中标签和已有布局，点击后才连接。不恢复终端输出和运行会话，已删除书签跳过。

70 项测试无失败，包含中文选区、历史搜索和配置持久化；一项可选测试跳过。Mac 验证时锁屏，实际点击验证待完成。ARM/Intel 临时签名、尚未公证，未进行 Intel 真机验证。不包含个人配置、密码或日志。常用命令以明文本地保存，请勿写入密码。
