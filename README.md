<div align="center">

# 禁漫姬 HarmonyOS (jinmanji-harmony)

**第三方禁漫天堂(18comic) HarmonyOS 原生客户端**

复刻自 Android 版 [jinmanji-app](../jinmanji-app/) · ArkTS / ArkUI · API 26 (HarmonyOS 26.0.0) · 零第三方依赖

</div>

> 本项目是 Android 原应用 `jinmanji-app/`（Kotlin + Jetpack Compose）向 HarmonyOS 的**原生复刻**：
> UI 用 ArkTS/ArkUI 重写，网络/解码/存储层按原实现逐行移植（API 加密封信、图片反混淆、域名池、下载队列均为等价重写，非 WebView 套壳）。
> 复刻范围以 `docs/feature-spec.md` 的 187 条功能项为准，按 **M（必保 110）/ S（简化 40）/ O（裁剪 37）** 三级划定边界——下文矩阵如实标注每一项的落地状态。

## ✨ 功能亮点

- 🧭 **四大 Tab + 路由页**：发现 / 分类 / 书架 / 我的（底部毛玻璃光感栏）；搜索、详情、阅读器、下载管理为路由页
- 🔍 **搜索**：关键词 + JM 编号直达 + 搜索历史；服务端排序（最新/观看/图片/爱心）与时间筛选（今日/本周/本月/指定年月）；语言多选与自定义筛选词（客户端过滤 + 自动连扫补足）；剪贴板 JM 编号自动填充
- 📖 **阅读**：条漫纵向 + 横向翻页双模式、三分点按热区、上下 HUD（目录/模式/亮度/预加载设置）、进度滑条、精确到页的续读、前后 5 页恒预加载；**原尺寸反混淆解码**（先解密再缩放，无横线瑕疵）忠实移植 `JmImageDecoder.kt`；双指缩放 1x~5x + 边界回弹
- 📥 **下载**：线性队列 + 五态状态机 + 页缓存复用，导出 **CBZ**（手写最小 ZIP 写入器：STORE 不压缩 + 自实现 CRC32，零第三方依赖）；已完成任务支持「打开文件 / 保存到用户所选位置」
- 📚 **书架**：收藏 / 历史 / 下载三段合一，续读横幅一键回到上次进度（精确到 第N话 P.x）
- 🌐 **镜像网络**：API 域名池（内置兜底 + 分发服务器刷新 + 失败隔离 5 分钟 + 18s 总预算）、图片 CDN 按 seed 分流（Java hashCode 手写等价）与轮换；设置页手动切换镜像 + 一键测速
- 🎨 **外观**：品牌粉 `#FF4D6D` 视觉体系；主题三态（跟随系统/浅色/深色）即选即生效；阅读器亮度遮罩 + 黑/米黄背景

## 📊 功能覆盖矩阵（原功能 → 鸿蒙版状态）

状态图例：✅ 完整复刻（M 级落地） · 🟡 简化（S 级，注明简化点） · ❌ 裁剪（O 级，不移植）

### 全局与导航

| 原功能 | 状态 | 鸿蒙版说明 |
| --- | --- | --- |
| 底部多 Tab 导航 + 全局沉浸式 | ✅ | 四 Tab 光感毛玻璃底栏（原版五 Tab，搜索并入发现页顶栏） |
| 二级页路由与返回 | ✅ | Navigation 栈；非发现 Tab 系统返回先回发现 Tab |
| 全局错误兜底 + crash 日志 | ✅ | 未捕获异常写 `filesDir/crash/` 日志并弹友好错误页（原版独立进程崩溃页见裁剪表） |
| 标签词云 / TagStats 词频 | ❌ | 收藏标签 chips + 自定义分类已覆盖同类入口 |

### 发现首页

| 原功能 | 状态 | 鸿蒙版说明 |
| --- | --- | --- |
| 热门榜单（横滑 + 前三名金银铜角标） | ✅ | 日/周/月/总四段切换（原版仅总榜横滑） |
| 随机推荐 + 换一批 | ✅ | 本地洗牌 + 交错淡入；失败保留旧内容 |
| 最新更新 3 列网格 + 分页 | ✅ | 上拉加载更多（原 PageBar 跳页弹窗简化为页码指示） |
| 首页缓存秒开（失败保留旧内容） | ✅ | 缓存优先展示 → 网络刷新替换 |
| 屏蔽标签过滤 | 🟡 | 标题/作者/分类字段匹配；后台拉真实标签校准裁剪；增删后下次刷新生效（非实时推送） |
| 语言/全彩徽章 | 🟡 | 标题/作者关键词启发式判定（原版标签级校准裁剪）；详情页加载后用真实 tags 校准 |
| 封面错峰预取器 | 🟡 | 依赖系统 Image 自带缓存 + `cachedCount`，不自研预取 |
| 分类速览快捷胶囊 | ❌ | 与分类 Tab 职能重复 |

### 分类与搜索

| 原功能 | 状态 | 鸿蒙版说明 |
| --- | --- | --- |
| 分类列表 + 分类详情（排序 chips + 网格 + 分页） | ✅ | 日/周/月/总/最新五档排序；瀑布流 3 列 |
| 自定义分类/tag | ✅ | 添加（≤16 字符查重）/点击搜索/删除确认，JSON 持久化 |
| 搜索：关键词 + JM 编号直达 | ✅ | 正则与原版一致；纯编号提交同样直达 |
| 排序 / 时间 / 指定年月筛选 | ✅ | 服务端参数；筛选抽屉（bindSheet）内即选即重搜 |
| 语言多选 + 全彩 + 自定义筛选词 | ✅ | 客户端过滤 + 自动连扫补足（单次上限 8 页，显示「已扫 N 页 · 筛后 M 条」） |
| 搜索历史 | ✅ | 点击即搜 / 单删 / 清空确认（上限 50） |
| 搜索状态保留 / 超时重试 | ✅ | 返回不重搜；失败「⚠ 点此重试」横幅 + 旧结果保留 |
| 剪贴板 JM 编号识别 | 🟡 | 进搜索页自动填充输入框（不做弹窗） |
| 热门搜索榜 | 🟡 | 无官方 API，以分类名作词源点击执行真实搜索，不伪造趋势数据 |
| 搜索历史长按多选批量删除 | ❌ | 点击/单删/清空已可用，多选批量未实现（可后补） |

### 详情与评论

| 原功能 | 状态 | 鸿蒙版说明 |
| --- | --- | --- |
| 详情头部 + 元数据（复制 JM 号/官方链接/作者点搜） | ✅ | 折叠视差头（封面 blur + 渐显书名顶栏） |
| CTA：开始阅读/续读 + 收藏/下载/评论 | ✅ | 主 CTA 显示「续读 · 第N话 P.x」；下载状态行实时反馈 |
| 章节列表 + 正倒序切换 | ✅ | 已读置灰 + 「上次读到 P.x」胶囊 |
| 内容预览墙 | ✅ | 前 8 页胶片条 + 全量页 bindSheet；点任意页直达该页 |
| 评论（翻页/剧透遮罩/时间格式化） | ✅ | bindSheet 半模态抽屉（原为整页）；「热门/最新」分段中热门为本地点赞降序（接口无排序参数）；只读 |
| 详情缓存秒开 + 断网可看 | ✅ | AlbumCache 优先 → 网络刷新 → 失败保留 |
| 连载中/已完结标识 | ❌ | API 无状态字段，不造假数据 |

### 阅读器

| 原功能 | 状态 | 鸿蒙版说明 |
| --- | --- | --- |
| 条漫纵向 / 横向翻页 + 模式记忆 | ✅ | List+LazyForEach / Swiper；四档枚举持久化 |
| 点按热区 / HUD / 进度滑条 | ✅ | 原版无 HUD（常驻顶栏），鸿蒙版为新增：三分热区 + 上下 HUD + Slider 跳页 + 微型页码胶囊 |
| 续读（精确到页的进度保存） | ✅ | 原版不持久化页码；鸿蒙版为**增强新增**：`{aid, chapterId, chapterIndex, page, totalPages}` 落盘，2s 节流写入 |
| 恒预加载后 5 页 + 下一章预载 | ✅ | 受「自动缓存」开关控制 |
| 反混淆解码链路 | ✅ | 分段数 md5（**不带扩展名**文件名）+ 带余数垂直倒序重排 + 先原尺寸解密再缩放；缩略图磁盘缓存 + 512MB/15s 页缓存清理 |
| 单页三态 + 失败重试 | ✅ | 点按重试 + 图片 CDN 轮换 |
| 双指缩放 1x~5x | ✅ | 实时缩放 + 双指平移 + 松手边界回弹 + HUD 重置入口（双击放大简化掉） |
| 日漫右翻 / 双页拼合 | 🟡 | 仅保留枚举与切换，渲染与横向模式相同（不并排拼合） |
| 亮度调节 | 🟡 | 应用内遮罩亮度（10-100）+ 记忆；黑/米黄背景（米黄不持久化） |
| 自动翻页 / 音量键翻页 / 裁白边 | ❌ | 原版亦无，纯构想项 |

### 书架（收藏 + 历史 + 下载）

| 原功能 | 状态 | 鸿蒙版说明 |
| --- | --- | --- |
| 收藏网格 + 排序记忆 + 手动添加（JM 号/#标签） | ✅ | 排序持久化；编号添加走详情接口校验 |
| 收藏标签 chips（点搜索/长按移除） | ✅ | 与详情页长按标签收藏联动 |
| 浏览历史（上限 300 + 排序 + 清空确认 + 开关联动） | ✅ | 卡片显示「读至 第x话 P.y / 共 z 页」（进度展示为增强新增） |
| 历史长按多选批量删除 | ✅ | 全选/取消全选/批量删（批量收藏未做） |
| 续读横幅 | ✅ | 鸿蒙版新增（依赖精确进度），点击直达 |
| 「有更新」红点 | ❌ | 无更新检测 API |

### 下载与离线

| 原功能 | 状态 | 鸿蒙版说明 |
| --- | --- | --- |
| 线性下载队列 + 状态机 + 重启即失败（不续传） | ✅ | 等待/下载中/暂停/完成/失败/取消；任务落盘 600ms 去抖 |
| 页缓存复用 + 换域名重试 | ✅ | 单任务页并发 3（原版 2） |
| CBZ 导出 | ✅ | STORE + 自实现 CRC32 的最小 ZIP；条目为**反混淆后按源格式**（jpg→jpg / webp→webp）；导出逐页进度 |
| 任务管理（暂停/继续/删除/多选批量/删文件） | ✅ | 删除确认含「同时删除原始文件」 |
| 打开文件 / 保存到所选位置 | ✅ | 系统打开方式（viewData + fileUri）+ DocumentViewPicker 保存 |
| 下载格式：PDF / ZIP / 7z(AES-256) / tar.gz 及档位 | ❌ | 只保留 CBZ/ZIP 一种（见裁剪表） |
| 缺失页处理 | 🟡 | 以灰底占位图写入压缩包并计入统计（原版规格为「跳过缺失页」，此处口径不同） |
| 前台通知进度 / 通知点击跳转 | ❌ | 页面内进度条替代（实况窗/通知为 O 级） |

### 设置与数据

| 原功能 | 状态 | 鸿蒙版说明 |
| --- | --- | --- |
| 主题（跟随系统/浅色/深色） | ✅ | 三态选择，`setColorMode` 即选即生效（启动/回前台同步应用） |
| 镜像域名切换 + 一键测速 | ✅ | 鸿蒙版新增 UI（原版为后台自动切换）；结果供首页延迟灯 |
| 屏蔽标签管理 | ✅ | 添加/列表/行内删除 |
| 缓存清理 / 自动缓存 / 浏览历史开关 | ✅ | 清理范围 = cacheDir + 页缓存目录 |
| 数据导出 JSON | ✅ | 结构对齐原版 `DataTransfer`（收藏含标签 + 浏览/搜索历史），写入应用 Export 目录并展示路径 |
| 数据导入（合并式） | 🟡 | 数据层合并接口已备（同 id 去重/保较新），**设置页暂无导入入口** |
| 生物识别应用锁 | 🟡 | userAuth 指纹简版；验证失败/不可用降级为仅保存开关（见已知限制） |
| 预加载页数 / 下载弹窗记忆 | ✅ | 1/3/5/8 档；「以后不再弹出」持久化 |
| 隐私模式开关 | ❌ | 鸿蒙沙箱天然私有目录，等价默认成立 |

### ❌ 裁剪清单（O 级，未移植）

| 原功能 | 裁剪理由 |
| --- | --- |
| 隧道子系统全家桶：Tor 插件 / WARP-MASQUE / DoH / SNI 切片·置空 / ECH / 隧道 HUD / 启动门控 | 依赖 Android 插件生态、arm64 原生内核与 conscrypt 反射，鸿蒙无对应机制；首页「镜像延迟灯」承接顶栏状态位 |
| PDF / 7z / tar.gz 导出及全部档位设置 | CBZ 已覆盖「离线可读 + 通用阅读器兼容」主诉求，多格式 = 自研压缩器 ×3 的维护成本 |
| WebDAV 云同步、本地 CBZ 导入 | 工程约定 O 级裁剪 |
| 独立进程崩溃提示页 | 保留全局错误兜底 + crash 日志文件（见上表） |
| 内置浏览器 | 原版 v0.8.4 已自行移除（死代码，0 处导航引用） |
| 开发者模式（模拟崩溃/日志级别/诊断区/连点彩蛋） | 调试向能力，非用户主流程 |
| 热搜榜 /「飙升榜」分段 / 评论服务端排序 | API 无对应参数或数据源，不伪造 |

## 🧱 工程结构

```
jinmanji-harmony/
├─ AppScope/                        # 应用级配置（bundleName: com.jinmanji.app, v1.0.0）与图标
├─ build-profile.json5              # SDK 基线 26.0.0（API 26）、签名配置（当前为空）
├─ docs/                            # 复刻规格文档（conventions / api-spec / feature-spec / uiux-design）
└─ entry/                           # 单模块工程（不拆 HSP/HAR）
   └─ src/main/
      ├─ module.json5               # 权限：ohos.permission.INTERNET、ACCESS_BIOMETRIC（应用锁）
      ├─ ets/
      │  ├─ entryability/EntryAbility.ets   # 全屏布局 + 全局错误观察者（crash 日志落盘）
      │  ├─ common/                 # Theme 主题 token / Components 通用组件(骨架·空态·错误) / Route 路由常量
      │  ├─ models/Models.ets       # Album/AlbumLite/Chapter/CommentItem 等模型（全 class）
      │  ├─ data/
      │  │  ├─ JmApi.ets            # API 客户端：token/AES 信封、域名池+测速+隔离、图片 CDN 分流
      │  │  ├─ ImageDecode.ets      # 反混淆：computeSegments + 垂直倒序重排 + 原尺寸解码链路
      │  │  ├─ Stores.ets           # 收藏/历史(300)/搜索历史(50)/精确进度/屏蔽词/缓存等持久化
      │  │  └─ DownloadManager.ets  # 下载队列状态机 + CBZ 导出（自实现 CRC32 的 ZIP 写入器）
      │  ├─ util/                   # Http(@ohos.net.http 封装) / Prefs(preferences 封装+全部 key)
      │  └─ pages/
      │     ├─ Index.ets / MainShell.ets    # 唯一 @Entry + Navigation 四 Tab 壳（应用锁拦截/返回逻辑）
      │     ├─ ExplorePage.ets              # 发现：榜单/随机/最新
      │     ├─ CategoryPage.ets / SearchPage.ets
      │     ├─ AlbumDetailPage.ets          # 详情 + 评论抽屉
      │     ├─ ReaderPage.ets               # 阅读器
      │     ├─ BookshelfPage.ets / DownloadsPage.ets
      │     └─ SettingsPage.ets             # 我的：分组设置
      └─ resources/base/           # element/color·string、media 图标、profile/main_pages
```

共 21 个 `.ets` 源文件、约 1.6 万行。编码硬规则（显式类型、禁 `any`、class 禁对象字面量、颜色引用 Theme token 等）见 `docs/conventions.md` §5。

## 🛠️ 从源码构建

**环境要求**：[DevEco Studio](https://developer.huawei.com/consumer/cn/deveco-studio/) 最新版 + **HarmonyOS 26.0.0 SDK（API 26）**；或 Command Line Tools（`devecocli` 1.3.0+，实测可用）。系统 Node 由工具链自带。

1. **打开工程**：DevEco Studio → File → Open → 选择 `jinmanji-harmony/` 目录（含根 `oh-package.json5` 的层级），等待自动 Sync/Index 完成。
2. **编译**：Build → Build Hap(s)/APP(s) → Build Haps。产物：`entry/build/default/outputs/default/entry-default-unsigned.hap`。
   命令行等价（配合 [Command Line Tools](https://developer.huawei.com/consumer/cn/download/) 的 hvigor）：
   ```sh
   export DEVECO_SDK_HOME=<command-line-tools>/sdk   # Windows 用 set
   hvigorw assembleHap --mode module -p product=default --no-daemon
   ```
3. **签名**：仓库 `build-profile.json5` 的 `signingConfigs` 为空，直接打包得到的是**未签名 HAP，无法安装**。两种方式任选：
   - 调试签名（推荐）：File → Project Structure → Signing Configs → 勾选 *Automatically generate signature*（需登录华为开发者账号），DevEco 自动生成调试证书并回填配置；
   - 手动：将 `.p12 / .cer / .p7b` 与 Profile 填入 `signingConfigs`，重新 Build 得到 `entry-default-signed.hap`。
4. **运行**：真机开启开发者模式 + USB 调试后连接（或启动 Device Manager 模拟器），点击 Run ▶ 即可安装启动；也可 `hdc install entry-default-signed.hap`。

> 本仓库当前已在本机 command-line-tools 工具链下通过 hvigor `assembleHap` 编译（CompileArkTS 无错误，产出未签名 HAP 约 2MB）；**尚未做任何真机/模拟器安装与运行验证**，见下节。

## ⚠️ 已知限制（如实说明）

- **未真机验证**：所有验证止于编译与静态检查；运行时行为（网络、解码、手势、userAuth、DocumentViewPicker 等）未在真机或模拟器上实测。
- **生物识别锁**：`module.json5` 未声明 `ohos.permission.ACCESS_BIOMETRIC`，真机上指纹验证预计不可用——按 S 级语义降级为「仅保存开关状态」，不会锁死应用。
- **数据导入无入口**：设置页仅实现导出；数据层已具备合并导入接口（同 id 去重、历史保较新），UI 待补。
- **CBZ 缺失页**以灰底占位图写入压缩包（与规格「跳过缺失页」口径不同，为保持 ZIP 页序完整）。
- **日漫右翻/双页**仅保留模式枚举与切换，渲染与横向模式相同；**米黄阅读背景**、部分搜索筛选选择为会话态，不持久化。
- **屏蔽词**增删后各列表需下拉刷新/重进才重新过滤；从阅读器返回书架需切分段或重进 Tab 才刷新横幅与历史。
- **下载并发**为单任务页并发 3（原版 2）；暂停后恢复为重新排队（原版亦无断点续传）。
- **搜索历史多选批量删除**未实现（点击即搜/单条删除/清空可用）。
- **无隧道子系统**：全部流量直连镜像域名池（保留 3 域名重试 + 失败隔离 5 分钟 + 18s 总预算 + 图片 CDN 分流轮换）；在需要抗封锁网络的网络环境下可能无法访问，这是与原版最大的能力差距。
- 屏蔽词匹配为字段级（标题/作者/分类），原版「后台拉真实标签校准屏蔽」已裁剪，屏蔽命中率低于原版。

## 📜 开源协议与致谢

- 本项目为 [jinmanji-app](../jinmanji-app/) 的复刻衍生作品，随原项目采用 **GNU GPL-3.0**，原项目第三方组件清单见 [THIRD_PARTY_NOTICES.md](../jinmanji-app/THIRD_PARTY_NOTICES.md)。
- 鸿蒙版**零第三方 ohpm 依赖**（`dependencies: {}`），仅使用系统 Kit：`@ohos.net.http`、`@ohos.data.preferences`、`@ohos.file.fs`、`@ohos.multimedia.image`、`@ohos.userIAM.userAuth` 等；ZIP/CRC32/AES/MD5 均用系统 cryptoFramework 或自实现，无任何移植库。
- 协议逆向与图片乱序还原算法的社区知识，致谢原项目声明中的 **hect0x7/JMComic-Crawler-Python** 与 **lanyeeee/jmcomic-downloader**。

## ⚠️ 免责声明

本项目为非官方第三方客户端，仅供学习与技术研究使用；请勿用于任何商业用途或违反当地法律法规的行为。请自行评估并承担使用风险。
