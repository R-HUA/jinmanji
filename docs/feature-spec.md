# 禁漫姬 HarmonyOS 复刻 · 功能规格说明书（feature-spec）

- 产出：界面分析师（UX 分析）
- 日期：2026-10-24
- 分析对象：`jinmanji-app/`（Kotlin + Jetpack Compose，版本 v0.15.x，全部 UI/设置/数据层文件逐一通读）
- 设计依据：`jinmanji-harmony/docs/uiux-design.md`（新 IA：4 Tab + 路由页）、`jinmanji-harmony/docs/conventions.md`（工程契约与 §7 范围分级）
- 引用格式：`Android 文件:行号` 均相对 `jinmanji-app/app/src/main/java/com/mobai/jm/`（省略前缀时指此目录）。

## 0. 分级基线（与 conventions.md §7 一致，细化到条目）

| 级别 | 定义（conventions §7 原文基线） | 本文细化判定标准 |
| --- | --- | --- |
| **M 必保** | 四大 Tab 主流程；搜索（关键词+JM 编号直达）；详情（视差头/元数据/CTA/章节列表/前 8 页胶片+全量预览 bindSheet/评论 bindSheet）；阅读器（条漫+左右翻页+点按热区+上下 HUD+进度滑条+续读保存+预加载）；书架（收藏/历史/下载三段+续读横幅）；下载队列+CBZ 导出；设置（镜像切换+测速、缓存清理、数据 JSON 导出） | 缺失即视为功能不完整的用户可感知能力；交互、状态（加载/空/错误/重试）、数据依赖一并验收 |
| **S 简化** | 生物识别锁；剪贴板 JM 编号识别；双页拼合/日漫右翻（保留枚举）；亮度滑条（应用内遮罩）；双击放大可简化 | 功能保留但实现降级，本文逐条写明"简化到什么程度" |
| **O 裁剪** | Tor/WARP/MASQUE/DOH 隧道子系统；PDF 导出；独立进程崩溃页（保留最简全局错误兜底与 crash 日志）；WebDAV；实况窗/悬浮窗下载进度；本地 CBZ 导入 | 一句话理由；复核时不得把 O 级当缺失上报 |

**统计口径**：本文功能项共 **187 条**（全局壳 8 + 发现 16 + 分类 8 + 书架 13 + 我的 4 + 搜索 16 + 详情 20 + 评论 6 + 阅读器 29（页面级 R-00 + 矩阵 R-01~R-28）+ 下载 12 + 设置 45 + 无安放界面处置 10），编号即验收清单。首标记分级分布：M 110 / S 40 / O 37（按每条首个分级标记统计，个别条目内含子分级，以行内说明为准）。

---

## 1. 信息架构映射总览（原 → 鸿蒙）

原项目结构（`ui/App.kt:142-186` 五 Tab 常驻 + `ui/App.kt:191-278` 覆盖层堆叠）：

| 原项目界面 | 原入口 | 新 IA 去向 | 备注 |
| --- | --- | --- | --- |
| 发现 HomeScreen | Tab 0 | **Tab1 发现** | 搜索并入顶栏；分类速览裁剪（X-05/E-13） |
| 分类 CategoryScreen | Tab 1 | **Tab2 分类** | 列表+分类详情双层结构保留 |
| 搜索 SearchScreen | Tab 2 | **路由页 A 搜索** | 发现页顶栏胶囊进入（conventions §3 ROUTE_SEARCH） |
| 收藏 FavoritesScreen | Tab 3 | **Tab3 书架 · 收藏段** | 顶栏"词云"入口随词云处置（§5） |
| 设置 SettingsScreen | Tab 4 | **Tab4 我的** | 重组为分组设置页（§4） |
| 历史历史 HistoryScreen | 设置页入口（覆盖层） | **Tab3 书架 · 历史段** | 合并 |
| 下载 DownloadsScreen | 设置页入口（覆盖层）+ 通知点击（`util/NavSignals.kt`） | **路由页 D 下载管理** + 书架下载段入口 | 合并 |
| 随机推荐 RandomScreen | 发现页"更多›"（覆盖层） | **发现页随机区块**承载；独立全屏页为 S 备选 | §5 T-02 |
| 标签词云 TagCloudScreen | 收藏页顶栏"词云" | **建议裁剪**（或并入书架标签段，S） | §5 T-01 |
| 详情 AlbumDetailScreen | 全局覆盖层 | **路由页 B 详情** | conventions §3 ROUTE_ALBUM |
| 阅读器 ReaderScreen | 详情/预览进入 | **路由页 C 阅读器** | conventions §3 ROUTE_READER |
| 评论 CommentsScreen | 详情"评论"按钮 | **详情页评论 bindSheet 抽屉**（不再整页） | uiux-design 页面 D |
| 内置浏览器 BrowserScreen | （无入口，死代码） | **不复刻** | §5 T-03 |
| 启动门控 StartupGateScreen | 隧道自动连接时 | **裁剪** | §5 T-04 |
| 隧道 HUD TunnelHud | 全局右上角 | **裁剪**；顶栏"镜像延迟灯"替代（E-02） | §5 T-05 |
| 崩溃页 CrashActivity | 崩溃时（独立进程） | **裁剪独立进程页**，保留全局兜底+crash.log | §5 T-06 |

新 IA 骨架（conventions §3）：`Index.ets → MainShell`（`Navigation` + 底部 `Tabs` 四栏：发现=`ExplorePage`、分类=`CategoryPage`、书架=`BookshelfPage`、我的=`SettingsPage`）；路由页 Search / AlbumDetail / Reader / Downloads 为 NavDestination，`pushPathByName` 跳转。

---

## 2. 逐屏功能清单（按鸿蒙新 IA）

### 2.0 全局壳 MainShell（8 项）

| 编号 | 功能项（分级） | 原项目依据 | 规格 |
| --- | --- | --- | --- |
| X-01 | 底部 4 Tab 光感导航：发现/分类/书架/我的（**M**） | `ui/App.kt:369-385`（原 5 Tab SlimNavigationBar） | 底部 `Tabs`（barPosition End）+ `backgroundBlurStyle` 等价光感（conventions §1 禁 HdsTabs）；选中 `PRIMARY #FF4D6D`、未选中 `TAB_INACTIVE`；Tab 页直接嵌入不经路由。原"搜索"Tab 取消，职能并入发现顶栏 |
| X-02 | 二级路由注册与跳转（**M**） | `ui/App.kt:233-278`（覆盖层堆叠） | `NavPathStack` `@Provide('navPathStack')`；预注册 ROUTE_SEARCH / ROUTE_ALBUM / ROUTE_READER / ROUTE_DOWNLOADS（conventions §3 参数表：search `{query?}`、albumDetail `{aid}`、reader `{aid, chapterId?, chapterIndex?, page?}`、downloads 无参） |
| X-03 | 全局沉浸式 edge-to-edge（**M**） | 各屏 `windowInsetsPadding(WindowInsets.systemBars)` 反向要求 | EntryAbility 全屏布局 + 页面 `expandSafeArea`；阅读器深色背景动态状态栏反色（uiux §二.2） |
| X-04 | 返回逻辑（**M**） | `ui/App.kt:96-105`（覆盖层兜底 + 非 Tab0 先回发现） | 简化为 Navigation 栈自然返回；Tab 间切换用底部栏；系统返回在二级页=pop，在 Tab 页=默认退出（保留"非发现 Tab 先回发现"行为 `ui/App.kt:105`） |
| X-05 | Tab 级状态保留（**M**） | `ui/App.kt:119-121`（主界面常驻组合，滚动位置/搜索结果不丢） | 四个 Tab 页组件常驻（Tabs 不销毁未选页内容需用条件加载+状态外提到 Store/@State 上层）；搜索结果与滚动位置保留（SearchStore 等价行为，S-13） |
| X-06 | 已在发现 Tab 再点发现 = 刷新（**S**） | `ui/App.kt:127-132` | 简化：保留"再点刷新"；也可用首页下拉刷新替代，二者至少实现其一 |
| X-07 | 全局错误兜底 + crash 日志（**M**） | `util/CrashHandler.kt`、`ui/CrashActivity.kt:37` | EntryAbility 最简全局错误兜底（conventions §1），未捕获异常写入 crash.log 文件；独立进程崩溃提示页本身为 O（T-06） |
| X-08 | 应用图标与文案基线（**M**） | `README.md:99`（Logo/品牌） | AppScope 图标占位（conventions §8）；全部 UI 文案中文；数字本地化（10591→1.1万 或 10.6k，全局统一） |

### 2.1 Tab1 发现 ExplorePage（16 项）

原 HomeScreen（`ui/home/HomeScreen.kt`）+ RandomScreen 并入 + 搜索入口上移。

| 编号 | 功能项（分级） | 原项目依据 | 规格 |
| --- | --- | --- | --- |
| E-01 | 沉浸光感吸顶搜索栏（**M**） | uiux-design §四.1（新增交互）；原搜索 Tab 入口 `ui/App.kt:164` | 吸顶栏（`backgroundBlurStyle`）：左品牌标识 + 中胶囊搜索入口（提示词"搜索漫画名、作者或输入 JM 编号直达"）+ 右排行榜快捷入口。点击胶囊 → `pushPathByName(ROUTE_SEARCH)`。不再有独立搜索 Tab |
| E-02 | 顶栏节点延迟状态灯（**M**） | 替代 `ui/components/TunnelHud.kt:29-70`（隧道 HUD，T-05） | 绿点 + `xx ms`，数据源 = **镜像测速结果**（SET-28，conventions M：镜像测速）；点击展示当前镜像域名与最近测速值（隧道流量/速度等隧道指标裁剪） |
| E-03 | 热门榜单区：分段切换（**M**） | `ui/home/HomeScreen.kt:200-214`（原仅总榜横滑 30 条）；`data/JmApi.kt:417-427` ranking 支持 mv_t/mv_w/mv_m/mv | `SegmentButton`：日榜/周榜/月榜/总榜（mv_t/mv_w/mv_m/mv）。uiux 的"飙升榜"API 无对应参数，**用『最新(mr)』占第四档之外不新增**——四分段=日/周/月/总，不造无数据源的分段。数据：`jmApi.ranking("0", order, 1)` |
| E-04 | 热门榜单区：横滑卡片流 + 前三名金银铜角标（**M**） | 同上；角标为 uiux §四.1 新增 | 横向 `List`（`listDirection(Horizontal)`）封面卡；前 3 名数字角标（金/银/铜），点卡片 → ROUTE_ALBUM |
| E-05 | 随机推荐区块：横滑卡片 + 换一批（**M**） | `ui/home/HomeScreen.kt:148-171`；`data/Stores.kt:108-124`（refreshRandom 单段刷新+本地洗牌） | 区块头部"随机推荐 + ⟳ 换一批"，换一批时旋转图标动效 + 交错淡入（uiux）。数据：`jmApi.random()` 本地洗牌展示；失败 Snackbar/Toast 提示且保留旧内容（`HomeStore.refreshRandom` 行为） |
| E-06 | 随机推荐区块：屏蔽过滤（**S**） | `ui/home/HomeScreen.kt:163`（BlockTagsStore.isBlocked 过滤） | 简化：命中标题/作者/分类/子分类即隐藏（`BlockTagsStore.isBlocked` 的字段匹配部分）；真实标签联动校准（TagStore.enrich 全量拉详情）裁剪（T-08） |
| E-07 | 随机推荐独立全屏页（**S**） | `ui/random/RandomScreen.kt:55-150`（大池合并去重 + 单次洗牌顺序分页 + PageBar + 作者点击搜索） | 简化方案 A（推荐）：并入发现区块（E-05），"更多›"改为滚动定位到区块，不建独立页；方案 B：保留全屏路由页（大池=随机+最新+排行去重合并、`baseSeed` 洗牌、PageBar 翻页、每页数量设置 SET-04）。二选一，A 为默认 |
| E-08 | 最新更新区：3 列网格 + 分页（**M**） | `ui/home/HomeScreen.kt:216-248`；`data/JmApi.kt:413-415` latest(page)（每页 80 条） | `Grid`/`WaterFlow` 3 列 + 底部 PageBar（上一页/页码/下一页）；数据 `jmApi.latest(page)`；页码点击跳页见 E-09 |
| E-09 | 分页条点击跳页（**S**） | `ui/components/PageBar.kt:47-87`（点击页码弹跳页输入框） | 简化：保留"上一页/下一页 + 当前页/总页"显示；跳页输入弹窗可后补（全站 PageBar 统一组件行为） |
| E-10 | 分类速览快捷胶囊（**O**） | `ui/home/HomeScreen.kt:173-198` | 裁剪：与 Tab2 分类职能重复，uiux §四.1 明确"移除冗余分类速览"；自定义分类入口保留在分类页（C-04） |
| E-11 | 封面卡片标准化（**M**） | `ui/components/ComicCard.kt:39-112` | 3:4 圆角封面（`COVER_R=12`、内描边）+ 右上角**文本徽章**（中字/日漫/韩漫/全彩，替代原圆形国旗贴图，uiux §四.1）+ 书名两行省略 + 作者行（可点搜索）；长按回调保留（书架删除用） |
| E-12 | 语言徽章判定（**S**） | `data/TagStore.kt:31-45`（标签级判定 + LangDetect 启发式回退） | 简化：标题/作者/分类关键词启发式（LangDetect 等价逻辑移植）为默认；详情页加载后用真实 tags 校准（TagStore.remember 等价，进 D-07）；**列表滚动时后台拉详情校准（enrich）裁剪**（T-08） |
| E-13 | 封面骨架屏 + 渐进加载（**M**） | `ui/components/Shimmer.kt:17-26`（呼吸式闪烁块）；`ui/components/ComicCard.kt:67-73` | 加载前柔和脉冲动画占位（conventions §8 每页必须骨架/加载态） |
| E-14 | 首页数据缓存秒开（**M**） | `data/HomeCache.kt`；`data/Stores.kt:49-66`（缓存优先展示→网络刷新替换→失败保留旧缓存） | 发现页三区数据本地缓存（preferences/文件）；刷新失败保留旧内容 + Snackbar 提示（`ui/home/HomeScreen.kt:104-110`）；空+失败态显示错误 + 重试按钮（`ui/home/HomeScreen.kt:128-141`） |
| E-15 | 封面错峰预取（**S**） | `ui/home/HomeScreen.kt:67-77`；`util/ImagePrefetch.kt` | 简化：系统 `Image(url)` 自带内存+磁盘缓存（conventions §1），不移植自研预取器；列表用 `cachedCount` 即可 |
| E-16 | 屏蔽词变更即时生效（**S**） | `data/BlockTagsStore.kt:59-74`（isBlocked 含真实标签匹配） | 简化：屏蔽词 Store 为响应式状态，增删后各列表重新过滤；匹配维度见 E-06（真实标签匹配裁剪） |

### 2.2 Tab2 分类 CategoryPage（8 项）

原 CategoryScreen（`ui/category/CategoryScreen.kt`）：分类列表层 + 分类详情层（selected 全局态，`data/Stores.kt:140-141`）。

| 编号 | 功能项（分级） | 原项目依据 | 规格 |
| --- | --- | --- | --- |
| C-01 | 分类频道列表（**M**） | `ui/category/CategoryScreen.kt:107-121`；`data/JmApi.kt:430-443` | ListItem：分类名 + "N 部作品"（total 为空或 0 时隐藏，`CategoryScreen.kt:109`）+ 右箭头；点击进入分类详情（页内二级视图或路由均可，返回保留列表位置）。数据：`jmApi.categories()` |
| C-02 | 分类详情：榜单排序 chips + 网格 + 分页（**M**） | `ui/category/CategoryScreen.kt:294-360` | FilterChips：日榜/周榜/月榜/总榜/最新（mv_t/mv_w/mv_m/mv/mr；无 slug 分类默认 mr、其余默认 mv，`CategoryScreen.kt:240-242`；slug 空用 "0"）；Adaptive 网格 ComicCard；底部 PageBar。数据：`jmApi.ranking(slug, order, page)`；翻页空结果 Toast"没有更多了"（`CategoryScreen.kt:276-278`） |
| C-03 | 分类详情：加载/错误/重试/空态（**M**） | `ui/category/CategoryScreen.kt:316-333` | 首载 spinner；错误文案 + 重试；conventions §8 |
| C-04 | 自定义分类/tag（**S**） | `ui/category/CategoryScreen.kt:123-158,171-226`；`data/Stores.kt:168-211` CustomCatStore | 简化保留：添加（≤16 字符码点计数、查重、错误提示）、点击=按关键词搜索（跳 ROUTE_SEARCH 带 query）、删除（确认弹窗）；原"长按删除"可简化为显式删除按钮/图标。持久化 JSON。**契约缺口**：conventions §4 Stores.ets 未含 CustomCat，见 §6 |
| C-05 | 分类列表缓存 + 全局选中保留（**M**） | `data/Stores.kt:132-166`（loadIfNeeded + selected 全局态） | 分类列表本地缓存；selected 切 Tab/返回保留 |
| C-06 | 吸顶多维筛选器（地区/题材/读者/排序联动）（**S**） | uiux §四.(2) 新增构想 | 简化：**不虚构 API 无有的维度**。落地为 C-02 的排序 chips + 分类切换即"多维"；地区/读者群体筛选 API 无参数（`JmApi.kt:418-427` 仅 c/o/page），不做假筛选器 |
| C-07 | 瀑布流错落封面流（**S**） | uiux §四.(2)（LazyVWaterFlowLayout 构想） | 简化：等高 3 列 Grid 已满足 M；瀑布流（WaterFlow）为视觉增强，可后补；卡片底部 2 个高频标签胶囊依赖真实标签数据（已裁剪 enrich），**降级为作者行** |
| C-08 | 分类网格屏蔽过滤（**S**） | `ui/category/CategoryScreen.kt:257`（TagStore.enrich 联动） | 同 E-06：字段匹配过滤保留，标签级校准裁剪 |

### 2.3 Tab3 书架 BookshelfPage（13 项）

新页（uiux §三：收藏升级为书架）。收藏（`ui/favorites/FavoritesScreen.kt`）+ 历史（`ui/history/HistoryScreen.kt`）+ 下载入口合并 + 新增续读。

| 编号 | 功能项（分级） | 原项目依据 | 规格 |
| --- | --- | --- | --- |
| B-01 | 三段结构：收藏 / 历史 / 下载（**M**） | 收藏 `FavoritesScreen.kt:120-215`；历史 `HistoryScreen.kt:89-196`；下载入口原在设置 `SettingsScreen.kt:359-365` | 页顶分段（SegmentButton 或页签）切换三段；下载段为任务摘要列表 + "进入下载管理"按钮 → ROUTE_DOWNLOADS |
| B-02 | 顶部一键续读横幅（**M**） | uiux §四.(3) 新增；conventions §7 M"续读横幅" | "继续阅读《标题》· 第N话 P.x"横幅（取最近一条阅读历史），点击 → ROUTE_READER 携带 `{aid, chapterIndex, page}`（conventions §3 参数） |
| B-03 | 精确阅读进度记录（**M**） | **原项目无**（`HistoryStore.record` 仅记录到本子级，`data/HistoryStore.kt:47-61`；阅读器 `ReaderScreen.kt:103` currentPage 从不落盘）| 新增：Stores.ets 阅读历史精确到 `{aid, chapterId, chapterIndex, page, totalPages, at}`（conventions §4 契约）；阅读器进入/翻页/切章/退出时写入 |
| B-04 | 书架卡片进度显示（**M**） | uiux §四.(3)（"读至 第1话 P.15 / 共174页"） | 收藏/历史卡片底部副标题显示进度（有进度时）；"有更新"红点依赖更新检测 API（无），**不做** |
| B-05 | 收藏段：网格 + 排序（**M**） | `FavoritesScreen.kt:84-89,207-213`；`ui/components/SortDialog.kt:40-45` | 网格 ComicCard；排序：时间/标题 × 正序/倒序（默认时间倒序），选择持久化（AppPrefs `favSort`，`util/AppPrefs.kt:233-238`）；长按卡片弹确认移除（`FavoritesScreen.kt:229-245`） |
| B-06 | 收藏段：手动添加（**M**） | `FavoritesScreen.kt:91-118`（jm 号/纯数字 → JmApi.album → FavStore.add；#开头或其他 → 收藏标签） | 顶部输入行 + 添加按钮：编号添加需请求 `jmApi.album(id)`（失败 Toast 错误信息）；`#标签` 直接入标签集。数据：`Stores.ets` FavStore 等价 |
| B-07 | 收藏标签 chips（**M**） | `FavoritesScreen.kt:152-185`（点按搜索/长按移除）；`data/FavStore.kt:86-116` | 标签胶囊区：点按 → ROUTE_SEARCH 带 query；长按（或简化为编辑态×按钮）弹确认移除；详情页长按标签收藏入口联动（D-08） |
| B-08 | 收藏空态（**M**） | `FavoritesScreen.kt:196-205` | "还没有收藏～ 在详情页点 ♥ 即可加入" |
| B-09 | 历史段：网格 + 排序 + 清空（**M**） | `HistoryScreen.kt:82-87,107-115,128-165`；`data/HistoryStore.kt`（上限 300 条） | 排序同 B-05（`historySort` 持久化）；清空需确认弹窗（`HistoryScreen.kt:210-226`）；历史上限 300 条行为保留 |
| B-10 | 历史段：长按多选批量操作（**S**） | `HistoryScreen.kt:64-76,94-105,167-194` | 简化：**必做**长按进入多选 + 全选/取消全选 + 批量删除；批量收藏/批量取消收藏（`batchFavorite`，`HistoryScreen.kt:229-246`）保留但可后补。选择态顶部栏显示"已选 N 项" |
| B-11 | 历史空态 + 记录开关联动（**M**） | `HistoryScreen.kt:118-126`；`SettingsScreen.kt:287-306` | 空态文案"还没有浏览历史（可在设置中关闭记录）"；SET-06 开关关闭后不再写入 |
| B-12 | 下载段：任务摘要列表（**M**） | `SettingsScreen.kt:359-365`（入口）；`ui/downloads/DownloadsScreen.kt:107-160`（列表） | 段内显示任务简表（封面缩略 + 标题 + 状态/进度条），点击任一任务 → ROUTE_DOWNLOADS；数据：DownloadManager.tasks |
| B-13 | 书架排序记忆（**M**） | `util/AppPrefs.kt:233-245`（favSort/historySort） | 两个排序偏好持久化（util/Prefs.ets） |

### 2.4 Tab4 我的 SettingsPage（4 项页面框架；设置项明细见 §4）

| 编号 | 功能项（分级） | 原项目依据 | 规格 |
| --- | --- | --- | --- |
| P-01 | 分组设置页骨架（**M**） | `ui/settings/SettingsScreen.kt:245-909`（LazyColumn + SectionTitle 分组） | 分组：外观 / 阅读偏好 / 通用 / 缓存 / 下载 / 数据 / 镜像与网络 / 隐私 / 关于（§4 全清单）；分组可折叠或常展开 |
| P-02 | 下载管理入口（**M**） | `SettingsScreen.kt:359-365` | "我的下载（N 个任务）"行 → ROUTE_DOWNLOADS |
| P-03 | 历史管理入口（**S**） | `SettingsScreen.kt:279-284` | 简化：入口移至书架历史段（B-09），我的页保留"记录浏览历史"开关（SET-06）即可，不再重复整页入口 |
| P-04 | 关于区（**M**） | `SettingsScreen.kt:879-908` | 版本号 + 免责声明（"个人学习项目，请勿用于商业用途"）；连点 5 次开开发者模式的彩蛋 → O（T-07） |

### 2.5 路由页 A：搜索 SearchPage（16 项）

原 SearchScreen（`ui/search/SearchScreen.kt`）+ SearchStore（`ui/search/SearchStore.kt`，全局状态保留）。

| 编号 | 功能项（分级） | 原项目依据 | 规格 |
| --- | --- | --- | --- |
| S-01 | 搜索输入 + 搜索按钮（**M**） | `SearchScreen.kt:134-154` | 胶囊输入框（placeholder"请输入……"）+ 搜索按钮 + IME Search 动作；空输入不触发 |
| S-02 | JM 编号直达（**M**） | `SearchScreen.kt:72-73,104-114`（正则 `jm123456/JM123456/123456`） | 纯编号/jm 前缀输入 → 直接 `pushPathByName(ROUTE_ALBUM, {aid})`，不做关键词搜索；conventions §7 M |
| S-03 | 外部搜索请求（作者/标签点击带入）（**M**） | `ui/App.kt:150-153,249-257`（SearchRequest + 关闭覆盖层）；详情/词云/随机多来源 | 详情页标签/作者、书架标签 chips 等跳转 → ROUTE_SEARCH `{query}` 自动执行搜索 |
| S-04 | 结果网格 + 总数（**M**） | `SearchScreen.kt:322-361`；`data/JmApi.kt:686-708` search() | Adaptive 网格 ComicCard + "共 N 条"计数（+ 排序/筛后计数，见 S-08）；空结果显示"没有符合筛选的结果"（`SearchScreen.kt:330-338`） |
| S-05 | 分页（**M**） | `SearchScreen.kt:352-359`；`SearchStore.kt:235-244`（pageCount/hasNextPage，筛选模式下虚拟页） | PageBar 上一页/下一页/页码；筛选补足模式下为虚拟分页 |
| S-06 | 排序（服务端参数）（**M**） | `SearchScreen.kt:376-386`（mr/mv/mp/tf = 最新/最多观看/最多图片/最多爱心） | 筛选抽屉内单选；变更即重搜并持久化（`SearchStore.kt:256-261`） |
| S-07 | 时间筛选（服务端参数）（**M**） | `SearchScreen.kt:388-408`（a/t/w/m 全部/今日/本周/本月） | 单选；与排序并存；持久化 |
| S-08 | 指定年月筛选弹窗（**S**） | `SearchScreen.kt:482-556`（年 2026→2006 下拉 + 月 1-12/全年；应用/清除） | 简化保留：年月二级选择器（`JmApi.search` 的 y/m 参数）；与时间预设互斥逻辑保留（`SearchStore.kt:263-281`） |
| S-09 | 语言多选 + 全彩（客户端过滤）（**S**） | `SearchScreen.kt:410-418`；`SearchStore.kt:337-373`（applyFilter：语言=或、自定义词=或、两组与；LangDetect 启发式；"未识别"选项） | 简化：内置语言 zh/ja/en/ko/未识别 + 全彩开关；匹配用标题/作者/分类关键词启发式（全彩判定同 E-12 简化）；标签级校准裁剪。**注意**：客户端过滤依赖"筛选补足"才能翻页有效（S-11） |
| S-10 | 自定义筛选词（**S**） | `SearchScreen.kt:420-449,558-595`；`SearchStore.kt:318-335`（≤16 字符、查重、勾选、删除、持久化） | 简化保留：添加/勾选/删除 + 持久化（Prefs.ets）；行内删除图标保留 |
| S-11 | 筛选补足自动扫描（**S**） | `SearchStore.kt:185-219`（筛选激活时连翻 API 页直到虚拟页装满，单次上限 8 页） | 简化保留：无客户端筛选时直接取 API 页；有筛选时自动连扫补足（显示"已扫 N 页 · 筛后 M 条"，`SearchScreen.kt:173-185`） |
| S-12 | 搜索历史（**M**） | `SearchScreen.kt:211-297`；`data/SearchHistoryStore.kt`（上限 50 条） | 输入为空时展示：点击即搜；清空（确认弹窗）；长按多选批量删除 + 全选/取消（`SearchScreen.kt:88-119,222-254`）——多选部分降 S 可后补，点击/清空为 M。持久化 |
| S-13 | 搜索状态全局保留（**M**） | `SearchStore.kt:26-50`（query/results/page/gridState 切 Tab 不丢） | 结果、页码、滚动位置、筛选状态在返回后保留，不重复请求 |
| S-14 | 超时与错误处理（**M**） | `SearchStore.kt:162-233`（40s 总超时；错误文案区分隧道；旧结果保留 + 顶部细进度条）；`SearchScreen.kt:188-190,299-309,339-348` | M：错误态 + 重试按钮 + "⚠ 点此重试"横幅 + 再次搜索时旧结果不消失（顶部 LinearProgress）；S：40s 硬上限数值可简化为 Http 层超时；隧道专属文案（"正在通过 WARP 隧道搜索…"）裁剪 |
| S-15 | 剪贴板 JM 编号识别（**S**） | uiux §四.(1) 新增；conventions §7 S | 简化（conventions 明确）：进入搜索页时读剪贴板，若匹配 JM 编号格式则**自动填充输入框**即可，不做灵动胶囊弹窗 |
| S-16 | 热门搜索榜 / 多标签语法组合检索（**O**） | uiux §四.(1) 构想（无 API 数据源） | 裁剪：`JmApi` 无热搜/趋势接口（`JmApi.kt:686-708` 仅 search），搜索历史已承担入口职责；`作者:`/`标签:` 语法高亮组合为构想功能，裁剪 |

### 2.6 路由页 B：详情 AlbumDetailPage（20 项）

原 AlbumDetailScreen（`ui/album/AlbumDetailScreen.kt`）。

| 编号 | 功能项（分级） | 原项目依据 | 规格 |
| --- | --- | --- | --- |
| D-01 | 折叠视差头部（**M**） | uiux §四.2 新增（原为普通 SlimTopBar + 平铺头部，`AlbumDetailScreen.kt:207,609-737`） | 背景封面 blur(60)+暗渐变；顶部栏初始透明仅返回/分享/更多，上滑超封面高度后光感渐显单行书名；**不重复显示长书名** |
| D-02 | 封面 + 元数据区（**M**） | `AlbumDetailScreen.kt:614-706` | 左 3:4 封面（`jmApi.albumCoverUrl(aid)`）；右侧：标题两行（长按复制，:652-656）、作者行（点击→搜索该作者 ：676；长按复制 ：677）、车牌号胶囊 `JM{id}`（点击复制 + Toast，:682-697）、统计 ♥likes/👀views（Symbol 图标替代 emoji） |
| D-03 | 复制官方链接（**M**） | `AlbumDetailScreen.kt:657-666` | 顶栏/操作区复制 `https://18comic.vip/photo/{id}` + Toast |
| D-04 | 语言徽章 + 全彩（**M**） | `AlbumDetailScreen.kt:625-640`（封面右上角国旗） | 徽章文本化（中字/日漫/韩漫，uiux）；详情有真实 tags → 移植 `TagStore.remember` 等价判定（tag 命中优先，标题启发式回退，`data/TagStore.kt:39-46`） |
| D-05 | 标签 chips（**M**） | `AlbumDetailScreen.kt:708-735`（≤14 个；点击搜索；已收藏标签高亮） | FlowRow 胶囊：点击 → ROUTE_SEARCH；收藏标签以 `PRIMARY` 系高亮 |
| D-06 | 标签长按收藏/取消（**S**） | `AlbumDetailScreen.kt:236-243`（FavStore.toggleTag + Toast） | 简化保留：长按或编辑入口二选一，写入收藏标签集（联动 B-07） |
| D-07 | CTA 行：主次按钮（**M**） | `AlbumDetailScreen.kt:739-792`（原：开始阅读/下载/评论 三按钮 + 右下收藏 FAB :367-393） | 重构为：主 CTA"开始阅读 / 续读第N话 P.x"（ACCENT 蓝、通栏 55%，有进度时显示续读文案与进度，进入 ROUTE_READER 携带进度）+ 三个等宽次级圆钮：收藏 ♥（微动效）/ 下载 ⬇ / 评论 💬。**移除右下角 FAB**（uiux §四.2） |
| D-08 | 收藏切换（**M**） | `AlbumDetailScreen.kt:367-393`（FavStore.toggle + 已收藏红心态 + Toast） | 切换 FavStore；按钮态/动效反馈；TagStats.onFavorite 联动裁剪（T-01） |
| D-09 | 章节列表（**M**） | `AlbumDetailScreen.kt:272-305`（序号 + 章节名 + 点击进阅读器 + 长按复制章节名） | ListItem：序号 + 标题（空则"第 N 話"，:281）；点击 → ROUTE_READER `{aid, chapterIndex}`；长按复制章节名（S 可简化，按钮/菜单复制） |
| D-10 | 章节正倒序切换 + 状态标识（**M**） | uiux §四.2 新增（原无） | 列表头"章节 (N) ⇅ 正倒序"切换；已读章节置灰、"上次读到 P.x"胶囊标记（数据源 B-03 精确进度）；"连载中/已完结"标识 API 无状态字段，**不做** |
| D-11 | 内容预览：前 8 页胶片条 + 全量 bindSheet（**M**） | `AlbumDetailScreen.kt:307-360`（原 3 列平铺前 60 页，点击直达该页）；uiux §四.2 重构 | 单行横向胶片（前 8 页缩略）+ "查看全部 N 页 ›" → `bindSheet` 半模态 `LazyVGrid`/Grid 全量页（原上限 60 页，可沿用前 60 或全部，注明取前 60 与原一致）；点击任意页 → ROUTE_READER `{aid, chapterIndex:0, page}` |
| D-12 | 预览数据与解码（**M**） | `AlbumDetailScreen.kt:178-199`（第一话 chapterImages + PagesCache + scrambleId + PageLoader targetWidth=360） | 数据：`jmApi.chapterImages(first)` + `jmApi.scrambleId(first)`；列表缓存（PagesCache 等价）；图片走 ImageDecode.ets 链路（反混淆后缩略）；conventions §4 |
| D-13 | 预览缩略图预热（**S**） | `AlbumDetailScreen.kt:192-198`（前 15 页顺序预取，80ms 间隔） | 简化：胶片条可视区 + bindSheet 打开时按需加载即可（LazyForEach），可不做顺序预热 |
| D-14 | 详情缓存秒开 + 失败保留（**M**） | `AlbumDetailScreen.kt:144-175`（AlbumCache 优先 → 网络刷新替换 → 失败保留缓存仅记录日志） | AlbumCache 等价本地缓存；断网可看（有缓存不报错）；无缓存失败 → 错误态 + 重试 |
| D-15 | 浏览历史记录（**M**） | `AlbumDetailScreen.kt:172`（HistoryStore.record，封面用 albumThumbUrl） | 进入详情（加载成功后）写入历史；受 SET-06 开关控制 |
| D-16 | 下载弹窗（**S**） | `AlbumDetailScreen.kt:396-513`（格式/质量摘要 + "以后不再弹出" + 候选选择器 :516-557） | 简化：弹窗摘要显示"格式：CBZ（ZIP 无损存档）+ 图像：解密后原格式"；"以后不再弹出"checkbox 持久化（`downloadRemember`，`AppPrefs.kt:110-115`）；PDF/7z 档位候选择器裁剪（T-09） |
| D-17 | 发起下载入队（**M**） | `AlbumDetailScreen.kt:126-130,483-507`（DownloadQueue.enqueue + Toast 队列数） | DownloadManager.enqueue(task)；Toast"已加入下载队列（当前 N 个）" |
| D-18 | 下载状态行（**M**） | `AlbumDetailScreen.kt:771-791`（排队中/下载中 x/y 失败 n 页/导出中 x/y/已保存路径/失败原因/已取消） | CTA 区下方状态行实时显示；下载中/排队中禁用下载按钮（:756-764） |
| D-19 | 评论入口 + 数量角标（**M** 入口 / **S** 角标） | `AlbumDetailScreen.kt:767-769`（评论按钮） | 入口 → 评论 bindSheet（CM-01）；角标数量需额外请求 `jmApi.comments` 取 total，可后补（S） |
| D-20 | 加载/错误/空态（**M**） | `AlbumDetailScreen.kt:210-227` | 首载 spinner；错误 + 重试；章节为空兜底（`JmApi.album` 无 series 时以自身为单章，`JmApi.kt:457-461`——数据层行为，详情页需兼容展示） |

### 2.7 路由页 B 附：评论抽屉 CommentsSheet（6 项）

原 CommentsScreen（`ui/comments/CommentsScreen.kt`），鸿蒙改为 bindSheet 半模态（uiux §四.(4)，高度约 75%）。

| 编号 | 功能项（分级） | 原项目依据 | 规格 |
| --- | --- | --- | --- |
| CM-01 | 半模态评论抽屉（**M**） | `ui/App.kt:269-278`（原整页覆盖层）；uiux §四.(4) | `bindSheet` 从底部滑出；标题"评论 · {书名截断16字}"（`CommentsScreen.kt:81-84`）；conventions §7 M |
| CM-02 | 评论列表渲染（**M**） | `CommentsScreen.kt:147-210`（昵称/匿名回退、"回复"标记、时间戳格式化 yyyy-MM-dd HH:mm、♥ 点赞数、内容空显"（空）"） | 卡片式列表；HTML 清洗（`<br>`→换行、去标签、实体反转义）由数据层完成（`JmApi.kt:500-507`） |
| CM-03 | 剧透遮罩（**M**） | `CommentsScreen.kt:188-202`（spoiler 评论显示"包含剧透，点按查看"，点击揭示，状态 per-id 记忆） | 磨砂/纯色遮罩 + 点击显示 |
| CM-04 | 评论分页（**M**） | `CommentsScreen.kt:60-78,130-137`（每页约 10 条，pageCount=ceil(total/10)，PageBar 翻页 + "共 N 条 · 第 x 页"） | 数据：`jmApi.comments(albumId, page)`；底部 PageBar；加载中顶部细进度条（:139-141） |
| CM-05 | 空/错/载态（**M**） | `CommentsScreen.kt:85-113`（空"还没有评论"；错误+重试；首载 spinner） | conventions §8 |
| CM-06 | 热门/最新评论筛选（**O**） | uiux §四.(4) 构想 | 裁剪：`/forum` 接口无排序参数（`JmApi.kt:480-498` 仅 mode/aid/page/lang），只读按时间序 |

### 2.8 路由页 C：阅读器 ReaderPage（页面级 1 项 R-00 + 矩阵 28 项见 §3）

原 ReaderScreen（`ui/reader/ReaderScreen.kt`）+ ReaderImage/PageLoader/JmImageDecoder。页面级职责：

| 编号 | 功能项（分级） | 原项目依据 | 规格 |
| --- | --- | --- | --- |
| R-00 | 路由参数与进入定位（**M**） | `ReaderScreen.kt:71-77,95-97,144-166`（albumId/episodes/startIndex/startPage；缓存先显 + scrollToItem） | ROUTE_READER `{aid, chapterId?, chapterIndex?, page?}`；章节列表优先用 AlbumCache（避免重复拉详情）；定位到目标页非阻塞（`requestScrollToList` 等价，:137-140）；续读由 B-03 进度驱动 |

（R-01~R-27 见 §3 阅读器功能矩阵。）

### 2.9 路由页 D：下载管理 DownloadsPage（12 项）

原 DownloadsScreen（`ui/downloads/DownloadsScreen.kt`）+ DownloadQueue（`download/DownloadQueue.kt`）。

| 编号 | 功能项（分级） | 原项目依据 | 规格 |
| --- | --- | --- | --- |
| DL-01 | 任务列表项（**M**） | `DownloadsScreen.kt:224-330`（封面 44×58 + "JM{id} · 标题"两行 + 状态行 + "下载于 yyyy-MM-dd HH:mm" + 进度条） | List 项：封面缩略、标题、状态文案（排队中/下载中 x/y（失败 n 页）/导出中 x/y/已完成·路径/失败：原因/已取消）、创建时间、进度条（运行/排队时；导出阶段按 exportDone/exportTotal，:301-317） |
| DL-02 | 下载引擎：线性队列 + 单本 2 并发（**M**） | `DownloadQueue.kt:202-212`（逐任务 worker）；`:276-311`（Semaphore(2) 并发页下载） | DownloadManager 状态机：等待/下载中/暂停/完成/失败（conventions §4）；2 并发可调为常量 |
| DL-03 | 任务持久化与重启恢复（**M**） | `DownloadQueue.kt:95-112`（downloads.json；重启时 RUNNING/QUEUED → FAILED "已中断（应用重启）"） | 任务列表落盘；恢复语义保留（中断任务标记失败） |
| DL-04 | 页面获取与缓存复用（**M**） | `DownloadQueue.kt:284-306`（①手动下载目录/page_cache 原始字节复用 ②网络换域名重试 3 次）；`util/PageLoader.kt:168-179` cachedRawFile | 下载前先查阅读页缓存（raw 字节）复用；未命中走 `jmApi.fetchBytes(jmApi.imageUrl(..., retry))` 重试；"缓存命中数"可仅记日志 |
| DL-05 | CBZ 导出（**M**） | `DownloadQueue.kt:314-380`（格式分派）；conventions §7 M | CBZ = ZIP（STORE 不压缩 + 自实现 CRC32，conventions §4 DownloadManager.ets 契约）；条目 = **解密（反混淆）后按原始格式**的图片（等价 archiveImgQuality 的"解密后同格式"语义，`DownloadQueue.kt:536-576`）；文件名 `JM{id} {清洗后标题≤80字}.cbz`（:491-494 等价） |
| DL-06 | 缺失页处理（**S**） | `DownloadQueue.kt:460-472,524-535`（PDF 占位页"第 N 页缺失"；压缩包缺页跳过） | 简化：CBZ 内缺失页跳过；完成后 Toast/状态行注明缺失 N 页（不生成占位图，PDF 占位随 PDF 裁剪） |
| DL-07 | 保存位置（**S**） | `DownloadQueue.kt:578-604`（MediaStore Downloads 相对路径）；`AppPrefs.kt:247-252` downloadPath | 简化：保存到应用沙箱下载目录（固定），任务完成后提供"保存到用户所选位置"（系统保存选择器）入口；自定义相对路径设置裁剪（SET-09 简化版） |
| DL-08 | 长按多选 + 全选 + 批量删除（**M**） | `DownloadsScreen.kt:64-91,162-182`（选择态顶栏"已选 N 项"、全选/取消全选、底部"删除所选/完成"） | 同款交互 |
| DL-09 | 删除确认 + 可选删文件 + 强制终止（**M**） | `DownloadsScreen.kt:186-221`（确认弹窗、"同时删除原始文件"checkbox 默认不勾、进行中任务强制终止并清理临时文件）；`DownloadQueue.kt:148-158` | 删除记录（默认）/同时删文件；RUNNING/QUEUED 删除 = 取消 + 清理临时目录 |
| DL-10 | 打开位置 / 分享（**S**） | `DownloadsScreen.kt:124-152`；`DownloadQueue.kt:161-190`（folderIntent/viewFileIntent/shareIntent 三级回退） | 简化：已完成任务提供"打开/预览文件"（系统打开方式，MIME 按格式）+ 系统分享；"打开文件夹位置"系统差异大，可只做打开文件 |
| DL-11 | 空态（**M**） | `DownloadsScreen.kt:98-105` | "还没有下载任务～ 去详情页点「下载」生成 CBZ 吧"（原文案含 PDF，改 CBZ） |
| DL-12 | 前台通知进度 + 通知点击跳转（**O**） | `download/DownloadService.kt`；`util/NavSignals.kt`（openDownloads 信号）；README v0.4.1 | 裁剪：实况窗/悬浮窗下载进度（conventions §7 O，页面内进度替代）；通知点击跳转随通知一起裁剪 |

---

## 3. 阅读器功能矩阵（R-01 ~ R-28，逐项）

原实现基线：`ui/reader/ReaderScreen.kt`（507 行）。原阅读器为**常驻顶栏**（SlimTopBar）+ 两种模式 + 双指缩放，**无 HUD、无点按热区、无进度滑条、无亮度控制、无进度持久化**——这些在鸿蒙版为新增（依据 uiux §四.3 与 conventions §7 M）。

| # | 能力项 | 原项目行为（依据） | 鸿蒙规格 | 分级 |
| --- | --- | --- | --- | --- |
| R-01 | 纵向条漫模式 | 默认模式；LazyColumn 连续滚动 + `ContentScale.FillWidth`（`ReaderScreen.kt:384-407`） | `List` + LazyForEach + `cachedCount(5)`；FillWidth 逐页 | **M** |
| R-02 | 横向翻页模式 | HorizontalPager + fitScreen（`ReaderScreen.kt:302-337`） | Swiper/List 横向；fitScreen 单页适配 | **M** |
| R-03 | 模式切换 + 全局记忆 | 顶栏文字按钮"横向/纵向"（`ReaderScreen.kt:260-271`；`AppPrefs.kt:254-259` readerHorizontal） | HUD"阅读模式"按钮；模式枚举扩展为 纵向/横向/日漫右翻/双页（S-级后两档见 R-04/05）；选择持久化（Prefs.ets） | **M**（枚举含 4 档，后 2 档 S） |
| R-04 | 日漫右→左翻页 | 无（原仅横向 LTR pager） | 保留模式枚举与切换（RTL 翻页方向）；渲染与横向模式相同 | **S**（conventions §7：保留枚举与切换即可） |
| R-05 | 双页拼合（平板/折叠屏） | 无 | 保留模式枚举；md/lg 断点可启用双页并排渲染 | **S**（渲染可后补，conventions §7） |
| R-06 | 点按热区 | 无点按翻页（纵向滚动模式无热区） | 屏幕三分热区：中央=HUD 显隐；左/右（或上/下）=上/下一页；日漫模式自动镜像；横向模式点按翻页 | **M**（conventions §7） |
| R-07 | HUD 顶栏 | 常驻 SlimTopBar：返回 + 话标题 + 缩放重置 + 模式 + 页码 x/y（`ReaderScreen.kt:238-281`） | 浮动 Top HUD（光感模糊）：返回 + 话标题（空则"第 N 話"）+ 模式胶囊 + 页码；中央点按切换显隐（弹簧动画 200ms，uiux §五.3） | **M** |
| R-08 | HUD 底栏：进度滑动条 | 无滑条（仅页码文字） | Bottom HUD：Slider（当前页/总页，显示 `1/174`）拖动实时跳页；两端"上一话/下一话"按钮 | **M** |
| R-09 | 滑条缩略图预览 | 无 | 拖动时滑块上方悬浮目标页小图 | **S**（可后补，先文字页码气泡） |
| R-10 | HUD 四大金刚控制栏 | 无（仅模式切换 + 重置） | 目录 / 阅读模式 / 画面调节 / 设置 四按钮（uiux §四.3） | **M**（按钮与入口 M；各弹层内容按 R-11/R-12/R-15/R-16 分级） |
| R-11 | 章节目录半模态 | 无（切章需退出到详情页） | 目录按钮 → bindSheet 章节列表（复用 D-09/D-10 组件），点击切换章节 | **M** |
| R-12 | 画面调节（亮度） | 无 | HUD 画面调节弹层：应用内遮罩亮度滑条 + 记忆（Prefs.ets 亮度值） | **S**（conventions §7：只调应用内遮罩亮度） |
| R-13 | 夜间反相/护眼滤镜 | 无（跟随主题背景色 surface） | 阅读背景深黑 `READER_BG #0D0D0D`（M）+ 纸质米黄可选 | 背景 **M**（黑）；米黄 **S**；夜间反相 **O**（无原实现，滤镜属增强） |
| R-14 | 智能裁白边 / 超分增强 | 无 | — | **O**（无原实现，纯增强构想） |
| R-15 | 自动翻页 / 音量键翻页 | 无 | — | **O**（conventions 未列；音量键监听在 ArkUI 常规能力外） |
| R-16 | 阅读器内设置面板 | 无（设置在设置页） | HUD 设置按钮 → 弹层含：预加载页数（S，SET-22）、背景色（R-13）、亮度重置 | 入口 **M**；项内含 S/O 见各自 |
| R-17 | 微型常驻页码胶囊 | 无（HUD 常驻所以总有页码） | HUD 隐藏时右下角低透明度 `第N话 · x/y` 胶囊（可在设置关闭，uiux §四.3） | **M** |
| R-18 | 章节切换：尾部"上一章/下一章" | 纵向模式列表尾"—— 本章完 ——" + 上一章/下一章按钮（边界隐藏）（`ReaderScreen.kt:409-431`） | 纵向滚动尾部保留同款；横向模式滑到边界给切换提示 | **M** |
| R-19 | 章节切换：HUD 快捷上一话/下一话 | 无（HUD 不存在） | Bottom HUD 两端按钮（R-08） | **M**（并入 R-08） |
| R-20 | 续读（进入定位）+ 进度保存 | 无持久化：currentPage 仅内存（`ReaderScreen.kt:103`）；startPage 仅来自详情预览点击（`AlbumDetailScreen.kt:343`） | 进入时读 B-03 精确进度定位 `{chapterIndex, page}`；翻页/切章/退出写入 Store | **M**（conventions §7"续读保存"） |
| R-21 | 恒预加载后 5 页 | prefetchAhead：当前页+1..+5 去重入队（`ReaderScreen.kt:120-134`）；纵向靠 firstVisibleItemIndex、横向靠 pager currentPage 触发（:229-236,309-316） | List/Swiper `cachedCount(5)` + 显式预取当前+5；去重集合保留 | **M** |
| R-22 | 下一章预加载 | 下一章 chapterImages（缓存优先）+ scrambleId + 前 5 页 PageLoader（`ReaderScreen.kt:211-225`）；受 autoCache 开关（:88,121-123） | 同款：下一章目录 + 前 5 页后台预载；受 SET-05 自动缓存开关控制 | **M** |
| R-23 | 章节目录缓存秒开 + 失败保留 | PagesCache 先显 → 网络刷新（变化才替换）→ 失败且无缓存才报错（`ReaderScreen.kt:156-199`） | PagesCache 等价；"先撤 loading 再滚屏"防死锁经验保留（:177-182 注释） | **M** |
| R-24 | 图片解码链路 | PageLoader：原图字节（手动下载>页缓存>网络换域 3 次）→ **原尺寸反混淆** → 缩放到目标宽（`util/PageLoader.kt:56-123`）；反混淆算法 `data/JmImageDecoder.kt:22-66`（分段数=md5 不带扩展名规则）；内存 LRU 96MB、磁盘 512MB 自动清理、并发上限（:30-58,181-197） | ImageDecode.ets 忠实移植 segments+decode（conventions §4）；"先解密再缩放"铁律保留；页缓存 + 磁盘上限清理保留；并发由系统管 | **M**（算法）；缓存清理 **M**；并发调节 **O**（T-07 附） |
| R-25 | 单页三态：加载/失败/成功 | Loading 灰底 spinner；Failed 点按重试（"自动切换线路"）；Done 图片（`ReaderScreen.kt:440-507`） | 三态保留；失败点按重试 M；自动换图床域名轮换（`JmApi.kt:564-578` nextImageHost）保留为 S（镜像内多图床域名取模轮换，简化不做出错降级统计） | 三态 **M**；换域轮换 **S** |
| R-26 | 双指缩放 1x~5x + 边界限制 + 双击 2x | 纵向模式：transformable 手势 scale∈[1,5]、pan 边界 clamp、双击 2x/还原、顶栏"1.6x · 重置"按钮（`ReaderScreen.kt:104-118,339-382,246-259`） | 双指缩放 + 平移边界回弹（PinchGesture + PanGesture）；双击放大可简化（conventions §7）；缩放重置入口保留 | **S**（双击/重置可简化，缩放本体保留） |
| R-27 | 全屏沉浸 + 安全区 | windowInsetsPadding(systemBars)（非沉浸，`ReaderScreen.kt:238-242`） | expandSafeArea 全屏 + 深色背景 + 状态栏浅色图标（conventions §3） | **M** |
| R-28 | 打开原网页 / 本页书签 / 截图分享 | 无 | — | **O**（依赖被裁剪的浏览器/隧道；书签分享无原实现） |

---

## 4. 设置项全清单（45 项）

来源：`ui/settings/SettingsScreen.kt`（全部条目）+ `util/AppPrefs.kt`（全部键，行号即键定义）。新 IA 重组进"我的"页分组。

### 4.1 外观

| 编号 | 设置项 | 原键/默认（AppPrefs.kt） | 鸿蒙去向 | 分级 |
| --- | --- | --- | --- | --- |
| SET-01 | 主题：跟随系统/浅色/深色 | ThemePrefs（`util/ThemePrefs.kt`；`SettingsScreen.kt:912-945` 弹窗） | 我的→外观；Prefs.ets `themeMode` | **M** |
| SET-02 | 阅读器默认模式（纵向/横向/日漫右翻/双页） | `readerHorizontal`（:254-259，布尔） | 我的→阅读偏好；扩展为枚举（R-03） | **M** |
| SET-03 | 亮度记忆 | 无（新增） | 我的→阅读偏好（R-12） | **S** |

### 4.2 阅读与通用

| 编号 | 设置项 | 原键/默认 | 鸿蒙去向 | 分级 |
| --- | --- | --- | --- | --- |
| SET-04 | 随机推荐每页数量（12/24/36/48，默认 24） | `randomPageSize`（:212-217；`SettingsScreen.kt:947-982`） | 我的→通用；仅在采用 E-07 方案 B（独立随机页）时有效；方案 A 下裁剪 | **S** |
| SET-05 | 自动缓存（阅读时缓存图片） | `autoCache`（:9-13，默认 true；`SettingsScreen.kt:308-331`） | 我的→缓存；控制 R-21/R-22 预载落盘与 PageCache 写入 | **M** |
| SET-06 | 记录浏览历史开关 | `historyEnabled`（:226-231，默认 true；`SettingsScreen.kt:287-306`） | 我的→通用；联动 D-15/B-11 | **M** |
| SET-07 | 屏蔽标签（多关键词管理：添加/删除/列表预览） | BlockTagsStore（`data/BlockTagsStore.kt`；`SettingsScreen.kt:1089-1140` 弹窗） | 我的→通用；命中标题/作者/分类/子分类隐藏（E-06 简化口径） | **S** |
| SET-08 | 预加载页数 | 无（原固定 5） | 我的→阅读偏好（conventions §4 Prefs 提及"预加载页数"） | **S** |

### 4.3 缓存

| 编号 | 设置项 | 原键/默认 | 鸿蒙去向 | 分级 |
| --- | --- | --- | --- | --- |
| SET-09 | 清除缓存（图片+详情，二次确认） | `SettingsScreen.kt:984-1007`；`util/StorageUtil.kt` clearCache | 我的→缓存；conventions §7 M | **M** |
| SET-10 | 已用缓存统计（大小+文件数+刷新） | devMode 限定（`SettingsScreen.kt:333-349`） | 随开发者模式裁剪；可保留纯大小展示 | **O**（T-07） |

### 4.4 下载

| 编号 | 设置项 | 原键/默认 | 鸿蒙去向 | 分级 |
| --- | --- | --- | --- | --- |
| SET-11 | 我的下载入口（N 个任务） | `SettingsScreen.kt:359-365` | 我的→下载；= P-02 | **M** |
| SET-12 | 下载格式：PDF/ZIP/7z/tar.gz（默认 pdf） | `downloadFormat`（:74-80） | 固定 **CBZ(ZIP)**；PDF→O（T-09）、7z→O（T-09）、tar.gz→O | **S**（只留 CBZ 时 UI 不再需要选择器，可整项隐藏） |
| SET-13 | PDF 图像质量（visual/max/compact） | `pdfPreset`（:117-122） | — | **O**（随 PDF 裁剪，T-09） |
| SET-14 | 压缩级别（储存~极限 6 档，默认 3） | `archiveLevel`（:82-87） | CBZ 用 STORE 固定 | **O** |
| SET-15 | 压缩包图像质量（visual/lossless/compact/raw） | `archiveImgQuality`（:68-73） | 固定"解密后按原始格式"（DL-05） | **S**（不做档位选择） |
| SET-16 | 压缩包密码（7z：none/fixed/random + 固定密码 + 随机策略 append/twolevel） | `archivePwdMode`/`archiveFixedPwd`/`archivePwdStrategy`（:89-108） | — | **O**（7z 专属，T-09） |
| SET-17 | 下载弹窗"以后不再弹出" | `downloadRemember`（:110-115） | 我的→下载（D-16 联动） | **S** |
| SET-18 | 下载保存位置（Download 相对路径，4 预设+自定义） | `downloadPath`（:247-252；`SettingsScreen.kt:1009-1048`） | 简化为固定应用目录 + 保存选择器导出（DL-07） | **S** |

### 4.5 数据

| 编号 | 设置项 | 原键/默认 | 鸿蒙去向 | 分级 |
| --- | --- | --- | --- | --- |
| SET-19 | 导出数据（.json；勾选 收藏含标签/历史含搜索历史/系统配置） | `util/DataTransfer.kt`；`SettingsScreen.kt:1142-1184` | 我的→数据；conventions §7 M"数据 JSON 导出" | **M** |
| SET-20 | 导入数据（选择 .json → 描述信息 → 勾选合并导入） | `SettingsScreen.kt:1186-1226`（合并式、向下兼容） | 我的→数据；合并语义（同 id 收藏去重、历史保较新时间，`FavStore.kt:119-141`/`HistoryStore.kt:74-92`） | **S**（保留；文件选择与解析可后补） |

### 4.6 镜像与网络（新增分组，conventions §7 M 基线）

| 编号 | 设置项 | 原键/默认 | 鸿蒙去向 | 分级 |
| --- | --- | --- | --- | --- |
| SET-21 | 当前镜像域名切换 | 无 UI（原域名池自动故障切换，`data/JmApi.kt:157-168,320-368`；FALLBACK_DOMAINS :80-86） | 我的→镜像与网络：域名候选列表 + 手动选择（conventions §4 util/Http.ets"域名/镜像从 Prefs 读取，可切换"） | **M** |
| SET-22 | 镜像测速（一键测全部候选域名延迟、按延迟排序） | 原无 UI（图片域名测速 `JmApi.kt:647-678` 为后台行为） | 我的→镜像与网络；结果供 E-02 延迟灯与默认镜像 | **M** |
| SET-23 | 接口诊断信息展示（当前域名/图片域名/接口版本） | devMode"接口信息"（`SettingsScreen.kt:512-517`；`JmApi.debugInfo()`） | 并入镜像分组（只读展示） | **S** |

### 4.7 隐私（新增分组）

| 编号 | 设置项 | 原键/默认 | 鸿蒙去向 | 分级 |
| --- | --- | --- | --- | --- |
| SET-24 | 生物识别应用锁（指纹/面容，失败回退开关） | 无（uiux §四.(5) 新增） | 我的→隐私；`@ohos.userIAM.userAuth` 简版（conventions §1/§7 S） | **S** |
| SET-25 | 隐私模式（数据存应用私有目录） | `privacyMode`（:138-143，默认 true） | 鸿蒙应用沙箱天然私有目录，等价默认成立 | **O**（无需开关） |
| SET-26 | 多任务快照模糊遮罩 | 无（uiux §四.(5) 构想） | — | **O**（稳定 API 集外；应用锁已覆盖防窥主诉求） |

### 4.8 诊断与实验（原 devMode 区）

| 编号 | 设置项 | 原键/默认 | 鸿蒙去向 | 分级 |
| --- | --- | --- | --- | --- |
| SET-27 | 开发者模式开关（连点"关于·禁漫姬"5 次） | `devMode`（:219-224；`SettingsScreen.kt:879-899`） | — | **O**（T-07） |
| SET-28 | 日志级别（NONE~VERBOSE，默认 ERROR） | `logLevel`（:15-20） | 固定 ERROR 落盘（X-07） | **O** |
| SET-29 | 运行日志路径展示 | `SettingsScreen.kt:504-511` | crash.log 保留 | **O** |
| SET-30 | 模拟崩溃自测（双击随机崩溃） | `util/CrashTester.kt`；`SettingsScreen.kt:73-86,520-529` | — | **O**（T-07） |
| SET-31 | SNI 切片 + 切片参数（位置/间隔） | `sniSplit/sniSplitPos/sniSplitDelay`（:23-39） | — | **O**（隧道子系统，T-04） |
| SET-32 | SNI 绕过（置空） | `sniBypass`（:41-45） | — | **O**（同上） |
| SET-33 | DoH 模式（off/system/enhanced/strict）+ DoH 地址模板 + 测试按钮 | `dohMode/dohUrl`（:192-204）；`SettingsScreen.kt:1228-1270,1704-1745` | — | **O**（同上） |
| SET-34 | ECH 开关 | `echEnabled`（:206-210） | — | **O**（同上） |
| SET-35 | 清除 DNS 缓存 | `SettingsScreen.kt:604-613` | — | **O**（同上） |
| SET-36 | 隧道模式 WARP/Tor + Tor 插件检测/启停/网桥配置 | `tunnelMode/torBridges`（:54-66）；`SettingsScreen.kt:630-685,1310-1352` | — | **O**（Tor/WARP/MASQUE/DOH 子系统整体裁剪，conventions §7 O） |
| SET-37 | 隧道状态开关/启动自动连接/传输模式（auto/quic/tcp）/隧道 SNI 列表/一键注册 WARP/导入·修改·导出配置/通道测试/隧道流量清零 | `masqueAutoStart/masqueTransferMode/masqueSnis/masqueLastGood`（:145-190）；`SettingsScreen.kt:686-851` | — | **O**（同上，共 9 个子项计 1 条） |
| SET-38 | 实时状态浮标开关（HUD） | `hudEnabled`（:131-136） | — | **O**（隧道 HUD 裁剪，T-05；E-02 延迟灯无需开关或并入镜像组） |
| SET-39 | 图片并发数（0=自动，1..512） | `imgConcurrency`（:124-129）；`SettingsScreen.kt:1477-1507` | 系统 Image 自管 | **O** |
| SET-40 | HTTP/2 实验开关 | `apiHttp2`（:47-52） | — | **O**（底层协议实验，`@ohos.net.http` 自管） |
| SET-41 | 浏览器网络模式/浏览器禁截屏 | `browserNetMode/browserSecure`（:171-184，浏览器遗留键） | — | **O**（浏览器死代码，T-03） |

### 4.9 关于

| 编号 | 设置项 | 原键/默认 | 鸿蒙去向 | 分级 |
| --- | --- | --- | --- | --- |
| SET-42 | 版本号 + 标语 | `SettingsScreen.kt:879-899` | 我的→关于 | **M** |
| SET-43 | 免责声明 | `SettingsScreen.kt:901-908` | 我的→关于 | **M** |
| SET-44 | 收藏排序记忆 | `favSort`（:233-238） | 书架（B-05/B-13） | **M** |
| SET-45 | 历史排序记忆 | `historySort`（:240-245） | 书架（B-09/B-13） | **M** |

---

## 5. 原项目有、新 IA 无安放位置的界面处置（10 条）

| 编号 | 界面/能力 | 原依据 | 处置建议 | 分级 |
| --- | --- | --- | --- | --- |
| T-01 | 标签词云 TagCloudScreen | `ui/cloud/TagCloudScreen.kt:35-94`（TagStats.topTags(80) 字号随频次缩放、三色轮换、点击搜索；数据源 `data/TagStats.kt`） | **裁剪（O）**：收藏标签 chips（B-07）+ 分类自定义 tag（C-04）已提供同类入口，词云无独立信息增量；其数据源 TagStats（阅读/收藏/下载打点，`AlbumDetailScreen.kt:129,243,251` 等）仅词云消费，一并裁剪。若评审要求保留 → **降 S 并入书架收藏段顶部**：等字号 chips 按频次降序（去掉字号缩放/三色），点击进搜索 | **O**（备选 S） |
| T-02 | 随机推荐独立页 RandomScreen | `ui/random/RandomScreen.kt`（大池去重合并、单次洗牌顺序分页、PageBar、作者点击搜索） | **合并进发现页**（E-05/E-07）：区块+换一批为 M；独立页与其分页洗牌为 S 备选（方案 B） | 合并 **M** / 独立页 **S** |
| T-03 | 内置浏览器 BrowserScreen | `ui/browser/BrowserScreen.kt`（818 行：WebView 常驻、请求拦截走 WARP/DoH、用户脚本 GM_*、收藏/下载/历史/脚本四模式、禁截屏） | **不复刻（O）**：原项目 v0.8.4 已自行移除（README:113"移除内置浏览器（不再维护）"）；本会话 grep 验证 App.kt/SettingsScreen/MainActivity 对 BrowserScreen **0 处引用**（死代码），且其核心价值（隧道内浏览）随隧道子系统裁剪 | **O** |
| T-04 | 启动门控 StartupGateScreen | `ui/App.kt:107-117,322-366`（隧道自动连接时先连后载，失败可重试/跳过直连） | **裁剪（O）**：隧道子系统整体裁剪（conventions §7 O），鸿蒙版启动即直连镜像，无门控页 | **O** |
| T-05 | 隧道实时 HUD TunnelHud | `ui/components/TunnelHud.kt:29-70`（延迟/速度/累计流量，点击详情 Toast） | **裁剪（O）**；其"顶栏实时状态"位置由 **镜像延迟灯（E-02，M）** 替代，数据源改为镜像测速 | **O**（替代物 M 见 E-02） |
| T-06 | 崩溃提示页 CrashActivity | `ui/CrashActivity.kt:37-118`（独立进程 :crash、自动复制崩溃信息、反馈引导、退出按钮） | **裁剪独立进程页（O）**；按 conventions §7 保留"最简全局错误兜底 + crash 日志文件"（X-07，M） | **O**（兜底 M 见 X-07） |
| T-07 | 开发者模式及其诊断/自测区 | `SettingsScreen.kt:520-529,879-899`（连点 5 次、模拟崩溃、日志级别、运行日志、接口信息、已用缓存） | **裁剪（O）**：调试向能力非用户主流程；接口信息并入镜像分组只读展示（SET-23，S） | **O** |
| T-08 | TagStore 后台标签校准（enrich） | `data/TagStore.kt:48-70`（列表滚动时静默拉 /album 详情校准国旗/全彩/屏蔽，2 并发） | **裁剪（O）**：其收益（国旗/全彩更准、屏蔽更全、顺带预热详情）在鸿蒙版由"详情页 remember（D-04，M）+ 标题启发式（E-12，S）"承接大部分；列表级后台全量拉详情成本高（每个列表项一次 /album 请求），首版不做 | **O** |
| T-09 | PDF / 7z / tar.gz 导出及全部档位设置 | `util/PdfWriter.kt`、`util/ArchiveWriter.kt`、`DownloadQueue.kt:327-380`、SET-13/14/16 | **裁剪（O）**：conventions §7 明确"PDF 导出"裁剪、下载只保 CBZ；7z AES-256/加密文件名/二级压缩包与 tar.gz 同属多格式导出，一并裁剪（多格式 = 自研压缩器 ×3 的维护成本，CBZ 已覆盖"离线可读+通用阅读器兼容"主诉求） | **O** |
| T-10 | 通知栏下载进度 + 通知点击跳转 | `download/DownloadService.kt`（前台通知）、`util/NavSignals.kt`（openDownloads） | **裁剪（O）**：实况窗/悬浮窗进度为 conventions §7 O，页面内进度（DL-01/D-18）替代；通知点击跳转随通知裁剪 | **O** |

---

## 6. 数据依赖速查与契约缺口（给主控/工程师）

### 6.1 JmApi 方法 → 消费屏（原 `data/JmApi.kt`）

| 方法（原行号） | 消费屏 |
| --- | --- |
| `random()`（:408） | 发现-随机区块 E-05 |
| `latest(page)`（:413） | 发现-最新 E-08 |
| `ranking(category, order, page)`（:418） | 发现-榜单 E-03/04、分类详情 C-02 |
| `categories()`（:430） | 分类列表 C-01 |
| `album(albumId)`（:446） | 详情 D、收藏添加 B-06、下载 DL-02、阅读器 R-00 |
| `chapterImages(photoId)`（:474） | 详情预览 D-12、阅读器 R-23、下载 DL-02 |
| `scrambleId(photoId)`（:512） | 预览/阅读器/下载（反混淆参数） |
| `comments(albumId, page)`（:480） | 评论抽屉 CM |
| `search(query, page, order, time, year, month)`（:686） | 搜索 S |
| `imageUrl/albumCoverUrl/albumThumbUrl`（:614-623） | 全部封面/阅读页 |
| `fetchBytes(url)`（:635） | 下载 DL-04、PageLoader R-24 |

### 6.2 Store/工具 → 消费屏

HomeCache（发现秒开）、CategoryStore+CustomCatStore（分类）、SearchStore（搜索全局态）、FavStore（书架收藏+标签）、HistoryStore（浏览历史）、精确阅读进度 Store（**新增**，B-03）、SearchHistoryStore（S-12）、AlbumCache（详情/阅读器）、PagesCache（章节页列表）、DownloadManager=DownloadQueue（下载）、ImageDecode.ets=JmImageDecoder+PageLoader（R-24/D-12）、BlockTags 屏蔽词（E-06/SET-07）、Prefs.ets=AppPrefs（§4）。

### 6.3 契约缺口（conventions §4 未覆盖、需主控裁决）

1. **屏蔽词（BlockTags）与自定义分类（CustomCat）与收藏标签（favTags）**：conventions §4 Stores.ets 契约仅列收藏/阅读历史/搜索历史——按本文分级分别为 S/S/M，需要数据层补契约或由页面用 Prefs.ets 自管 JSON。
2. **TagStats**：词云裁剪（T-01）后无消费方，建议不实现。
3. **镜像测速与切换**（SET-21/22，M）：conventions 仅在 util/Http.ets 提及"域名/镜像从 Prefs 读取，可切换"，测速方法与结果结构需数据层补契约。
4. **图片 CDN 多域名轮换**（R-25 S 级简化）：`imageUrl retry` 语义需在 JmApi.ets 保留。
5. **评论 HTML 清洗**：应在 jmApi.comments 解析层完成（原 `JmApi.kt:500-507`）。

### 6.4 明确不做（防"假功能"）

- 热门搜索榜/趋势（无 API）；"飙升榜"分段（无参数）；连载中/已完结状态（无字段）；章节搜索（无 API，原项目也没有）；评论排序（无参数）；书架"有更新"红点（无更新检测接口）。
- WebDAV 云同步、本地 CBZ 导入：uiux §三 提及但 conventions §7 明确 O（WebDAV）/ O（本地 CBZ 导入），本文不为其立条。

---

*统计（已用脚本核对）：功能项总数 = X8 + E16 + C8 + B13 + P4 + S16 + D20 + CM6 + R29（R-00 + R-01~R-28）+ DL12 + SET45 + T10 = **187**；首标记分级 M 110 / S 40 / O 37。*
