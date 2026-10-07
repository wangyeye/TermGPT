# TermGPT 图标

由内置 imagegen 生成；源文件 AppIcon.png，打包文件 TermGPT.icns 在本机构建时生成，不随开源源码提交。
设计提示：macOS 应用图标，深蓝玻璃圆角方形，白色终端 > 与下划线，薄荷色四角 AI 星光，透明边缘，无文字或 OpenAI 标志。

在项目目录执行 `./scripts/make-icon.sh`。脚本检查 macOS、sips、iconutil，生成标准 16–1024 像素 iconset 并转换 icns。然后 `./scripts/build.sh` 将图标写入应用资源和 Info.plist。
