# SummerDream-Text-Extractor-
一个用于提取 Ren'Py 游戏《夏梦》剧情文本的简单工具。

本项目不会提供或分发《夏梦》的原始剧情脚本、图片、音频等游戏资源，仅提供用于本地整理剧情文本的提取脚本。

## 功能

运行后会从《夏梦》的剧情 `.rpy` 文件中整理出更适合直接阅读的文本，并生成：

- `夏梦_完整剧情原文.txt`
- `夏梦_关键争议原文.txt`

完整剧情版会尽量保留游戏中的对白、旁白和实际显示文本，同时移除 Ren'Py 的立绘、音乐、转场、变量赋值等程序指令。

争议文本版会整理涉及性别议题、男性向游戏文化、后宫/纯爱、DEI、日本/东瀛设定、民族与文化讨论、媒体与舆论等内容，并尽量保留完整上下文，方便人工阅读和核查。

## 使用方法

### 1. 准备游戏剧情文件

你需要自行合法取得《夏梦》。地址：https://store.steampowered.com/app/5204330/_/

本工具默认用于游戏目录中的：

```
SummerDream/
└─ game/
   └─ story_script/
       └─ story_script.rar/
          ├─ chapter_0.rpy
          ├─ chapter_1.rpy
          ├─ ...
          └─ chapter_9.rpy
```
使用前，需要自行解压。

### 2. 放入工具
将：
Build-StoryText.ps1
运行剧情提取.cmd

放到与 chapter_0.rpy ～ chapter_9.rpy 相同的目录。
例如：
extracted_story_script/
├─ chapter_0.rpy
├─ chapter_1.rpy
├─ ...
├─ chapter_9.rpy
├─ Build-StoryText.ps1
└─ 运行剧情提取.cmd

### 3. 运行
直接双击：
**运行剧情提取.cmd**
即可。

启动器会调用 Windows PowerShell，并仅对本次运行使用：
-ExecutionPolicy Bypass

不会永久修改系统的 PowerShell 执行策略。
处理完成后，两份 TXT 会输出到桌面。

## 安全说明

本工具只进行本地文本读取和文本文件生成。

它不会：
- 启动《夏梦》游戏
- 执行游戏目录中的 .exe
- 执行 .rpy 剧情脚本
- 修改原始剧情文件
- 上传任何游戏文件
- 连接网络
- 删除游戏文件
- 
Build-StoryText.ps1 可以直接使用文本编辑器检查。
## 系统要求

主要测试环境：
Windows 11
Windows PowerShell 5.1

PowerShell 脚本使用 UTF-8 with BOM 保存，以兼容 Windows PowerShell 5.1 对中文文本的读取。

## 关于剧情文本

本仓库不会提供：
chapter_0.rpy ~ chapter_9.rpy
story_script.rar
完整游戏剧情 TXT
游戏图片、音乐及其他资源

这些内容属于原游戏及其权利人的作品。
本项目只提供用于从用户自己拥有的游戏副本中进行本地文本整理的工具。

## 免责声明

本项目是非官方第三方工具，与《夏梦》的开发者、发行者及 Ren'Py 项目无任何隶属或合作关系。
本工具的目的仅为文本整理、研究和评论便利。
《夏梦》的剧情、美术、音乐及其他原始游戏内容的版权归其各自权利人所有。
## License

本仓库中由本项目提供的提取脚本和启动脚本采用 MIT License。
MIT License 仅适用于本项目自行编写的工具代码，不适用于《夏梦》的剧情、美术、音乐或其他游戏内容。
