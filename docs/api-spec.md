# api-spec.md — 禁漫姬 Android 版 数据与网络层接口规格（鸿蒙移植用）

> 依据：`jinmanji-app/` 源码逐文件分析（2026-10）。所有"源码位置"均为 Kotlin 文件内行号，
> 路径省略前缀 `jinmanji-app/app/src/main/java/com/mobai/jm/`（例：`JmApi.kt:342` 指
> `data/JmApi.kt` 第 342 行）。移植时**必须**对照源码核对关键算法；本文所有行号已逐条核对。
>
> 分级标记：**[M]必保**（不做就不是这个 App）、**[S]可简化**（保留语义、实现可简化）、**[O]建议裁剪**（鸿蒙版不做，见 §8）。

---

## 1. 总体架构

```
UI (Compose)
 ├─ JmApi (data/JmApi.kt) ─── JM 移动端 API：AES 加密信封 + 域名池 + 图片 CDN 池
 ├─ PageLoader (util/PageLoader.kt) ─ 章节大图：原图下载→原尺寸反混淆→缩放；三级字节缓存
 ├─ Coil ImageLoader (MoBaiApplication.kt) ─ 封面/列表小图（网络 Image 组件）
 ├─ 各 Store (data/*.kt) ─── 收藏/历史/搜索历史/屏蔽词/标签统计/详情缓存/章节缓存/首页缓存
 └─ DownloadQueue (download/DownloadQueue.kt) ─ 线性下载队列 + PDF/ZIP/7z/tar.gz 导出
```

- 网络栈：OkHttp；API 客户端默认 **HTTP/1.1**（`JmApi.kt:115-122`，CN 网络 h2 假死），图片客户端 **H2+H1.1**（`MoBaiApplication.kt:37`）；两者共享调度器与连接池（`net/NetDispatcher.kt:10-13`：连接池 32 连接 / 10 分钟保活；每主机并发默认 24，可在设置中改 1..512，总并发 = perHost×4 上限 2048，`NetDispatcher.kt:16-20`）。
- API 客户端超时：connect 5s / read 12s / call 15s（`JmApi.kt:125-127`）；域名服务器专用客户端 4/4/5s（`JmApi.kt:132-136`）；图片客户端 6/20/25s（`MoBaiApplication.kt:38-40`）。
- Cookie：进程内内存 CookieJar，按 host 整组覆盖保存（`JmApi.kt:98-108`）。`/setting` 的响应会种下基础 cookie，之后所有 API 请求自动带上（注释见 `JmApi.kt:251`）。

---

## 2. JM API 端点清单

### 2.0 通用调用协议（所有 `apiGet` 端点共用）**[M]**

源码：`JmApi.kt:320-368`（`apiGet`）。

1. `ts = floor(now-ms / 1000)` 的十进制字符串（`JmApi.kt:342`）。
2. `token = md5hex( ts + "185Hcomic3PAPP7R" )`（`TOKEN_SECRET` 常量 `JmApi.kt:53`；计算 `JmApi.kt:343`；md5hex 输出 32 字符小写 hex，`JmApi.kt:294-297`）。
3. 请求头（`JmApi.kt:344-348`）：
   - `token: <token>`
   - `tokenparam: "<ts>,<appVersion>"`（appVersion 初始 `"2.0.26"`，由 `/setting` 的 `jm3_version` 更新，`JmApi.kt:177,267-273`）
   - `User-Agent: Mozilla/5.0 (Linux; Android 9; V1938CT Build/PQ3A.190705.11211812; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/91.0.4472.114 Safari/537.36`（`JmApi.kt:88-90`）
   - 外加内存 CookieJar 中的该 host cookie。
4. 响应为 JSON 信封：`{ "code": <int>, "data": <str> }`。`code != 200` 抛错（`JmApi.kt:350-351`）；`data` 为 Base64 文本。
5. 解密：`AES-256-ECB(PKCS5Padding)`，**key = md5hex(ts + "185Hcomic3PAPP7R") 这 32 个 hex 字符的 ASCII 字节**（即 key 就是 token 字符串本身的字节，不是 16 字节摘要！见 `JmApi.kt:299-303,354`）。解密结果为明文 JSON。
6. 多域名重试与预算（`JmApi.kt:322-327,359-366`）：
   - 取 `orderedDomains()`（健康排序，见 §6.1）前 N 个：隧道运行时 N=2，直连 N=3；
   - 总预算 18 秒；剩余 < 800ms 即放弃；单次尝试 callTimeout 封顶为剩余预算（<14s 时）；
   - 成功：`rememberGoodDomain`（该域名移到队首并持久化 `jm_last_domain`，`JmApi.kt:370-376`）+ 清除失败计数；失败：`markDomainFailure`（连续 2 次失败隔离 5 分钟，`JmApi.kt:626-632`、`QUARANTINE_MS` `JmApi.kt:160`）。

### 2.1 端点表

除特别说明外，方法均为 `GET https://<API域名><路径>`，请求头按 §2.0，响应 `data` 解密后的 JSON 结构如下。

| # | 端点 | 参数 | 解密后响应字段（用到的） | 源码 |
|---|------|------|--------------------------|------|
| 1 | `/setting` | 无 | `img_host`(str, 官方图片域名)、`jm3_version`(str) | `JmApi.kt:252-279` |
| 2 | `/random_recommend` | `time=<当前毫秒>`（防缓存） | `Comic[]`（见 §2.2），每批 30 条，服务端按周期轮换固定池 | `JmApi.kt:408-410` |
| 3 | `/latest` | `page=<n>`（从 1 起） | `Comic[]`，每页 80 条 | `JmApi.kt:413-415` |
| 4 | `/categories` | 无 | `{ categories: [{ id, name, slug, total_albums }] }` | `JmApi.kt:430-443` |
| 5 | `/categories/filter` | `page`、`c=<分类id或slug，空则"0">`、`o=<mr/mv/mv_m/mv_w/mv_t>`（最新/总榜/月/周/日） | `{ content: Comic[] }` | `JmApi.kt:417-427` |
| 6 | `/search` | `search_query`、`page`、`o=<mr/mv/mp/tf>`（最新/最多观看/最多图片/最多爱心）、`t=<a/t/w/m>`（全部/今日/本周/本月）、可选 `y=<年>`、`m=<月>`（仅有年时只带 y） | `{ total:int, content: Comic[] }`，每页约 45 条 | `JmApi.kt:686-708` |
| 7 | `/album` | `id=<albumId>` | `{ name, author:str[], tags:str[], likes, total_views, series:[{id,name,sort}] }`；`series` 按 `sort.toInt()` 升序；为空时回退单章节 `[{id=albumId, name, sort="1"}]` | `JmApi.kt:446-471` |
| 8 | `/chapter` | `id=<photoId(章节id)>` | `{ images: str[] }`（图片文件名列表，含扩展名，如 `00001.webp`） | `JmApi.kt:474-477` |
| 9 | `/forum` | `mode=manhua`、`aid=<albumId>`、`page`（从 1 起，每页约 10 条）、`lang=CN` | `{ total:int, list:[{ CID, nickname⎮username, content(HTML), likes, spoiler(bool⎮"1"), addtime⎮update_at, parent_CID }] }` | `JmApi.kt:480-498` |
| 10 | `/chapter_view_template` | `id=<photoId>`、`mode=vertical`、`page=0`、`app_img_shunt=1`、`express=off`、`v=<ts>` | **不是加密信封**：返回 HTML/JS 明文；用正则 `var\s+scramble_id\s*=\s*(\d+)` 提取；**此端点 token 密钥不同**：`token = md5hex(ts + "18comicAPPContent")`，tokenparam 同格式；失败回退常量 `220980`；结果按 photoId 进程内缓存 | `JmApi.kt:509-542` |

域名分发服务器（非 JM API，无 token）**[S]**：`https://rup4a04-c02.tos-cn-hongkong.byteplues.com/newsvr-2025.txt`（`JmApi.kt:64-65`）。响应文本处理（`JmApi.kt:229-249`）：
1. 去掉开头所有 `code > 127` 的字节（BOM/乱字符）；
2. `trim()` 后按 `AES-256-ECB(PKCS5Padding)` 解密，key = `md5hex("diosfjckwpqpdfjkvnqQjsik")`（`DOMAIN_SECRET`，`JmApi.kt:54`）的 ASCII 字节（同 §2.0 第 5 条规则）；
3. 明文 JSON 取 `Server: str[]` 为新域名池。

### 2.2 Comic 对象解析 **[M]**

源码 `JmApi.kt:380-400`（`parseComic`），模型 `Models.kt:5-13`：

```
Comic {
  id:        str  ← o["id"]
  title:     str  ← o["name"]
  author:    str  ← o["author"]   // 列表接口为单个字符串
  coverUrl:  str  ← 三种情况（JmApi.kt:384-389）：
     a. image 为空 → https://<imgHost(seed="album/{id}")>/media/albums/{id}_3x4.jpg
     b. image 以 "http" 开头 → 原样
     c. 其它（相对路径，通常 /media/albums/xxx.jpg）→ https://<imgHost(seed=image)>{image}
  category:    str? ← o["category"]["title"]
  categorySub: str? ← o["category_sub"]["title"]
}
```

评论清洗（`JmApi.kt:500-507`）：`<br>`→换行 → 去所有标签 → 反转义 `&amp; &lt; &gt; &quot; &#39; &nbsp;` → trim。模型 `JmComment` 见 `Models.kt:43-52`。

「车牌号」解析（搜索页本地逻辑，`ui/search/SearchScreen.kt:73`）：正则 `^\s*(?:[jJ][mM])?\s*(\d{1,10})\s*$` 命中则把纯数字当 albumId 直达详情。

---

## 3. 图片反混淆（分块重排）算法 **[M] — 逐行精确移植**

源码：`data/JmImageDecoder.kt`（全文 73 行）。

### 3.1 分块数计算 `segments(scrambleId, photoId, filename)`（`JmImageDecoder.kt:22-33`）

```
输入：scrambleId:int（来自 /chapter_view_template，见 §2.1#10）
      photoId:str   章节ID
      filename:str  图片文件名（含扩展名）
1. pid = photoId 转整数；转换失败 → 返回 0（不解码）          // :23
2. 若 pid < scrambleId → 返回 0（老图无加密）                  // :24
3. 若 pid < 268850 → 返回 10（固定 10 段）                     // :25   常量 SCRAMBLE_268850 :18
4. x = pid < 421926 ? 10 : 8                                   // :26   常量 SCRAMBLE_421926 :19
5. nameNoSuffix = filename 去掉最后一个 '.' 及之后（不含扩展名）// :28-29 ★ 官方算法用不带扩展名的文件名
6. h = md5hex( pid的十进制字符串 + nameNoSuffix )              // :30   注意 photoId 按数值化后的十进制参与拼接
7. n = h 最后一个字符的字符码 % x                              // :31   （'0'..'9'=48..57，'a'..'f'=97..102）
8. 返回 n*2 + 2                                                // :32
```

> ★ v0.2.2 修复记录（README:94）：哈希输入是**不带扩展名**的文件名（`md5(photoId + "00001")` 而非 `md5(photoId + "00001.webp")`），14/14 样本吻合。这是最易踩的坑。
> pid 数值化注意：`"0000123"` → 123，参与 md5 的是 `"123"`（`toLongOrNull` 后插值）。

### 3.2 重排 `decode(input: Bitmap, segments: Int)`（`JmImageDecoder.kt:36-66`）

```
若 segments <= 0 → 原样返回                                    // :37
若 h(图高) < segments → 原样返回                               // :40
over = h % segments                                            // :46
for i in 0 until segments:                                     // :47
    move = h / segments                // 每段基准高度          // :48
    ySrc = h - move*(i+1) - over       // 源条带顶部（自底向上数）// :49
    yDst = move * i                    // 目标条带顶部          // :50
    若 i == 0: move += over            // 余数行并入第 0 段      // :51-53
    否则:      yDst += over            // 其余段整体下移 over    // :54-55
    若 move <= 0: continue                                      // :56
    ySrc = max(ySrc, 0)                                         // :57
    绘制：源矩形 (0, ySrc, w, ySrc+move) → 目标矩形 (0, yDst, w, yDst+move)，双线性过滤 // :58-63
```

语义：把乱序图按高度切成 `segments` 条水平带（自底向上编号 0..n-1），第 i 条（自底数）搬到输出第 i 槽（自顶数），即**垂直方向带级倒序重排**；除不尽的 `over` 行并入第 0 条。

### 3.3 原图 → 最终图流程与并发注意事项（`util/PageLoader.kt`）**[M]**

`PageLoader.load(context, photoId, filename, scrambleId, targetWidth)`（`PageLoader.kt:56-123`）：

1. 缓存键 `"{photoId}/{filename}@{scrambleId}@{targetWidth}"`；内存 LRU 96MB（按 byteCount 计，`PageLoader.kt:46-48,63`）。
2. 并发信号量：默认 4；用户设置 1..512 时取设置值但**封顶 32**（`PageLoader.kt:31-44`）。
3. `targetWidth ≤ 720` 视为缩略图：先查缩略图磁盘缓存 `{page_cache}/{photoId}/{filename}.t{width}-s{scrambleId}.jpg`，命中直接返回（`PageLoader.kt:68-86,125-132`）。
4. 原图字节三级来源（`readBytes`，`PageLoader.kt:134-163`）：
   ① 手动下载目录 `downloads/{photoId}/{filename}` → ② 页缓存 `page_cache/{photoId}/{filename}` → ③ 网络下载，`imageUrl(photoId, filename, attempt)` 换域名重试 3 次（attempt=0..2），成功且 `autoCache` 开启时写入页缓存并触发 trim。
5. 解码与反混淆（`PageLoader.kt:90-108`）：
   - **必须解码到原始尺寸后再反混淆，最后才缩放**。先缩放会使分段边界因取整错位，出现"横线"瑕疵（v0.5.2 实测平均 3px、最大 8px 接缝，README:100、注释 `PageLoader.kt:16-20`）。
   - 缩略图用 RGB_565 解码（内存减半，`PageLoader.kt:91-94`）。
   - `JmImageDecoder.segments(scrambleId, photoId, filename)` 计算段数 → `JmImageDecoder.decode`。
   - `targetWidth < 原宽` 时等比缩放；缩略图结果以 JPEG q82 落盘（`PageLoader.kt:102-118`）。
6. 磁盘页缓存总量 512MB，超限删最旧（按 lastModified）直到 ≤ 90% 上限；trim 节流 15s（`PageLoader.kt:50,181-197`）。
7. 并发注意：解码产生的中间 `Bitmap` 及时 `recycle()`（`PageLoader.kt:101,106`）；`JmApi.scrambleId` 结果进程内缓存（`JmApi.kt:509`），阅读器在章节加载后**后台**获取，期间用默认 220980 先渲染（`ui/reader/ReaderScreen.kt:99,154,201-209`）；scrambleId 变化会使预取集合失效并按新值重预取。

封面/列表小图不走反混淆（`/media/albums/` 资源无加密），直接用网络 Image 组件 + 预取错峰（`util/ImagePrefetch.kt:16-28`：去重后逐张入队，间隔 50ms）。

---

## 4. 本地存储 **[M]**

存储根目录（`util/StorageUtil.kt:15-32`）：隐私模式（默认开）→ 应用私有 `filesDir`；关闭 → 外部应用目录。子目录：

| 路径 | 内容 |
|------|------|
| `favorites.json` | 收藏列表 |
| `meta/fav_tags.json` | 收藏的标签 |
| `meta/history.json` | 浏览历史 |
| `meta/search_history.json` | 搜索历史 |
| `meta/blocked_tags.json` | 屏蔽词 |
| `meta/custom_cats.json` | 自定义分类/tag |
| `meta/tag_stats.json` | 标签词频统计（词云） |
| `meta/home.json` | 首页预加载缓存 |
| `meta/downloads.json` | 下载任务记录 |
| `meta/{albumId}.json` | 本子详情缓存（AlbumCache） |
| `meta/pages/{photoId}.json` | 章节图片文件名列表缓存（PagesCache） |
| `page_cache/{photoId}/…` | 阅读页原图 + 缩略图（见 §3.3） |
| `downloads/{photoId}/{filename}` | 手动下载的原始（乱序）图片 |
| `image_cache/` | Coil 封面磁盘缓存（2GB，`MoBaiApplication.kt:79-86`） |

所有 Store 共同模式：JSON 数组/对象整体覆写持久化（异步协程写、失败静默）、启动 init 一次性读入内存、运行期内存列表即真相。读写语义：

- **收藏 FavStore**（`data/FavStore.kt`）：`FavItem { id, title, author(逗号连接), coverUrl, addedAt:ms }`（:16-23）。`add` 按 id 去重、新收藏插到列表头（:56-69）；`toggle` 返回收藏后状态；标签列表 trim + 去重（:86-108）。**无数量上限**。导入合并按 id 去重返回新增数（:119-129）。
- **浏览历史 HistoryStore**（`data/HistoryStore.kt`）：`HistoryItem { id, title, author, coverUrl, viewedAt:ms }`（:17-24）。`record` 在详情页加载后调用（`ui/album/AlbumDetailScreen.kt:172`）：设置 `historyEnabled`（默认 true）关闭时不记录；同 id 先删后插到头；**上限 300 条**，超出删尾部（:47-61）。导入合并同 id 保留较新 viewedAt、加完按 viewedAt 降序重排（:74-92）。
  > ⚠ **页码事实澄清**：原项目**不持久化阅读页码/章节进度**。`HistoryItem` 无页码字段；阅读器 `ReaderArgs.startPage`（`ui/reader/ReaderScreen.kt:71-77`）仅在会话内由"详情页预览墙点击直达该页"传入（`ui/App.kt:240-245`），退出即丢。鸿蒙版按原行为实现即可；若产品要求"续读"，属于超出原实现的增强，需另行决策（不在本规格内）。
- **搜索历史 SearchHistoryStore**（`data/SearchHistoryStore.kt`）：字符串列表，去重 + 置顶，**上限 50 条**（:34-41）；批量删除/清空/导入去重（:43-65）。
- **偏好设置 AppPrefs**（`util/AppPrefs.kt`，SharedPreferences `mobai_prefs`）全键与默认值：
  `auto_cache=true`、`log_level=ERROR`、`random_page_size=24`、`history_enabled=true`、`privacy_mode=true`、`hud_enabled=true`、`dev_mode=false`、`fav_sort/history_sort=time_desc`、`reader_horizontal=false`、`download_format=pdf`、`archive_level=3(0..5)`、`archive_img_quality=visual`、`archive_pwd_mode=none`、`archive_fixed_pwd=""`、`archive_pwd_strategy=append`、`download_remember=false`、`pdf_preset=visual`、`download_path=Download`、`img_concurrency=0(自动)`、`tunnel_mode=warp`、`tor_bridges=""`、`masque_*`/`doh_*`/`sni_*`/`ech_enabled`（隧道与实验网络，见 §8 裁剪）。
  JmApi 自用键（同文件）：`jm_domains`、`jm_last_domain`、`jm_image_host`、`jm_app_version`、`jm_host_order`、`jm_host_order_ts`（`JmApi.kt:56-62`）。
- **屏蔽词 BlockTagsStore**（`data/BlockTagsStore.kt`）：trim + 去重；命中判定 `isBlocked`（:59-74）：拼接 `title + author + category + categorySub` 小写后包含任一屏蔽词，**或**后台校准到的真实 tags（TagStore）中包含屏蔽词。
- **标签词频 TagStats**（`data/TagStats.kt`）：`{ counts: {tag:int}, readIds/favIds/dlIds: [] }`；阅读/收藏/下载各记一次（同 id 同类不重复计数），供词云 `topTags(limit)` 按次数降序（:42-74）。
- **详情/章节/首页缓存**：AlbumCache 单文件覆写（`data/AlbumCache.kt:28-38`）；PagesCache 同（`data/PagesCache.kt:27-37`）；HomeCache `{random[], ranking[], latest[]}`（`data/HomeCache.kt`）。语义：先读缓存秒开，网络成功后覆写，失败保留旧值（调用处 `Stores.kt:49-70`、`ReaderScreen.kt:157-199`、`AlbumDetailScreen.kt:144-157`）。
- **数据导入/导出**（`util/DataTransfer.kt`）：导出 JSON `{ app:"mobai", schema:1, exportedAt, favorites:{items[],tags[]}, history:{browse[],search[]}, config:{theme,autoCache,randomPageSize,logLevel,downloadPath,historyEnabled,favSort,historySort,blockedTags[]} }`（:40-82）；导入为**合并式**、未知字段忽略、单项失败跳过（:113-169）。

---

## 5. 下载子系统 **[S]（格式可简化，队列/状态机语义保留）**

源码：`download/DownloadQueue.kt`（605 行）+ `util/ArchiveWriter.kt` + `util/PdfWriter.kt` + `download/DownloadService.kt`（前台通知，鸿蒙用常驻通知替代即可）。

### 5.1 队列模型（`DownloadQueue.kt:46-53,202-212`）

- **线性 FIFO**：一次只跑一个任务（`ensureWorker` 循环取第一个 `QUEUED`）；任务内**2 并发协程**下载图片（Semaphore(2)，:277）。
- 任务持久化 `meta/downloads.json`，写盘 600ms 去抖（:192-200）。
- **重启恢复语义**：init 时 `RUNNING/QUEUED` 任务一律改为 `FAILED`，error="已中断（应用重启）"（:100-111）——不做断点续传。

### 5.2 章节状态机（`State` :57；`runTask` :253-413）

```
QUEUED ──(worker取出)──> RUNNING ──(图片全部落盘)──> exporting=true（逐页导出）──> DONE
  │                         │                                        │
  └── 用户取消/删除 ────────┴──────────────> CANCELED <───────────────┘（导出中也可取消）
  任意阶段异常 ──> FAILED(error=msg)
```

- 字段：`Task { id(时间戳), albumId, title, state, done, total, failedPages, savedTo, savedUri, cover, createdAt, error, format(pdf/zip/7z/targz), level(0..5), pwdMode(none/fixed/random), fixedPwd, pwdStrategy(append/twolevel), exporting, exportDone, exportTotal }`（:59-81）。
- 删除任务：进行中先置 CANCELED + 清理临时文件；`deleteFile=true` 时同时删除已保存产物（:148-158）。

### 5.3 执行流程（`runTask` :253-413）

1. `JmApi.album(albumId)`（网络级重试 3 次，退避 500ms×i，:415-429）。
2. 遍历全部章节：`chapterImages(ep.id)` + `scrambleId(ep.id)`，汇总 `pages: [{photoId, filename, scrambleId}]`，`total` 随之增长（:261-269）。
3. 下载到临时目录 `{cacheDir}/pdf_{taskId}/{序号 %05d}.bin`（**存乱序原始字节**）；每页：先查本地缓存（手动下载目录/页缓存，>1KB 才算命中，`PageLoader.cachedRawFile` `PageLoader.kt:169-179`），未命中走网络换域名重试 3 次（:272-311）。
4. 导出（exporting 阶段，逐页回调进度）：
   - **PDF**（`buildPdf` :431-489）：逐页解码 → 反混淆（同 §3）→ 自研 PdfWriter 以 JPEG DCTDecode 嵌入（`PdfWriter.kt:78-174`；质量 visual=97/max=100/compact=90 且宽≤1240，:432-439）；缺失页生成 1240×1754 灰底占位、文字"第 N 页缺失"（:460-472）。逐页编码即 recycle，峰值内存≈单页。
   - **ZIP / 7z / tar.gz**（`ArchiveWriter.kt`）：逐条 provider 按需产出 `(文件名, 字节)`，内存恒定；级别映射 zip `[0,1,3,6,8,9]`、gz `[0,1,3,6,8,9]`、LZMA2 `[0,1,3,5,7,9]`（:126-128）；7z 支持 AES-256 密码（含加密文件名，:90-124）。**没有独立 CBZ 格式**——ZIP 按页序写图片文件即 CBZ 兼容结构，仅扩展名 `.zip`。
   - 压缩包图片质量档（`archiveEntry` :508-576）：`lossless` 像素无损（源 jpg→JPEG q100，否则 API30+ WebP 无损/低版 PNG）；`visual`（默认）/`compact` 有损重编码按**源扩展名**输出（源 jpg→JPEG q95/85，否则 WebP q95/80）；`raw` 原样直存不解密，附「说明.txt」（含加密提示与缺失页统计，:338-347）。
   - 7z 密码策略（:324-379）：`fixed` 用设置中的固定密码；`random` 生成 12 位随机密码（字符集 `abcdefghjkmnpqrstuvwxyzABCDEFGHJKMNPQRSTUVWXYZ23456789`，:503-505）；`append` 把" 密码xxx"追加到文件名；`twolevel` 内层加密 7z + 外层无密码 zip 附「解压密码.txt」。
5. 保存（`saveDownload` :578-604）：Android 10+ 走 MediaStore Downloads（RELATIVE_PATH 默认 `Download`，可配置）；文件名 `"JM{albumId} {标题(非法字符替换'_'，截80)}.{ext}"`（:491-494）。完成后清临时目录。

---

## 6. 域名/镜像与图片 CDN 切换 **[M]**

### 6.1 API 域名池（`JmApi.kt:157-227,626-632`）

- 内置兜底域名（`FALLBACK_DOMAINS` :80-86）：`www.cdnhjk.net`、`www.cdngwc.cc`、`www.cdngwc.net`、`www.cdngwc.club`、`www.cdnutc.me`。
- 启动：读缓存 `jm_domains`（逗号分隔）并与兜底合并去重（`withLastFirst` :220-227，上次成功域名置顶）→ 后台拉域名分发服务器（§2.1 末）刷新 → 后台拉 `/setting` 更新图片域名与版本号。全部异步不阻塞首屏（`init` :193-218）。
- 排序 `orderedDomains`（:163-168）：剔除隔离中的域名（连续失败 2 次 → 隔离 5 分钟），其余按失败次数升序；全隔离则退回全集。
- 成功域名移到队首并记 `jm_last_domain`（`rememberGoodDomain` :370-376）。

### 6.2 图片 CDN 池（`JmApi.kt:544-623`）

- 候选池 `allImgHosts`（:552-554）：有测速结果时 = 测速序前 4 + `/setting` 当前域名；否则 = 当前域名 + 6 个备用 CDN（`EXTRA_IMAGE_HOSTS` :71-78：`cdn-msp.jmapiproxy1.cc`、`cdn-msp.jmapiproxy2.cc`、`cdn-msp2.jmapiproxy2.cc`、`cdn-msp3.jmapiproxy2.cc`、`cdn-msp.jmapinodeudzn.net`、`cdn-msp3.jmapinodeudzn.net`）。默认当前域名 `cdn-msp.jmdanjonproxy.xyz`（:68）。
- **分流**：同一资源固定映射到同一 CDN——`hostForSeed(seed, retry)`（:606-611）：`idx = (javaStringHashCode(seed) & 0x7FFFFFFF) % pool.size`；`retry` 递增则 `idx += retry` 再取模。
  > ⚠ 移植注意：`String.hashCode()` 是 Java 算法（UTF-16 码元，h = 31*h + c，int32 溢出回绕），ArkTS 无内置，需手写实现，否则分流映射与原版不一致（不影响正确性，但影响缓存命中与行为一致性）。
- **健康探测**：启动后台对每个候选 CDN GET `/media/albums/1447694_3x4.jpg` 计时，按延迟排序存 `jm_host_order`，12 小时缓存（`testHostsIfStale` :647-678）；另有 30 分钟一次的轻量 HEAD 探测（`/media/albums/1475774_3x4.jpg`）维护运行时健康池（`refreshImageHostsAsync` :580-604）。
- **失败换域**：Coil 图片拦截器对 `/media/` 请求失败时 `nextImageHost` 轮换最多 2 次，仍失败 `reportImgHostFailure` 把该域名移出健康池并触发重探（`MoBaiApplication.kt:56-75`、`JmApi.kt:563-578`）。
- **跨域共享缓存**：Coil 缓存键去掉域名部分（`scheme://` 后第一段），同图不同 CDN 共享缓存（`MoBaiApplication.kt:93-103`）。
- 图片 URL 拼装（:613-623）：章节图 `https://{host}/media/photos/{photoId}/{filename}`（seed=`"{photoId}/{filename}"`）；封面大图 `/media/albums/{albumId}.jpg`；封面小图 `/media/albums/{albumId}_3x4.jpg`（列表/预览用，体积约 1/10）。

---

## 7. 关键数据模型汇总（`data/Models.kt`）

`Comic`（:5-13）、`JmCategory { id, name, slug, total }`（:15-20）、`JmAlbum { id, name, author[], tags[], likes, views, episodes[] }`（:22-32）、`Episode { id, title, sort }`（:34-40）、`JmComment`（:43-52）。收藏/历史条目结构见 §4。序列化均 JSON、`ignoreUnknownKeys`，向后兼容。

---

## 8. 建议鸿蒙版裁剪的网络能力 **[O]**

以下能力全部位于开发者模式/实验网络（`util/net/`），均为"抗 CN 网络封锁"手段，非业务依赖，API 层零耦合（只通过 `NetTweaks.apply` 挂钩 OkHttp Builder，`NetTweaks.kt:30-86`）：

| 能力 | 源码 | 裁剪理由（一句话） |
|------|------|--------------------|
| Tor 隧道插件 | `net/TunnelPluginClient.kt`、`plugin-tor/` 整个模块 | 依赖独立 APK + 手工 Binder + 签名级权限的 Android 插件生态，鸿蒙无对应机制且维护成本极高。 |
| WARP/MASQUE 隧道 | `net/MasqueManager.kt`、`net/WarpRegistrar.kt`、jniLibs `libusque.so` | 内核是 Android arm64 原生二进制不可复用，重交叉编译鸿蒙成本大，属小众实验特性。 |
| 自研 DoH | `net/DohDns.kt`（RFC1035 wire + RFC8484） | 鸿蒙系统 DNS 可用且该特性仅配合隧道/抗封锁场景，纯手写报文解析移植性价比低。 |
| SNI 切片/置空 | `net/NetTweaks.kt:60-85`、`net/DelegatingSocket.kt` | 依赖 Java SSLSocketFactory 逐层包装与 conscrypt 行为 hack，鸿蒙 TLS 栈不暴露等价扩展点。 |
| ECH 注入 | `net/NetTweaks.kt:253-281`（反射 conscrypt） | 基于 Android conscrypt 私有 API 反射，鸿蒙无此实现路径。 |
| 隧道 HUD/流量统计 | `net/TunnelStats.kt`、`ui/components/TunnelHud.kt` | 统计对象（隧道）已裁剪，连带失去意义。 |
| 内置浏览器 | `data/BrowserStore.kt`、`ui/browser/BrowserScreen.kt` | Android 原版 v0.8.4 已自行移除（README:113），无需移植。 |

裁剪后 `AppPrefs` 中 `tunnel_mode/tor_bridges/masque_*/doh_*/sni_*/ech_enabled/browser_*` 键一并省略；`JmApi.apiGet` 中 `MasqueManager.isRunning` 分支（隧道限 2 域名）固定按直连 3 域名处理（`JmApi.kt:324`）。

---

## 9. 移植核对清单（给数据层工程师）

1. token/AES：三处 md5+AES（API 信封、域名分发、scramble 页）key 都是 **hex 字符串的 ASCII 字节**；scramble 页密钥是 `18comicAPPContent`，其余是 `185Hcomic3PAPP7R`；域名分发是 `diosfjckwpqpdfjkvnqQjsik`。
2. 反混淆：`segments` 五步（§3.1）+ 带余数倒序重排（§3.2）+ **先原尺寸解密再缩放**（§3.3）。
3. 存储上限：历史 300 / 搜索历史 50 / 收藏无上限 / 页缓存 512MB / 封面缓存 2GB。
4. 下载：线性队列 + 2 并发 + 重启即 FAILED（不续传）+ 状态机 5 态。
5. 行为细节：18s API 总预算、域名失败隔离 5min、图片 CDN 固定 seed 分流 + 失败轮换、`_3x4` 小图、跨域缓存键。
