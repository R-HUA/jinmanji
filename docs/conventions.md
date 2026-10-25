# jinmanji-harmony 工程约定（所有参与工程师必读）

本项目目标：把 Android 原应用 `jinmanji-app/`（Kotlin + Jetpack Compose 的 JMComic 漫画阅读器）完整复刻为 HarmonyOS 原生应用（ArkTS + ArkUI）。UI 设计语言参照 `docs/uiux-design.md`。

## 1. 技术基线

- HarmonyOS，目标 API 版本 26（`"compatibleSdkVersion": "26.0.0"`, `"targetSdkVersion": "26.0.0"`，modelVersion 26.0.0），本机 devecocli 1.3.0 + HarmonyOS 26.0.0 SDK 实测编译通过。
- 单模块 entry 工程，不拆 HSP/HAR。
- 只用系统 Kit：`@ohos.net.http`、`@ohos.data.preferences`、`@ohos.data.relationalStore`（可选，能用 preferences 就用）、`@ohos.file.fs`、`@ohos.multimedia.image`、`@ohos.userIAM.userAuth`（可选简版）、ArkUI 内置组件。
- 禁止：任何第三方 ohpm 依赖；`@kit.UIDesignKit` / HdsTabs / uiMaterial 等 HarmonyOS 7 专有 API（设计文档中的这类能力一律用稳定 API 等价实现：`Tabs` + `backgroundBlurStyle`、`bindSheet`、`geometryTransition` 可选）；experimental API。
- 所有 `.json5` 配置必须是**严格 JSON**：无注释、无尾逗号（脚本会用 `JSON.parse` 校验）。
- 网络图片直接 `Image(url)`（系统 Image 支持网络源并自动缓存）；需要反混淆的章节大图走 `data/ImageDecode.ets`。

## 2. 目录与文件所有权（谁只能动哪里）

```
jinmanji-harmony/
├─ AppScope/
│  ├─ app.json5                                  ← 工程架构师
│  └─ resources/base/element/{string.json,color.json} ← 工程架构师
├─ build-profile.json5 / hvigorfile.ts / hvigor/hvigor-config.json5 / oh-package.json5 / .gitignore ← 工程架构师
├─ docs/                                          ← 分析师产出（api-spec.md、feature-spec.md），其他人只读
└─ entry/
   ├─ build-profile.json5 / hvigorfile.ts / oh-package.json5 ← 工程架构师
   ├─ src/main/module.json5                       ← 工程架构师
   ├─ src/main/ets/
   │  ├─ entryability/EntryAbility.ets            ← 工程架构师（沉浸式全屏 + 最简全局错误兜底）
   │  ├─ common/{Theme.ets, Components.ets, Route.ets} ← 工程架构师
   │  ├─ models/Models.ets                        ← 数据层工程师
   │  ├─ data/{JmApi.ets, ImageDecode.ets, Stores.ets, DownloadManager.ets} ← 数据层工程师
   │  ├─ util/{Http.ets, Prefs.ets}               ← 数据层工程师
   │  └─ pages/
   │     ├─ Index.ets / MainShell.ets             ← 工程架构师
   │     ├─ ExplorePage.ets                       ← 发现页工程师
   │     ├─ CategoryPage.ets / SearchPage.ets     ← 分类与搜索工程师
   │     ├─ AlbumDetailPage.ets                   ← 详情页工程师
   │     ├─ ReaderPage.ets                        ← 阅读器工程师
   │     ├─ BookshelfPage.ets / DownloadsPage.ets ← 书架工程师
   │     └─ SettingsPage.ets                      ← 设置页工程师
   └─ src/main/resources/base/
      ├─ element/{color.json, string.json}        ← 工程架构师
      ├─ media/app_icon.png                       ← 工程架构师（base64 占位图）
      └─ profile/main_pages.json                  ← 工程架构师（只注册 pages/Index）
```

任何人不得改动所有权之外的文件，也不得改动 `jinmanji-app/` 下任何内容。

## 3. 组件与路由契约

- 唯一 `@Entry` 页面：`pages/Index.ets`，内容仅挂载 MainShell；`main_pages.json` 只注册 `pages/Index`。
- `MainShell.ets`：`Navigation(this.pageStack)` 内放底部 `Tabs` 四栏：发现=`ExplorePage`、分类=`CategoryPage`、书架=`BookshelfPage`、我的=`SettingsPage`。`NavPathStack` 通过 `@Provide('navPathStack')` 下发，子页 `@Consume('navPathStack')` 获取，用 `pushPathByName(name, param)` 跳转。
- **MainShell 必须预注册全部路由**（import 下列页面组件并实现 navDestination 构建器映射表）。页面文件由后续工程师按本契约创建，import 可先指向当时尚不存在的文件（同轮稍后补齐），但**导出名与路径必须严格一致**：

| 文件 | export struct | Route.ets 常量（值） | push 参数 |
| --- | --- | --- | --- |
| pages/SearchPage.ets | `SearchPage` | ROUTE_SEARCH（"search"） | `{ query?: string }` |
| pages/AlbumDetailPage.ets | `AlbumDetailPage` | ROUTE_ALBUM（"albumDetail"） | `{ aid: string }` |
| pages/ReaderPage.ets | `ReaderPage` | ROUTE_READER（"reader"） | `{ aid: string, chapterId?: number, chapterIndex?: number, page?: number }` |
| pages/DownloadsPage.ets | `DownloadsPage` | ROUTE_DOWNLOADS（"downloads"） | 无 |

- 页面接收参数：`NavDestination().onReady((ctx: NavDestinationContext) => { const p = ctx.pathInfo.param as RouteParams; ... })`。
- 四个 Tab 页组件直接嵌入 Tabs，不经路由；其余页面均为 NavDestination。
- 阅读器全屏沉浸：`expandSafeArea` + 深色背景；从详情页"开始阅读/续读"进入时携带上次阅读进度。

## 4. 数据契约（数据层工程师实现；页面工程师只读使用，以文件实际导出为准）

- `models/Models.ets`：`Album`、`AlbumLite`、`Chapter`、`ChapterPage`、`CommentItem`、`SearchOptions`、`RankingType` 等模型——全部 class，字段显式类型 + 构造器默认值。
- `data/JmApi.ets`：`export const jmApi` 单例；方法与原 Kotlin 对齐：首页/最新、榜单（日/周/月）、随机推荐、搜索、分类列表、专辑详情（含章节）、章节分页数据、评论列表、图片 URL 拼装（含反混淆 seed 提取）。
- `data/ImageDecode.ets`：忠实移植原 `JmImageDecoder.kt` 的分块重排算法，形如 `export async function descramble(buf: ArrayBuffer, seed: number): Promise<PixelMap>`；并提供"网络字节 → 重排 → PixelMap"的整链路辅助函数供阅读器/预览调用。
- `data/Stores.ets`：收藏、阅读历史（精确到 `{aid, chapterId, chapterIndex, page, totalPages, at}`）、搜索历史的增删查改（`@ohos.data.preferences` 或 relationalStore，异步接口）。
- `data/DownloadManager.ets`：下载队列单例，状态机（等待/下载中/暂停/完成/失败）、并发控制、进度回调、CBZ 导出（手写最小 ZIP 写入器：STORE 不压缩 + 自实现 CRC32，不依赖第三方）。
- `util/Http.ets`：基于 `@ohos.net.http` 的 GET 封装（超时、UA/headers、cookie、错误归一化为带 message 的 Error）；域名/镜像从 Prefs 读取，可切换。
- `util/Prefs.ets`：`@ohos.data.preferences` 封装；所有 key 常量集中在此（当前镜像域名、主题模式、阅读器默认模式/预加载页数、亮度记忆、安全锁开关等）。
- 页面工程师若发现契约缺失（方法/字段不存在），**记入返回结果 notes，不要自行在页面文件里补数据层**。

## 5. ArkTS 硬规则（编译不过 / 检查必揪的常见坑）

- 一切变量/参数/返回值显式类型；禁止 `any`/`unknown`；模型一律 class，**禁止给 class 形参传对象字面量**——先 `new` 再逐字段赋值。
- 状态用装饰器：`@State`/`@Prop`/`@Link`/`@Provide`/`@Consume`/`@Watch`/`@ObjectLink`；UI 状态勿放普通成员变量。
- `ForEach` 第二参数必须提供稳定 keyGenerator；长列表用 `List` + `LazyForEach`（配 IDataSource）或 `cachedCount`；瀑布流 `WaterFlow` + `FlowItem`；横向胶片 `List` + `.listDirection(Axis.Horizontal)`。
- 异步 `async/await`，`Promise<T>` 泛型写全；网络/IO 失败要有 catch 并落到页面错误态。
- 禁止 TS 口语写法：解构 class、展开运算符重组 class、索引签名、`as object` 滥用；联合字面量类型可用。
- 颜色一律引用 `common/Theme.ets` 常量（运行时 string 颜色），不散落硬编码；例外：半透明遮罩等一次性 rgba 可内联。

## 6. 主题 token（common/Theme.ets 必须提供，页面一律引用）

- `PRIMARY = '#FF4D6D'`（品牌粉：Tab 激活、收藏、强调）、`ACCENT = '#3B5BDB'`（主 CTA 蓝：开始阅读等主行动按钮）
- `BG = '#F7F8FA'`、`CARD = '#FFFFFF'`、`TEXT_MAIN = '#1E293B'`、`TEXT_SUB = '#64748B'`
- `CHIP_BG = 'rgba(226,232,240,0.65)'`、`READER_BG = '#0D0D0D'`、`DIVIDER = '#E2E8F0'`、`TAB_INACTIVE = '#8E8E93'`
- 圆角：`COVER_R = 12`、`CARD_R = 12`、`CHIP_R = 14`；封面比例 3:4。

## 7. 范围分级（复核时按此判定，不得把 O 级当缺失上报）

- **必保（M）**：四大 Tab 主流程；搜索（关键词 + JM 编号直达）；详情（视差头/元数据/CTA/章节列表/前 8 页胶片 + 全量预览 bindSheet/评论 bindSheet）；阅读器（条漫 + 左右翻页 + 点按热区 + 上下 HUD + 进度滑条 + 续读保存 + 预加载）；书架（收藏/历史/下载三段 + 续读横幅）；下载队列 + CBZ 导出；设置（镜像切换 + 测速、缓存清理、数据 JSON 导出）。
- **简化（S）**：生物识别锁（userAuth 指纹，失败回退开关）；剪贴板 JM 编号识别（进搜索页自动填充即可）；双页拼合/日漫右翻（保留模式枚举与切换，双页渲染可后补）；亮度滑条只调应用内遮罩亮度；缩放手势双击放大可简化。
- **裁剪（O）**：Tor/WARP/MASQUE/DOH 隧道子系统（plugin-tor 与 util/net 深层网络改造）；PDF 导出；独立进程崩溃页（保留最简全局错误兜底与 crash 日志文件）；WebDAV 云同步；实况窗/悬浮窗下载进度（页面内进度替代）；本地 CBZ 导入。

## 8. 其它

- `resources/base/media/app_icon.png`：工程架构师用 base64 解码生成的纯色/简单占位 PNG。
- 图标优先 `SymbolGlyph($r('sys.symbol.xxx'))` 常见系统符号名，不确定可用性时退化用 Text 符号（如 ♥ ⬇ 💬）。
- 所有 UI 文案中文；数字单位本地化（10591 → 1.1万 或 10.6k 均可，风格统一）。
- 每个页面必须处理：加载骨架/加载态、空态、错误态（含重试）、分页/加载更多（适用处）。
