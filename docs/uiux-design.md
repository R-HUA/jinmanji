# HarmonyOS 7 漫画 App 全量页面 UI/UX 重构与架构设计方案

本方案基于现有漫画 App 的三张核心界面截图（发现首页、漫画详情页、阅读器页），结合 [HarmonyOS 鸿蒙设计规范与指南](https://developer.huawei.com/consumer/cn/design/)、[HarmonyOS 7 新能力特性（API 26）](https://developer.huawei.com/consumer/cn/features/)、[UI Design Kit 沉浸光感材质](https://developer.huawei.com/consumer/cn/doc/HarmonyOS-Guides/ui-design-hds-component-material) 以及 [HarmonyOS 多设备开发最佳实践](https://developer.huawei.com/consumer/cn/best-practice/multidevice/)，对全量页面（不局限于现有截图页面）进行系统性的 UI/UX 重构与 ArkUI 工程架构设计。

---

## 一、 现有界面痛点深度诊断（基于截图逐帧剖析）

在对现有三张界面截图进行视觉层级、交互路径与性能开销评估后，当前版本主要存在以下核心痛点：

| 页面名称 | 对应截图 | 视觉与排版痛点 | 交互与架构痛点 |
| :--- | :--- | :--- | :--- |
| **发现首页** | 图 1 (`3491.jpg`) | 1. 顶部标题区被状态栏裁剪遮挡，且存在突兀的双色分割细条。<br>2. “随机推荐”与“热门排行”封面图加载空白，缺乏骨架屏（Skeleton）与渐进式淡入。<br>3. 封面右上角圆形国旗角标（🇨🇳/🇯🇵）贴图感生硬，缺乏圆角徽章融合。<br>4. 卡片底部标题文字截断且存在重影/乱码堆叠。 | 1. 中部“分类速览”胶囊栏与底部导航栏的“分类”Tab 职能重复。<br>2. 底部导航栏包含 5 个平级入口（发现、分类、搜索、收藏、设置），“搜索”占据独立一级 Tab 造成导航冗余。<br>3. 底部栏采用纯色死板背景，未适配 [沉浸光感开发指导](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-immersive-light-sense-development) 的半透明模糊材质。 |
| **漫画详情页** | 图 2 (`3492.jpg`) | 1. 顶部返回栏直接复制超长书名（`出租女友/租借女友/...`），与正文标题完全重复，浪费首屏黄金空间。<br>2. 作者、作品 ID（`JM1197606`）、红心与浏览量 Emoji（❤️ `10591` · 👀 `55039`）平铺堆砌，缺少信息分组。<br>3. 按钮视觉权重倒置：“下载”使用了最显眼的深蓝实心主色，而核心主行动点（CTA）“开始阅读”却采用浅紫弱化样式。 | 1. 右下角悬浮的心形收藏按钮（FAB）遮挡了下方漫画预览图，且与顶部操作区割裂。<br>2. 章节列表（`章节 (1)`）过于单薄，缺少正倒序切换、卷/话分组、阅读进度高亮。<br>3. 底部直接平铺“内容预览（前 60 页）”三列网格，导致详情页无限拉长，首屏一次性请求过多图片极易引发卡顿与流量浪费。 |
| **阅读器页** | 图 3 (`3493.jpg`) | 1. 顶部常驻白底导航栏（`← 第 1 話`、`横向 1/174`），严重破坏全屏漫画阅读的沉浸感。<br>2. 底部未延伸至系统导航条（Home Indicator）安全区，画面上下割裂。 | 1. 缺乏单击画面中央唤出/收起的浮动控制栏（HUD）。<br>2. 右上角仅靠纯文字“横向”切换阅读模式，缺少直观的进度滑动条（Slider）、章节快速跳转、双页拼合（平板/折叠屏）、画面裁边及预加载状态反馈。 |

---

## 二、 HarmonyOS 7 (API 26) 核心设计规范赋能体系

在重构过程中，全面引入 HarmonyOS 7 原生设计语言与底层渲染能力，建立四大设计支柱：

### 1. 沉浸光感材质体系（Immersive Light Sense）
* **空间材质与动态高光**：依据 [UI Design Kit (HDS 组件材质)](https://developer.huawei.com/consumer/cn/doc/HarmonyOS-Guides/ui-design-hds-component-material) 与 [沉浸光感开发指导](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-immersive-light-sense-development)，在顶部导航栏（`HdsNavigation`）、底部悬浮导航栏（`HdsTabs`）及阅读器控制面板中，应用 `uiMaterial` 与 `ImmersiveStyle`。当漫画封面或内页滚过导航栏底部时，材质层实时呈现半透明高斯模糊、色彩漫反射与微光边缘。
* **算力分级与优雅降级**：参照 [沉浸光感常见问题](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-immersive-light-sense-faq)，通过监听设备算力等级与 `uiMaterial.MaterialState`，在旗舰设备上开启实时动态光感与高光折射，在中低功耗或省电模式下自动降级为静态磨砂背板（`BlurStyle.Thin`），兼顾精致视效与 120Hz 满帧流畅度。

### 2. 全屏沉浸式与安全区延展（Edge-to-Edge Immersive）
* **全画幅视窗**：全局启用 `window.setWindowLayoutFullScreen(true)`，并使用 `.expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])` 将背景与滚动流延伸至状态栏与底部小白条区域。
* **动态状态栏反色**：在漫画详情页顶部高斯模糊封面区与暗色阅读器画布中，自动切换系统状态栏图标为浅色；在浅色背景滚动收起后平滑过渡为深色。

### 3. “一多”响应式与多端自适应架构（Single-Source Multi-Device）
遵循 [HarmonyOS 多设备开发最佳实践](https://developer.huawei.com/consumer/cn/best-practice/multidevice/) 与 [页面布局场景指南](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/typical-layout-scenario-V5)，针对直板手机、双折叠屏（Mate X 系列）、三折叠屏（Mate XT）及平板（MatePad）建立统一断点规范：

| 断点标识 | 屏幕宽度范围 | 典型设备形态 | 导航栏形态 (`Tabs` / `Navigation`) | 推荐/书架网格列数 | 详情页与阅读器布局策略 |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **sm** | `< 600vp` | 直板手机竖屏 | 底部悬浮光感 `HdsTabs`（4 栏） | 3 列标准卡片 / 2 列瀑布流 | 单栏流式详情页；单页竖向条漫或左右翻页 |
| **md** | `600vp - 840vp` | 折叠屏展开态 / 手机横屏 | 左侧垂直 `SideBar` 或底部紧凑胶囊栏 | 4 列卡片网格 | 详情页采用 `NavigationMode.Split` 双栏（左信息+右章节/预览）；阅读器支持双页并排（日漫模式） |
| **lg / xl** | `>= 840vp` | 平板横屏 / 三折叠全展开 / PC | 左侧常驻展开导航栏 + 顶部全局搜索栏 | 5 - 6 列卡片网格 | 详情页三区布局（左封面元数据、中章节与预览、右常驻评论流）；支持 [HarmonyOS 7 标准悬浮窗](https://developer.huawei.com/consumer/cn/features/) 与自由多窗分屏 |

### 4. 引力动效与一镜到底转场（Gravity Motion & Shared Element）
* **封面共享元素一镜到底**：遵循 [HarmonyOS 设计理念](https://developer.huawei.com/consumer/cn/design/concept/) 与 [动效设计指南](https://developer.huawei.com/consumer/cn/doc/design-guides/design-animation-overview-0000001750985338)，使用 `geometryTransition("manga_cover_" + mangaId)` 配合弹簧物理曲线（`curves.springMotion(0.35, 0.8)`），实现从“发现页卡片封面”到“详情页海报”，再到“阅读器第 1 页”的无感放大过渡。

---

## 三、 全量页面信息架构（IA）重塑

为解决现有 5 栏底部导航的功能重叠问题，将原本独立的“搜索”整合进首页顶栏与全局快捷键，并将“收藏”升级为功能完备的“书架”，形成 **4 大核心一级 Tab + 8 大全场景核心页面** 的完整架构：

* **一级导航层（Main Shell）**
  * **Tab 1：发现（Explore）** —— 个性化推荐、随机漫游、热门榜单、新番速递、顶部全局搜索框（支持 ID 车牌直达）。
  * **Tab 2：分类（Category）** —— 题材频道矩阵、多维交叉筛选器（地区/类型/状态/排序）、专题合集。
  * **Tab 3：书架（Bookshelf，由原“收藏”升级）** —— 我的收藏、阅读历史（带精确页码续读）、离线下载队列管理、本地导入（CBZ/ZIP/PDF）。
  * **Tab 4：我的（Profile & Settings，由原“设置”升级）** —— 账号与 WebDAV 云同步、分流节点与图源扩展管理、阅读器全局预设、隐私安全锁、缓存清理。
* **二级与模态页面层（Secondary & Modal Pages）**
  * **页面 A：全局聚合搜索与车牌直达页（Search & Quick ID Overlay）**
  * **页面 B：漫画详情与章节中心页（Manga Detail Page）**
  * **页面 C：内容预览与缩略图快览抽屉（Preview Gallery Sheet）**
  * **页面 D：章节评论与互动社区抽屉（Comments & Danmaku Sheet）**
  * **页面 E：全屏沉浸式阅读器（Immersive Manga Reader）**
  * **页面 F：下载中心与实况/悬浮窗控制器（Download Manager）**
  * **页面 G：安全防窥与生物识别锁屏页（Biometric Lock Screen）**

---

## 四、 核心页面逐页重构设计方案（含现有页面与扩展页面）

### 1. 发现首页（Explore Page）—— 对应截图 `3491.jpg` 重构

#### 视觉与交互改造要点
1. **沉浸光感吸顶搜索栏**：移除顶部被裁切的无意义标题与双色横条，替换为带有 `uiMaterial` 光感模糊效果的吸顶栏。左侧为 App 品牌标识与当前节点延迟状态灯（绿色圆点 `28ms`），中间为胶囊式搜索入口（提示词：“搜索漫画名、作者或输入 JM 编号直达”），右侧为排行榜快捷入口。
2. **封面卡片标准化与角标重设计**：
   * 统一采用 `3:4` 黄金比例圆角封面（`borderRadius(12)`），内嵌微弱内描边（`borderWidth(0.5), borderColor('rgba(255,255,255,0.15)')`）。
   * **废除生硬的圆形国旗贴图**：改为右上角半透明毛玻璃胶囊徽章（如 `中字`、`日漫`、`韩漫`、`全彩`），字号 `10fp`，背景采用 `BackdropBlur` 提取封面局部底色。
   * **优雅骨架屏与渐进加载**：图片加载前展示柔和脉冲呼吸动画（Shimmer Skeleton），彻底消除截图中大片灰白空框；底部书名固定最多 2 行（`maxLines(2)` + `TextOverflow.Ellipsis`），副标题展示作者或最新话数，杜绝文字重叠乱码。
3. **“随机推荐”交互升级**：保留右上角“换一批”按钮，点击时触发旋转图标动效与卡片列表的交错淡入（Staggered Fade-in），并支持左滑单张卡片“不感兴趣”。
4. **移除冗余“分类速览”，升级为“榜单与专题双栏区”**：将热门排行改造为支持“日榜 / 周榜 / 月榜 / 飙升榜”分段切换（`SegmentButton`）的横向高优卡片流，前 3 名配有流光金/银/铜数字角标。
5. **底部悬浮光感导航栏（`HdsTabs`）**：采用 HarmonyOS 7 沉浸光感底部栏，支持滚动时微缩或半透明透出底层漫画封面色彩。

#### 重构后布局示意

```
┌──────────────────────────────────────────────┐
│ ●28ms  [ 搜索漫画名/作者/JM编号直达 ]  排行榜 │  ← 沉浸光感吸顶搜索栏
├──────────────────────────────────────────────┤
│ 热门榜单  [日榜|周榜|月榜|飙升]               │  ← SegmentButton 分段切换
│ ┌────┐ ┌────┐ ┌────┐ ┌────┐                  │
│ │ 1  │ │ 2  │ │ 3  │ │ 4  │ ...横滑           │  ← 前 3 名金/银/铜角标
│ └────┘ └────┘ └────┘ └────┘                  │
├──────────────────────────────────────────────┤
│ 随机推荐                          ⟳ 换一批   │
│ ┌────┐ ┌────┐ ┌────┐                          │
│ │    │ │    │ │    │   3 列网格 + 骨架屏      │
│ └────┘ └────┘ └────┘                          │
├──────────────────────────────────────────────┤
│ 最新更新                                      │
│ ┌────┐ ┌────┐ ┌────┐                          │
│ │    │ │    │ │    │   3 列 + 上拉分页        │
│ └────┘ └────┘ └────┘                          │
├──────────────────────────────────────────────┤
│   发现      分类      书架      我的           │  ← 底部悬浮光感导航栏
└──────────────────────────────────────────────┘
```

### 2. 漫画详情页（Manga Detail Page）—— 对应截图 `3492.jpg` 重构

#### 视觉与交互改造要点
1. **折叠视差头部与消除重复标题**：
   * 首屏顶部导航栏完全透明，仅展示返回按钮、分享/复制链接按钮与更多菜单，**不再重复显示长书名**。当用户向上滑动超过封面高度时，顶部导航栏才以沉浸光感模糊渐显，并平滑浮现单行书名。
   * 背景层提取当前漫画封面图，叠加超大半径高斯模糊（`blur(60)`）与深色渐变遮罩，营造极具氛围感的沉浸头部。
2. **元数据与车牌 ID 胶囊规范化**：
   * 左侧封面图支持点击放大查看高清原图并保存相册。
   * 右侧信息区：主标题最多显示 2 行（点击可展开完整多语种译名气泡）；作者名设计为可点击的浅色高亮链接，点击直接跳转该作者作品合集；编号胶囊（`JM1197606`）内置一键复制图标，点击后弹出轻提示（Toast）“已复制编号 JM1197606”。
   * 统计数据（收藏数 `10.6k`、阅读量 `5.5w`）采用精致线性 Symbol 图标替代原生彩色 Emoji（❤️/👀），视觉风格更统一。
3. **主次分明的行动按钮区（CTA 重构）**：
   * **移除右下角遮挡画面的悬浮心形 FAB**，将“收藏”整合进主操作区。
   * **主行动按钮（Primary CTA）**：“开始阅读 / 续读第 1 话”占据右侧或通栏 `55%` 宽度，采用品牌高亮主色（或提取自封面的高饱和强调色）实心填充 + 醒目播放/翻书图标。
   * **次级操作按钮组（Secondary Actions）**：“收藏（带爱心微动效）”、“下载”、“评论（带角标数量）”采用等宽毛玻璃次级按钮并列排布，彻底纠正原截图中“下载”按钮喧宾夺主的问题。
4. **章节列表与“内容预览”抽屉化改造（核心性能与体验优化）**：
   * **章节区**：增加“正序/倒序”切换按钮、“连载中/已完结”状态标识及章节搜索。已读章节置灰，上次阅读章节显示“上次读到 P.12”胶囊标记。
   * **预览区重构（解决 60 页大图平铺拉长问题）**：不在详情页底部直接渲染 60 张三列大图，改为展示 **单行横向滑动的“前 8 页精简胶片预览条”**，右侧附带“查看全部 60 页预览 >”入口。点击后通过 HarmonyOS 原生半模态弹窗（`bindSheet`）唤起虚拟化网格画廊（基于 ArkUI 懒加载布局 `LazyVGridLayout`），点击任意一页可直接从该页进入阅读器。

#### 重构后布局示意

```
┌──────────────────────────────────────────────┐
│ ←              (透明)                 ⊂ ⊞    │  ← 初始透明，上滑渐显书名
│   ░░░░░ 高斯模糊封面背景 (blur 60) ░░░░░      │
│  ┌────────┐  出租女友/租借女友                │
│  │ 封面    │  作者：宮島禮吏 (可点击)          │
│  │ 3:4    │  [JM1197606 ⧉]  ♥10.6k 👁5.5w   │
│  └────────┘  [青年漫][剧情][爱情][校园][中文]  │
│                                              │
│  ┌────────────────────┬────┬────┬────┐       │
│  │ ▶ 开始阅读 第1话    │ ♥  │ ⬇  │ 💬 │       │  ← 主 CTA + 三个次级圆钮
│  └────────────────────┴────┴────┴────┘       │
│                                              │
│  章节 (12)  ⇅ 正倒序      [连载中]            │
│  ┌─ 第12话 ─────────────────── 上次读到P.12 ─┐│
│  ├─ 第11话 (已读置灰) ──────────────────────┤│
│  ├─ 第10话 (已读置灰) ──────────────────────┤│
│  └─ ... ────────────────────────────────────┘│
│                                              │
│  内容预览 (第1話 · 前60页)      查看全部 >    │
│  ┌────┐┌────┐┌────┐┌────┐┌────┐ →            │
│  │ 1  ││ 2  ││ 3  ││ 4  ││ 5  │   横向胶片条 │
│  └────┘└────┘└────┘└────┘└────┘              │
└──────────────────────────────────────────────┘
```

### 3. 沉浸式漫画阅读器（Immersive Reader Page）—— 对应截图 `3493.jpg` 重构

#### 视觉与交互改造要点
1. **默认真全屏无干扰画布**：
   * 进入阅读器后默认隐藏系统状态栏、顶部标题栏与底部导航条，100% 屏幕面积用于呈现漫画画面（支持深邃黑 `#000000` 或纸质护眼米黄背景）。
   * 仅在屏幕右下角或底部边缘保留极低透明度的微型常驻信息条（如 `第1话 · 1/174 · 16:21 · 电量 64%`），且可在设置中关闭。
2. **九宫格触控热区与单手操作优化**：
   * 屏幕左/下侧点击：下一页；屏幕右/上侧点击：上一页（可根据左手/右手习惯或日漫右翻模式自动镜像）。
   * **屏幕中央区域单击**：以弹簧动画呼出/隐藏 **沉浸光感浮动控制面板（HUD）**。
   * 支持双指自由缩放（`1.0x - 4.0x`）与双击定点放大（Smart Zoom），放大后滑动具备边缘回弹阻尼。
3. **上下双层沉浸光感 HUD 控制面板**：
   * **顶部浮动栏（Top HUD）**：返回按钮、当前话标题（`第 1 話`）、右上角“打开原网页/分流切换”与“本页书签/截图分享”按钮。
   * **底部浮动控制台（Bottom HUD）**：
     * **带缩略图预览的进度滑动条（Thumbnail Scrubber）**：拖动滑块（`1 / 174`）时，滑块上方实时悬浮显示目标页的小图预览，松手即刻跳转，并提供“上一话 / 下一话”快捷按钮。
     * **四大金刚控制栏**：
       1. **目录**：唤出侧边或半模态章节列表。
       2. **阅读模式**：一键切换 `纵向条漫（Webtoon 卷轴）`、`标准日漫（右至左翻页）`、`美漫/国漫（左至右翻页）`、`折叠屏/平板双页拼合（自动识别跨页大图）`。
       3. **画面调节**：亮度独立滑块、夜间暗色反相/护眼滤镜、智能裁白边（Auto Crop Borders）、超分画质增强开关。
       4. **自动翻页/设置**：支持倍速自动卷轴滚动及音量键翻页开关。
4. **双向预加载与分块解码优化**：
   * 参考 [新闻阅读行业场景解决方案](https://developer.huawei.com/consumer/cn/doc/best-practice/bpta-news-reading)，基于 `List` / `WaterFlow` 的 `cachedCount(5)` 实现前后 5 页后台静默预下载与内存 LRU 释放，条漫高速滑动如丝般顺滑。

#### HUD 布局示意

```
┌──────────────────────────────────────────────┐
│ ←  第 1 話 · 出租女友       [条漫] ⊂ ⊞ ⚑     │  ← Top HUD（光感模糊）
│                                              │
│                                              │
│              （全屏漫画画布）                 │
│         点中央=HUD  点左=下一页               │
│              点右=上一页                      │
│                                              │
│                                    1/174 ▏   │  ← 微型常驻页码胶囊
│ ┌──────────────────────────────────────────┐ │
│ │ 上一话  ●───────╂──────── 174   下一话   │ │  ← 进度滑动条
│ │                                          │ │
│ │    📖目录   ⇄阅读模式  🎨画面调节  ⚙设置   │ │  ← 四大金刚控制栏
│ └──────────────────────────────────────────┘ │  ← Bottom HUD（光感模糊）
└──────────────────────────────────────────────┘
```

### 4. 补全全量核心页面设计（超越现有截图的完整闭环）

#### (1) 全局搜索与车牌号直达页（Search & ID Direct Page）
* **智能剪贴板识别**：当用户复制了类似 `JM1197606` 或 6-7 位数字编号切回 App 时，顶部自动弹出灵动胶囊提示：“检测到漫画编号 JM1197606，点击立即直达”。
* **多维搜索面板**：包含搜索历史胶囊、实时热门搜索榜（带趋势升降箭头）、多标签组合检索器（支持按 `作者:`、`标签:`、`汉化组:` 语法高亮组合过滤）。

#### (2) 分类与排行榜中心（Category & Ranking Hub）
* **吸顶多级筛选器**：顶部提供 `全部地区（日本/韩国/内地/欧美）`、`题材标签（纯爱/奇幻/校园/同人/单行本）`、`读者群体（青年/少女/少年）`、`排序（最新更新/最多阅读/最高评分）` 四维联动折叠筛选栏。
* **虚拟化瀑布流展示**：使用 ArkUI `LazyVWaterFlowLayout` 呈现错落有致的封面流，卡片底部直接展示最高频的 2 个标签胶囊与收藏人数。

#### (3) 智能书架与离线下载中心（Bookshelf & Download Manager）
* **断点续读优先设计**：书架卡片底部不再只显示书名，而是高亮显示 `读至 第1话 P.15 / 共174页`，并带有“有更新”红点徽章；提供顶部一键“继续阅读《出租女友》”快捷横幅。
* **多任务下载与标准悬浮窗**：下载队列支持按章节多选、并发线程数控制（1-5 线程）、失败重试与打包导出（CBZ）。接入 HarmonyOS 7 标准悬浮窗与实况窗（Live View），当应用退至后台下载大型漫画时，在桌面闪控球或状态栏实时显示下载进度百分比。

#### (4) 评论与章节吐槽抽屉（Comments & Discussion Sheet）
* **半模态无感交互**：遵循 [HarmonyOS 弹出框与半模态规范](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-use-dialogs)，点击详情页或阅读器内的“评论”按钮时，无需整页跳转，直接通过 `bindSheet` 从底部滑出占据屏幕 `75%` 高度的沉浸光感评论抽屉。
* **防剧透遮罩**：支持带 `剧透折叠` 标记的评论（需点击磨砂遮罩方可查看文字），支持按“热门评论 / 最新评论 / 当前章节吐槽”筛选。

#### (5) 我的、分流图源与隐私安全中心（Profile, Sources & Privacy）
* **多线路分流测速面板**：针对漫画图源常见的网络波动，内置可视化的 CDN 分流节点测速卡片（展示各图片服务器延迟 `ms` 与成功率，支持一键切换或自动优选最快节点）。
* **隐私防窥体系**：
  * **生物识别应用锁**：支持调用 HarmonyOS `UserAuth` 接口开启指纹/3D 面容解锁。
  * **多任务模糊遮罩**：当用户上滑进入系统多任务后台切换界面时，自动将应用快照替换为高斯模糊图层或自定义安全封面，保护阅读隐私。

---

## 五、 核心 ArkTS 声明式代码重构范式

以下提供重构后核心架构（响应式主框架、漫画详情页折叠光感头部 + 半模态预览、沉浸式阅读器 HUD）的 ArkUI 实现范式。**注意：范式中的 HdsTabs/uiMaterial 为 HarmonyOS 7 专有能力，实际工程用稳定 API（Tabs + backgroundBlurStyle 等）等价实现。**

### 1. 响应式主导航壳与沉浸光感底栏 (`MainShell.ets`)

```typescript
Navigation(this.pageStack) {
  Tabs({ barPosition: BarPosition.End, index: this.currentIndex }) {
    TabContent() { ExplorePage() }.tabBar(this.TabBuilder('发现', 0))
    TabContent() { CategoryPage() }.tabBar(this.TabBuilder('分类', 1))
    TabContent() { BookshelfPage() }.tabBar(this.TabBuilder('书架', 2))
    TabContent() { ProfileSettingsPage() }.tabBar(this.TabBuilder('我的', 3))
  }
  .barBackgroundBlurStyle(BlurStyle.ComponentUltraThick)
  .barOverlap(true)
  .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
}
.mode(NavigationMode.Stack)
.hideTitleBar(true)
```

TabBar 样式要点：选中态 `#FF4D6D`，未选中 `#8E8E93`，SymbolGlyph 图标 + 11fp 文字，选中时 BounceSymbolEffect 微弹。

### 2. 漫画详情页：折叠光感头部 + 主次 CTA + 半模态预览抽屉 (`MangaDetailPage.ets`)

```typescript
Stack({ alignContent: Alignment.Top }) {
  Image(coverUrl).width('100%').height(340).objectFit(ImageFit.Cover).blur(65).opacity(0.45)
  Scroll() {
    Column({ space: 20 }) {
      Blank().height(56)
      Row({ space: 16 }) {
        Image(coverUrl).width(118).height(164).borderRadius(12)
          .geometryTransition('manga_cover_' + this.mangaId)
        Column({ space: 8 }) {
          Text(this.title).fontSize(18).fontWeight(FontWeight.Bold).maxLines(2)
          Text('宮島禮吏').fontSize(14).fontColor('#3B82F6')
          Row({ space: 10 }) {
            Text(this.mangaId).fontSize(12).padding(8).backgroundColor('rgba(148,163,184,0.2)').borderRadius(6)
            Text('♥ 10.6k · 👁 5.5w').fontSize(12).fontColor('#64748B')
          }
        }.layoutWeight(1)
      }
      // CTA 行：主按钮 layoutWeight(2) + 三个 46x46 圆形次级按钮
      // 预览胶片条：List(Axis.Horizontal) 前 8 页 + bindSheet 全量 LazyForEach 网格
    }
  }
  // 顶部导航栏：scrollOffset > 80 时 backgroundBlurStyle 渐显书名
}
```

### 3. 全屏沉浸式阅读器与浮动光感 HUD (`MangaReaderPage.ets`)

```typescript
Stack() {
  List({ scroller: this.listScroller }) {
    // LazyForEach + cachedCount(5) 预加载前后 5 页
  }
  .width('100%').height('100%').backgroundColor('#0D0D0D')
  .cachedCount(5)
  .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  .gesture(TapGesture({ count: 1 }).onAction((event) => {
    // tapX 落点三分：中央=HUD 显隐，右=下一页，左=上一页
  }))

  if (!this.isHudVisible) {
    Row() { Text('第 1 話'); Text(`${this.currentPage} / ${this.totalPages}`) }
      .backgroundColor('rgba(0,0,0,0.45)').position({ right: 0, bottom: 0 })
  }
  if (this.isHudVisible) {
    Column() {
      Row() { /* 返回 | 话标题 | 模式胶囊 */ }.backgroundBlurStyle(BlurStyle.Thin)
      Blank()
      Column() {
        Row() { Text('上一话'); Slider({ value: currentPage, max: totalPages }).layoutWeight(1); Text('下一话') }
        Row() { /* 目录 | 阅读模式 | 画面调节 | 设置 */ }.justifyContent(FlexAlign.SpaceAround)
      }.backgroundBlurStyle(BlurStyle.Thin)
    }.transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
  }
}
```

---

## 六、 工程架构与实施要点

* 单模块 entry 工程，pages/ 按页面分文件，common/ 放主题与通用组件，data/ 放数据层。
* 全局沉浸式：EntryAbility 设置 window 全屏布局，页面用 expandSafeArea 延展。
* 长列表一律 LazyForEach / cachedCount 预加载；瀑布流 WaterFlow；半模态 bindSheet。
* 主题双强调色：品牌粉 `#FF4D6D`（Tab 激活、收藏）与 CTA 蓝 `#3B5BDB`（开始阅读主按钮）。
