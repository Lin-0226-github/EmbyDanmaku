# EmbyDanmaku · 带弹幕的 Emby iOS 播放器

一个用 **Swift + SwiftUI** 写的 iOS Emby 客户端，界面与交互参考 VidHub / EPlayerX：媒体库海报墙、续播、搜索、
全屏播放器手势控制、**弹幕渲染与发送**、**定时关闭**。

- **最低系统：iOS 15.0**（已在 API 层面全面适配 iOS 15，可装在 iOS 15.5 的 iPhone XS ~ iPhone 12 上）
- **不需要任何电脑**：全程 iPhone 操作——网页上传代码 → GitHub Actions 云端编译 → Safari 下载 IPA → TrollStore 一键永久安装
- **自带应用图标**（深蓝影院渐变 + 播放键 + 弹幕条），开箱即用

> Xcode 只跑在 macOS 上，所以「没有电脑」的做法是：把编译丢给 GitHub 的云服务器，
> 把安装交给手机上的 TrollStore / 签名工具。本仓库把这两段链路都配好了。

---

## 一、功能清单

### 播放器
| 功能 | 说明 |
| --- | --- |
| 直连 / 转码自适应 | 先尝试直连原画质；遇到 MKV、DTS、PGS 图形字幕等 AVPlayer 不支持的组合，自动改用服务器 HLS 转码 |
| 倍速 | 0.5x ~ 3.0x，长按播放器可临时 3 倍速 |
| 音轨 / 字幕切换 | 支持内嵌轨、HLS 轨，以及服务器提取出的外挂字幕（客户端自渲染 SRT / VTT / ASS） |
| 字幕样式 | 字号 14–36 可调，居中显示，带半透明底色 |
| 选集 | 剧集列表一键切集，当前集高亮 |
| 自动连播 | 播完自动进入下一集，可关闭 |
| 续播 | 启动时自动跳回上次进度（距结尾 15 秒内视为看完） |
| 进度上报 | 向 Emby 上报开始 / 进度 / 停止，多设备续播同步 |
| 手势 | 左半屏上下滑调亮度、右半屏调音量、水平滑快进快退（整屏约 90 秒）、单击显隐控制层、双击播放暂停 |
| 画面 | 适应 / 填充切换 |
| 锁屏控制 | 支持锁屏与耳机的播放、暂停、上/下一集、拖动进度，并显示海报 |
| 后台播放 | 设置中可开关（Info.plist 已声明 audio 后台模式） |

### 弹幕
| 功能 | 说明 |
| --- | --- |
| 弹幕源 | **弹弹play 开放弹幕网络**（自动匹配 + 手动搜索），同时支持**导入本地 XML / JSON 弹幕** |
| 匹配方式 | 播放时按文件名自动搜索弹幕库；匹配结果会缓存，下次直接拉取 |
| 手动匹配 | 搜索番剧名 → 展开分集 → 选择对应弹幕库；可解除绑定 |
| 时间校准 | −30s ~ +30s 整体偏移，0.5 秒步进微调 |
| 样式 | 开关、透明度、字号、速度、显示区域（1/4、1/2、3/4、全屏）、同屏上限、描边、按类型过滤 |
| 屏蔽 | 关键词过滤（逗号分隔） |
| 发送 | 播放器内直接发弹幕，本机立即上屏并标黄框；若已绑定弹幕库且应用有权限，同时提交到服务器 |
| 渲染 | UIKit + CADisplayLink + 视图复用池，轨道防重叠调度，60fps，不占用 SwiftUI 刷新 |

### 定时关闭
- 预设 10 / 15 / 30 / 45 / 60 / 90 / 120 分钟
- 自定义 1–180 分钟
- **播完本集后停止**
- 倒计时实时显示在控制条上，可随时取消；触发后自动暂停并弹提示

### 媒体库
- 服务器管理（增删改）、用户名密码登录、已保存用户快捷选择、令牌存钥匙串、启动自动恢复会话
- 首页：继续观看（带进度条）、最近加入、媒体库入口
- 媒体库网格、搜索（输入防抖 0.4 秒）
- 详情页：背景图、海报、元信息、简介、演职人员、已看 / 收藏切换；剧集按季浏览

---

## 二、目录结构

```
EmbyDanmaku/
├── EmbyDanmaku.xcodeproj/      # Xcode 工程（可直接打开）
├── project.yml                 # XcodeGen 配置（增删文件后重新生成工程用）
├── Resources/
│   ├── Info.plist
│   └── Assets.xcassets/        # AppIcon（应用图标）
└── Sources/
    ├── App/
    │   ├── EmbyDanmakuApp.swift        入口
    │   └── AppState.swift              服务器列表、登录会话、令牌持久化
    ├── Core/
    │   ├── Emby/  EmbyModels / EmbyClient / EmbyPlayback（播放信息协商 + 进度上报）
    │   ├── Danmaku/ DanmakuItem / DanmakuEngine（轨道调度）/ DanmakuCanvasView（渲染）
    │   │            DanmakuAPI（弹弹play 签名请求）/ DanmakuParser / DanmakuManager
    │   ├── Player/ PlayerViewModel / PlaybackDecision（直连↔转码决策）
    │   │           SubtitleParser（SRT/VTT/ASS）/ SleepTimer
    │   └── Storage/ AppSettings / Keychain / LocalStore
    └── Views/
        ├── Server/   ServerListView / LoginView
        ├── Library/  HomeView / ItemDetailView / SearchView
        ├── Player/   PlayerView / PlayerControls / PlayerPanels
        ├── Settings/ SettingsView
        └── Components/ PosterCard / LabeledRow（iOS 15 上的 LabeledContent 替身）
```

---

## 三、打包与安装（重点：全程只用手机，不需要电脑）

整体链路：**手机里的终端 App 推送代码 → GitHub 云端编译 → Safari 下载 IPA → 手机上安装**。

### 第 1 步 · 在 GitHub 上建空仓库（Safari）

1. Safari 打开 [github.com](https://github.com)，注册 / 登录
2. 右上角 **+** → **New repository** → 名字填 `EmbyDanmaku` → 选 **Public**
3. **不要**勾选 Add a README file，保持空仓库 → **Create repository**

> 这一步只要能打开 github.com 就行，不需要用 Codespaces / 网页终端。

### 第 2 步 · 用手机里的终端 App 推送代码

> iOS 的「文件」App **不显示点开头的目录**（`.github` 会凭空消失），Safari 上传又**不支持文件夹**。
> 所以用带 Python / git 的终端 App + 项目自带脚本，目录结构和隐藏文件都会自动补齐。
> 脚本有两个：`upload.py`（走 GitHub API，**不需要 git**，推荐）和 `setup.sh`（走 git，备选）。

**方式 1：a-Shell + upload.py（推荐，不需要 git）**

a-Shell 自带完整的 Python 3，**不需要 git、不需要网页终端、也不需要先在网页上建仓库**，
一个脚本全搞定（它直接调 GitHub 的 API 上传）。

先拿令牌（只用一次）：Safari 打开 `https://github.com/settings/tokens`
→ **Generate new token (classic)** → 勾选 **repo** → 生成后复制保存（见第 3 步）。

a-Shell 里只敲两条命令：

```sh
pickFolder            # 弹出选择器 → 选中解压出来的 EmbyDanmaku 文件夹本身 → 打开
python3 upload.py     # 按提示粘贴令牌，其余全自动
```

`upload.py` 会自动：补回被 iOS 隐藏的 `.github/workflows/build-ipa.yml`
→ 校验令牌 → **创建 EmbyDanmaku 仓库**（已存在则直接整仓更新）→ 上传全部 50 多个文件（一个提交）
→ 打印 Actions 页面地址。

> **常用对照**
> - 手里只有 zip 还没解压：不用回「文件」App，直接在终端里解：
>   ```sh
>   python3 -c "import zipfile; zipfile.ZipFile('EmbyDanmaku.zip').extractall('EmbyDanmaku')"
>   cd EmbyDanmaku
>   ```
> - 上传到一半断了 / 想更新代码：原样再跑一次 `python3 upload.py`，会整仓覆盖
> - 粘贴令牌时屏幕**不显示任何字符**（不是卡住），粘贴后回车
> - 提示「创建仓库返回 403」：先去 GitHub 网页验证邮箱，或确认用的是 classic 令牌
> - 以后想回到这个目录：`showmarks` 看书签，`jump 书签名` 跳转

**方式 2：a-Shell + git（备选）**

如果你的 a-Shell 能装上 git（你这版目前装不上，会提示 Package git not found）：

```sh
pickFolder                                  # 选 EmbyDanmaku 文件夹本身
rm -rf ~/Documents/EmbyDanmaku
cp -R . ~/Documents/EmbyDanmaku && cd ~/Documents/EmbyDanmaku
git --version || pkg install git            # 装不上就回到方式 1
sh setup.sh                                 # 按提示输入用户名 + 令牌
```

**方式 3：iSH（再备选）**

iSH 要联网装 git，境外软件源有时会失败：

```sh
apk update && apk add git
mkdir -p /mnt/edm && mount -t ios null /mnt/edm     # 弹出选择器，选 EmbyDanmaku 文件夹
cp -r /mnt/edm/EmbyDanmaku ~/EmbyDanmaku && cd ~/EmbyDanmaku
sh setup.sh
```

### 第 3 步 · 生成 GitHub 令牌（只用一次）

Safari 打开 `https://github.com/settings/tokens` → **Generate new token (classic)**
→ 勾选 **repo** → 生成后**复制保存**（关掉页面就再也看不见了）。
脚本问你要「令牌 / 密码」时粘贴它，而不是你的登录密码。

> 提示：终端里粘贴/输入密码时屏幕**不会显示任何字符**（不是卡住了），粘贴后直接回车即可。
>
> 复制令牌的小技巧：先在备忘录里粘贴一次保存，再从备忘录复制，
> 这样在终端长按粘贴时不会因为来回切 App 被清空。

### 第 4 步 · 云端编译 IPA

1. 仓库页面 → **Actions** 标签（首次会提示启用，点允许）
2. 左侧选 **Build iOS IPA** → 右侧 **Run workflow** → 签名方式保持 `unsigned` → 确认
3. 等 5～10 分钟，出现绿色对勾即构建成功

### 第 5 步 · 用 Safari 下载 IPA

构建完成后，工作流会自动把 IPA 发布到仓库的 **Releases**（标签 `latest-ipa`）：

- 地址：`https://github.com/<你的用户名>/EmbyDanmaku/releases/tag/latest-ipa`
- 点 **EmbyDanmaku-unsigned.ipa** 直接下载（**无需登录 GitHub**），
  文件会出现在「文件」App 的「下载」文件夹里

> Actions 运行详情页底部的 **Artifacts** 也能下载，但需要登录 GitHub，手机上不如 Releases 方便。

### 第 6 步 · 安装到手机（两条路线，选一条）

**路线 A：TrollStore（强烈推荐，你的 iOS 15.5 正好在支持范围）**

TrollStore 适用 **iOS 14.0 ~ 16.6.1**，装好后用它安装的 App **永久有效、不会 7 天掉签**：

1. Safari 搜索「巨魔 TrollStore 在线安装」，找一个当前可用的社区页面，
   下载并安装 **TrollInstallerX / 巨魔安装器**（这类站点会随证书变动，失效就换一家）
2. **设置 → 通用 → VPN 与设备管理** → 信任对应的企业证书
3. 打开巨魔安装器 → 按提示安装 **TrollStore**（部分机型要选一个系统 App 做替换，按页面默认走）
4. 首次打开 TrollStore 会自动准备环境
5. 「文件」App 里找到 `EmbyDanmaku-unsigned.ipa` → **分享 → TrollStore** → 确认安装
6. 桌面出现「弹幕影院」，点开即用，永久有效

**路线 B：手机端签名工具（不想装 TrollStore 时用）**

Feather（开源）、Ksign、Scarlet 等工具可以直接在手机上给 IPA 签名并安装：

1. Safari 安装 Feather（GitHub 搜 `khcrysalis/Feather`）或同类工具，信任其企业证书
2. 按工具提示导入证书（共享证书开箱即用，但**随时可能被 Apple 吊销**；
   免费 Apple ID 个人证书 7 天有效、最多 3 个 App）
3. 导入 `EmbyDanmaku-unsigned.ipa` → 签名 → 安装 → 到设置里信任开发者

### 以后更新了怎么办

代码有更新 → 重跑一次 **Build iOS IPA** → Releases 下载新 IPA → TrollStore 里再装一次
（覆盖安装，播放进度、弹幕绑定、设置等数据都会保留）。

> 提示：换新版本的文件时，建议**删掉手机上整个 EmbyDanmaku 文件夹、用新 zip 整个重新解压**，
> 只替换单个文件容易漏（iOS「文件」App 里多层文件夹很容易点错层）。
> v10 起脚本上传后会自动把仓库和手机逐文件比对 SHA，发现不一致会列出来并拒绝触发构建。

### 方案 C：有电脑时（可选）

- Mac + Xcode 15+：双击 `EmbyDanmaku.xcodeproj`，配置签名后 ⌘R 跑真机
- Windows：用 [Sideloadly](https://sideloadly.io/) + 免费 Apple ID 安装（7 天有效）

---

**关于 HTTP**：Info.plist 里设置了 `NSAllowsArbitraryLoads`，因为局域网 Emby 多为 `http://IP:8096`。
你的服务器既然是公网 HTTPS，可以把这项收紧成 `NSAllowsLocalNetworking`，更安全。

**关于增删文件**：新增/删除 Swift 文件后，装了 XcodeGen 就在项目根目录跑 `xcodegen` 重新生成工程；
否则在 Xcode 里手动增删文件引用即可。

```bash
brew install xcodegen && cd EmbyDanmaku && xcodegen
```

---

## 四、配置 Emby 服务器

App 内「添加服务器」填入地址即可，例如：

```
http://192.168.1.10:8096
https://emby.example.com
```

然后用 Emby 的用户名 + 密码登录（密码保存在系统钥匙串）。

### 播放策略说明

客户端会把自己能解码的格式告诉服务器（见 `DeviceProfile.iOS`）：

- **可直连**：容器 `mp4 / m4v / mov`，视频 `H.264 / HEVC / AV1`，音频 `AAC / MP3 / AC-3 / E-AC-3 / ALAC / FLAC`
- **不直连**：`mkv`、`DTS`、`TrueHD`、`PGS` 图形字幕等 → 自动走服务器 HLS 转码

「设置 → 播放 → 优先直连播放」可以强制始终转码（网络差时更稳）。
「转码码率上限」对应弱网场景，默认 60 Mbps。

> 想让服务器少转码：在 Emby 后台把媒体转成 MP4（H.264 + AAC）是最省事的做法。

---

## 五、配置弹幕

### 方式 A：弹弹play 开放弹幕网络（推荐）

1. 访问 [弹弹play 开发者中心](https://www.dandanplay.com/open.html) 注册账号、创建应用，拿到 **AppId** 和 **AppSecret**。
2. App 内「设置 → 弹幕 → 弹幕服务」填入：
   - 弹幕 API 地址：`https://api.dandanplay.net`（默认已填好）
   - AppId / AppSecret
3. 播放时会自动按文件名搜索并匹配弹幕库。匹配不准时，播放器内「弹幕面板 → 搜索弹幕库」手动选择，选择结果会被记住。

> 不填凭证也能使用兼容弹弹play v2 规范的第三方服务；把「弹幕 API 地址」改成你的自建服务即可
> （例如社区常见的 `danmu_api` 项目，覆盖爱优腾芒哔等平台）。

### 方式 B：本地弹幕文件

播放器内「弹幕面板 → 导入弹幕文件」，支持：

- **XML**：B 站格式 `<d p="时间,模式,字号,颜色,时间戳,池,用户Hash,ID">文本</d>`，以及弹弹play 桌面端的 `<VisualDmItem>` 格式
- **JSON**：`{"comments":[{"p":"...","m":"..."}]}` 或 `[{"time":1.2,"text":"...","color":"#FFFFFF","mode":1}]`

导入后文件会被复制到 App 的 Application Support 目录，之后可在列表中直接切换。

---

## 六、常见问题

**Q：github.com 打不开 / 特别慢？**
A：这是国内网络的常见情况，和项目本身无关。可以试试：
换 Wi-Fi 或改用手机流量；换个时间段（凌晨最快）；用支持代理的浏览器 / 开 VPN 后再试。
只要第 1 步的建仓库、第 4 步的 Actions 页面能打开，整条链路就能跑通。

**Q：Safari 能不能直接上传文件夹？**
A：**不能**，这正是 iOS 的限制：网页上传点选的文件会被平铺到仓库根目录，
而 iOS「文件」App 又隐藏了 `.github` 这类点开头的目录。
所以请走第 2 步的终端 App 路线，`setup.sh` 会替你把目录结构补回来。

**Q：a-Shell 里提示 `git: command not found` / `Package git not found`？**
A：不用装 git，直接跑 `python3 upload.py`（a-Shell 自带 Python，走 GitHub API 上传，
   连建仓库都自动）。这也是本项目的推荐方式。

**Q：仓库里没有 `.github` 文件夹 / Actions 里没有工作流？**
A：往 `.github` 目录写文件需要令牌有 **workflow** 权限，只勾 `repo` 会被 GitHub 拒收，
   所以其他文件都传上去了、唯独工作流文件没传上。
   解决（令牌字符串不变，不用重新生成）：Safari 打开 <https://github.com/settings/tokens>
   → 点你的令牌 → 勾选 **workflow** → 拉到底点 **Update token** → 重跑 upload.py 即可补传。
   实在不行就纯网页手动建：仓库页面点 **+** → Create new file → 路径填
   `.github/workflows/build-ipa.yml`，内容从仓库里的 `github-workflow.txt` 复制 → Commit。

**Q：重跑时满屏 `（HTTP 409）"sha" wasn't supplied` / `（HTTP 422）Invalid request`？**
A：先别慌——**409 恰恰说明文件已经全部在仓库里了**（只有已存在的文件才会要求带 sha）。
   Safari 打开 `github.com/你的用户名/EmbyDanmaku` 看一眼，文件都在的话就直接去 Actions 触发构建。
   v6 版脚本会自动识别「仓库里已有相同内容」并跳过覆盖，不会再生这些报错；
   上传完成后还会**自动触发云端构建**，不用再去 Actions 页面手动点。

**Q：文件都传完了，最后报 `× 建树失败（HTTP 404）：Not Found`？**
A：这是 Git Data API「建树」接口偶发/持续返回 404（仓库刚初始化时容易出现）。
   v5 版脚本遇到它会先重试 3 次，仍失败就**自动切换逐文件上传**
   （Contents API，每个文件一个提交，慢约 2 分钟但必成）。
   看到开头打印 `upload.py v5` 即已包含此修复。

**Q：上传时报 `409 Git Repository is empty`？**
A：GitHub 的规定：一个提交都没有的全新仓库，不能直接用 Git 数据接口写文件。
   v4 版脚本会先自动放一个「种子提交」（用 README.md 初始化分支）再继续上传，
   看到开头打印 `upload.py v4` 即已包含此修复，重跑一遍即可，不用删仓库重建。

**Q：粘贴令牌按回车之后一直没反应？**
A：旧版本用了 Python 的「密码隐藏输入」（getpass），a-Shell 的终端不支持，会卡死在那里。
   新版（开头打印 `upload.py v3`）已改成普通输入，不会再卡。
   更省事的办法是绕开输入，直接把令牌存成文件再跑：
   ```
   echo ghp_你的令牌 > token.txt
   python3 upload.py
   ```
   脚本会自动读 token.txt，上传成功后自动删除它；token.txt 也永远不会被上传到 GitHub。

**Q：跑 upload.py 报 `SSL: CERTIFICATE_VERIFY_FAILED` / `self-signed certificate in certificate chain`？**
A：**不是令牌的问题**，是你手机到 GitHub 之间有个「中间人」在解密 HTTPS：
   代理 App 开了 MITM / TLS 解密、公司或校园网的上网审计、某些免费 VPN。
   脚本已经会自动跳过证书校验并继续上传（会打印一句提示），一般不用管。
   想根治的话：
   1. 关掉代理 App 的「HTTPS 解密 / MITM / 证书嗅探」开关；
   2. 或干脆断开代理和 VPN，改用手机流量重跑；
   3. 或开飞行模式等 5 秒再关掉，让网络重连。

**Q：报 `401 Bad credentials` 怎么办？**
A：三种可能：令牌过期 / 被删了；生成时没勾选 `repo`；粘贴时缺头少尾（`ghp_` 开头，通常 40 位）。
   去 <https://github.com/settings/tokens> 删旧的、重开一个（勾选 `repo`），整个复制过来。
   ⚠️ 令牌等同于密码，**不要截图发给别人、不要发到群里**，看到泄漏就立刻删掉重开。

**Q：令牌被我不小心暴露了（截图 / 聊天记录）？**
A：立刻打开 <https://github.com/settings/tokens> → Delete 掉它，再生成一个。
   GitHub 令牌只对勾选项有权限，删掉即刻失效，风险就止住了。

**Q：播放失败 / 一直转圈？**
A：优先检查服务器地址与网络。若提示转码失败，确认 Emby 的 FFmpeg 路径配置正确；
可在「设置 → 播放」里把「转码码率上限」调低，或打开「优先直连播放」。

**Q：没有字幕？**
A：外挂字幕需要服务器能提取（Emby 的 `/Videos/{id}/{mediaSourceId}/Subtitles/{index}/Stream.*` 端点）。
如果是 MKV 内嵌的 ASS 特效字幕，客户端会做纯文本渲染（特效不还原）；PGS 图形字幕只能靠服务器转码烧录。

**Q：弹幕匹配不到？**
A：弹弹play 的库以番剧为主，影视剧覆盖率有限。可在弹幕面板手动搜索；或者用文件名更规范的资源
（如 `剧名.S01E01.1080p.WEB-DL`）。匹配关键词会自动剔除分辨率、编码组等噪声。

**Q：弹幕时间对不上？**
A：用弹幕面板的「时间校准」滑动条调整，偏移会被按视频记住。

**Q：能投屏吗？**
A：当前版本未做 DLNA / AirPlay 投屏 UI。AVPlayer 原生支持 AirPlay，可自行在控制层加 `AVRoutePickerView`。

---

## 七、已知限制

- 播放内核为 AVPlayer，不支持的格式依赖 Emby 服务端转码（未集成 FFmpeg 软解内核）
- 未实现 DLNA / Chromecast 投屏、离线下载
- 弹幕发送接口依赖弹弹play 的应用授权额度，未授权时只在本机显示、不会提交到服务器
- ASS 字幕的高级特效（卡拉 OK、定位、动画）不还原

## 八、许可与合规

项目源码可自由使用。若以弹弹play 作为主要弹幕来源，请遵守其
[使用约定](https://doc.dandanplay.com/open/)：不得将弹幕功能作为卖点收费、不得批量抓取弹幕数据。
