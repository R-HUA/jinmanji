/**
 * pages/ExplorePage.ets —— 发现首页（Tab1，直接嵌入 MainShell 的 Tabs，不经路由）。
 *
 * 功能映射（docs/feature-spec.md §2.1）：
 *  - E-01/M 吸顶光感搜索栏：品牌名 + 节点延迟状态灯 + 胶囊搜索入口（pushPathByName ROUTE_SEARCH）+ 榜单快捷入口
 *  - E-02/M 节点延迟状态灯：绿点 + xx ms，数据源 jmApi.testDomains()；点击展示当前镜像与测速值
 *  - E-03/M 热门榜单分段：日榜/周榜/月榜/总榜（mv_t/mv_w/mv_m/mv，jmApi.ranking("0", order, 1)）
 *  - E-04/M 榜单横滑卡片流 + 前 3 名金/银/铜数字角标
 *  - E-05/M 随机推荐区块 +「换一批」（jmApi.random() 本地洗牌；失败 Toast 且保留旧内容；
 *          换一批触发图标旋转 + 交错淡入；E-07 采用方案 A：并入发现区块，无独立页）
 *  - E-06/S 屏蔽过滤：blockTagsStore.isBlocked（title/author/category/categorySub 命中即隐藏）
 *  - E-08/M 最新更新 3 列封面网格 + 分页（任务指定：下拉刷新 + 上拉加载更多；
 *          E-09 的 PageBar 跳页降级为页码指示 + 加载更多/没有更多了页脚）
 *  - E-13/M 骨架屏：ComicCard loading 骨架态 + SkeletonGrid
 *  - E-14/M 首页缓存秒开：homeCacheStore 优先展示 → 网络刷新替换 → 失败保留旧缓存 + Toast
 *  - E-15/S 列表 cachedCount（系统 Image 自带缓存，不自研预取）
 *  - E-12/S 语言徽章启发式（移植 util/LangDetect.kt 的关键词 + 字符脚本判定，页面内实现）
 *
 * 参考原实现：jinmanji-app .../ui/home/HomeScreen.kt、ui/random/RandomScreen.kt、
 *            ui/components/ComicCard.kt、data/HomeCache.kt、util/LangDetect.kt。
 */

import { ROUTE_SEARCH, ROUTE_ALBUM } from '../common/Route';
import {
  PRIMARY,
  CARD,
  TEXT_MAIN,
  TEXT_SUB,
  CHIP_BG,
  TAB_INACTIVE,
  BAR_LIGHT,
  TAB_BAR_HEIGHT,
  CARD_R,
  CHIP_R,
  FONT_TITLE,
  FONT_CAPTION,
  FONT_BADGE,
  SPACE_XS,
  SPACE_S,
  SPACE_M,
  SPACE_L,
  SPACE_XL
} from '../common/Theme';
import { ComicCard, EmptyView, SkeletonGrid } from '../common/Components';
import { AlbumLite, RankingType, DomainSpeed, errorMessage } from '../models/Models';
import { jmApi } from '../data/JmApi';
import { homeCacheStore, blockTagsStore, HomeCacheData } from '../data/Stores';

/* ── 页面级功能色（Theme.ets 未提供奖牌色/状态绿 token——契约缺口，已集中声明并记入 notes）── */
/** 榜单第 1 名金色角标 */
const MEDAL_GOLD: string = '#F5B93C';
/** 榜单第 2 名银色角标 */
const MEDAL_SILVER: string = '#AFBAC7';
/** 榜单第 3 名铜色角标 */
const MEDAL_BRONZE: string = '#C98A5B';
/** 银色角标上的深色数字（保证对比度） */
const MEDAL_SILVER_TEXT: string = '#2F3A45';
/** 节点延迟灯正常色（E-02：绿点） */
const LAMP_GREEN: string = '#34C759';

/** 吸顶光感栏高度 vp */
const TOP_BAR_H: number = 52;
/** 榜单横滑卡片宽度 vp（3:4 封面 + 两行标题 + 作者行） */
const RANK_CARD_W: number = 108;
/** 随机推荐固定展示数量（2 行 × 3 列，其余留在本地池供洗牌） */
const RANDOM_GRID_COUNT: number = 6;

/* ── 语言/全彩徽章启发式（E-12 S 级；关键词表移植自 util/LangDetect.kt:36-52,79-81）── */
const KW_FULLCOLOR: Array<string> = ['全彩', 'フルカラー', 'full color', 'fullcolor', '彩漫', '彩色'];
const KW_ZH: Array<string> = ['中文', '漢化', '汉化', '中字', '中國', '中国', 'chinese', '汉化组', '漢化組', '翻譯組', '翻译组', '烤肉'];
const KW_JA: Array<string> = ['日本語', '日語', '日文', 'japanese', '生肉', '日版'];
const KW_KO: Array<string> = ['한국', '한글', 'korean', '韓文', '韩文', '번역'];
const KW_EN: Array<string> = ['english', '英文', '英譯', '英译', 'translated'];

function containsAny(hay: string, words: Array<string>): boolean {
  for (const w of words) {
    if (hay.indexOf(w) >= 0) {
      return true;
    }
  }
  return false;
}

/** 字符脚本判定（LangDetect.kt:63-73：谚文→韩 / 假名→日 / 汉字→中 / 拉丁≥4→英） */
function scriptBadge(text: string): string {
  let hangul: number = 0;
  let kana: number = 0;
  let han: number = 0;
  let latin: number = 0;
  for (let i: number = 0; i < text.length; i++) {
    const c: number = text.charCodeAt(i);
    if ((c >= 0xAC00 && c <= 0xD7AF) || (c >= 0x1100 && c <= 0x11FF) || (c >= 0x3130 && c <= 0x318F)) {
      hangul++;
    } else if ((c >= 0x3040 && c <= 0x309F) || (c >= 0x30A0 && c <= 0x30FF) || (c >= 0x31F0 && c <= 0x31FF)) {
      kana++;
    } else if ((c >= 0x4E00 && c <= 0x9FFF) || (c >= 0x3400 && c <= 0x4DBF)) {
      han++;
    } else if ((c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A)) {
      latin++;
    }
  }
  if (hangul > 0) {
    return '韩漫';
  }
  if (kana > 0) {
    return '日漫';
  }
  if (han > 0) {
    return '中字';
  }
  if (latin >= 4) {
    return 'EN';
  }
  return '';
}

/** 封面右上角文本徽章：全彩优先，其次语言关键词，最后脚本启发式（E-11/E-12） */
function badgeFor(item: AlbumLite): string {
  const hay: string = `${item.title} ${item.author} ${item.category} ${item.categorySub}`.toLowerCase();
  if (containsAny(hay, KW_FULLCOLOR)) {
    return '全彩';
  }
  if (containsAny(hay, KW_ZH)) {
    return '中字';
  }
  if (containsAny(hay, KW_JA)) {
    return '日漫';
  }
  if (containsAny(hay, KW_KO)) {
    return '韩漫';
  }
  if (containsAny(hay, KW_EN)) {
    return 'EN';
  }
  return scriptBadge(`${item.title}${item.author}`);
}

/** Fisher–Yates 洗牌（返回新数组；E-05 本地洗牌展示） */
function shuffle(list: Array<AlbumLite>): Array<AlbumLite> {
  const out: Array<AlbumLite> = list.slice();
  for (let i: number = out.length - 1; i > 0; i--) {
    const j: number = Math.floor(Math.random() * (i + 1));
    const tmp: AlbumLite = out[i];
    out[i] = out[j];
    out[j] = tmp;
  }
  return out;
}

/** 榜单分段定义（E-03：日/周/月/总 = mv_t/mv_w/mv_m/mv，JmApi.ranking 的 o 参数） */
class RankTab {
  order: RankingType;
  label: string;

  constructor(order: RankingType, label: string) {
    this.order = order;
    this.label = label;
  }
}

/** 路由参数（conventions §3 参数表；ArkTS 严格模式禁对象字面量传参，与 BookshelfPage 同款 class 方案） */
class SearchRouteParam {
  query: string = '';
}

class AlbumRouteParam {
  aid: string = '';
}

/** 「最新更新」网格的一行（3 列卡片 + 稳定 key） */
class AlbumRow {
  rowKey: string = '';
  cards: Array<AlbumLite> = [];
}

/** LazyForEach 数据源：最新更新按 3 列分行的行集合 */
class LatestRowSource implements IDataSource {
  private rows: Array<AlbumRow> = [];
  private listeners: Array<DataChangeListener> = [];

  totalCount(): number {
    return this.rows.length;
  }

  getData(index: number): AlbumRow {
    return this.rows[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((l: DataChangeListener) => l !== listener);
  }

  reload(items: Array<AlbumLite>): void {
    const newRows: Array<AlbumRow> = [];
    for (let i: number = 0; i < items.length; i += 3) {
      const row: AlbumRow = new AlbumRow();
      row.rowKey = `lat_row_${Math.floor(i / 3)}_${items[i].id}`;
      row.cards = items.slice(i, i + 3);
      newRows.push(row);
    }
    this.rows = newRows;
    for (const l of this.listeners) {
      l.onDataReloaded();
    }
  }
}

/** 随机推荐卡片：换一批后按索引交错淡入（E-05 交错淡入动效） */
@Component
struct RandomCardCell {
  @Prop aid: string = '';
  @Prop coverUrl: string = '';
  @Prop title: string = '';
  @Prop author: string = '';
  @Prop badge: string = '';
  @Prop delayMs: number = 0;
  onOpen: (aid: string) => void = () => {};
  @State appearOpacity: number = 0;

  build() {
    Column() {
      ComicCard({
        coverUrl: this.coverUrl,
        title: this.title,
        author: this.author,
        badge: this.badge,
        onCardClick: (): void => {
          this.onOpen(this.aid);
        }
      })
    }
    .width('100%')
    .opacity(this.appearOpacity)
    .onAppear(() => {
      this.getUIContext().animateTo({ duration: 300, delay: this.delayMs, curve: Curve.EaseOut }, () => {
        this.appearOpacity = 1;
      });
    })
  }
}

@Component
export struct ExplorePage {
  /** 全局路由栈（MainShell @Provide 下发，conventions §3） */
  @Consume('navPathStack') navPathStack: NavPathStack;

  /* ── 榜单区（E-03/E-04）── */
  @State currentRank: RankingType = 'mv_t';
  @State rankItems: Array<AlbumLite> = [];
  @State rankLoading: boolean = false;
  @State rankError: string = '';

  /* ── 随机推荐区（E-05）── */
  @State randomItems: Array<AlbumLite> = [];
  @State randomLoading: boolean = false;
  @State randomError: string = '';
  /** 洗牌批次号：进入 ForEach key，换一批后重建卡片以重放交错淡入 */
  @State randomSeed: number = 0;
  @State refreshAngle: number = 0;

  /* ── 最新更新区（E-08）── */
  @State latestItems: Array<AlbumLite> = [];
  @State latestPage: number = 1;
  @State latestLoading: boolean = false;
  @State latestMoreLoading: boolean = false;
  @State latestMoreError: boolean = false;
  @State latestHasMore: boolean = true;
  @State latestError: string = '';

  /* ── 页面级（E-13/E-14 四态）── */
  @State pageLoading: boolean = false;
  @State pageError: string = '';
  @State refreshing: boolean = false;

  /* ── 节点延迟灯（E-02）── */
  @State latencyMs: number = -1;
  @State latencyDomain: string = '';

  /* ── 非渲染成员 ── */
  private randomPool: Array<AlbumLite> = [];
  private rankCache: Map<string, Array<AlbumLite>> = new Map<string, Array<AlbumLite>>();
  private rankSeq: number = 0;
  private latestSource: LatestRowSource = new LatestRowSource();
  private scroller: Scroller = new Scroller();
  private rankTabs: Array<RankTab> = [
    new RankTab('mv_t', '日榜'),
    new RankTab('mv_w', '周榜'),
    new RankTab('mv_m', '月榜'),
    new RankTab('mv', '总榜')
  ];

  aboutToAppear(): void {
    this.initFlow().catch((e: Error) => {
      console.info(`[ExplorePage] 初始化失败: ${errorMessage(e)}`);
    });
  }

  /* ───────────────────────── 数据流（缓存优先 → 网络刷新 → 失败保留，E-14） ───────────────────────── */

  private async initFlow(): Promise<void> {
    try {
      const cached: HomeCacheData | null = await homeCacheStore.load();
      if (cached !== null) {
        if (cached.ranking.length > 0) {
          this.rankItems = cached.ranking;
          this.rankCache.set('mv_t', cached.ranking);
        }
        if (cached.random.length > 0) {
          this.randomPool = cached.random;
          this.applyRandomBatch();
        }
        if (cached.latest.length > 0) {
          this.setLatestItems(cached.latest);
        }
      }
    } catch (e) {
      console.info(`[ExplorePage] 首页缓存读取失败: ${errorMessage(e as Error)}`);
    }
    this.rankLoading = this.rankItems.length === 0;
    this.randomLoading = this.randomItems.length === 0;
    this.latestLoading = this.latestItems.length === 0;
    this.pageLoading = this.rankItems.length === 0
      && this.randomItems.length === 0 && this.latestItems.length === 0;
    this.measureLatency().catch((e: Error) => {
      console.info(`[ExplorePage] 测速失败: ${errorMessage(e)}`);
    });
    await this.refreshAll(false);
  }

  /** 三区并发刷新；每区自行捕获错误（对应 HomeStore.load + 缓存覆写语义） */
  private async refreshAll(manual: boolean): Promise<void> {
    const tasks: Array<Promise<boolean>> = [
      this.fetchRanking(this.currentRank, true),
      this.fetchRandom(manual),
      this.fetchLatestPage(1, false)
    ];
    const ok: Array<boolean> = await Promise.all(tasks);
    const allEmpty: boolean = this.rankItems.length === 0
      && this.randomItems.length === 0 && this.latestItems.length === 0;
    if (allEmpty && (this.rankError !== '' || this.randomError !== '' || this.latestError !== '')) {
      // 空 + 失败 → 整页错误态 + 重试（HomeScreen.kt:128-141）
      this.pageError = this.rankError !== '' ? this.rankError
        : (this.randomError !== '' ? this.randomError : this.latestError);
    } else if (!allEmpty && (ok[0] || ok[1] || ok[2])) {
      try {
        await homeCacheStore.save(this.randomPool.slice(0, 12), this.rankItems.slice(0, 30),
          this.latestItems.slice(0, 60));
      } catch (e) {
        console.info(`[ExplorePage] 首页缓存写入失败: ${errorMessage(e as Error)}`);
      }
    }
    this.pageLoading = false;
    this.refreshing = false;
  }

  private async fetchRanking(order: RankingType, skeleton: boolean): Promise<boolean> {
    const seq: number = ++this.rankSeq;
    const cached: Array<AlbumLite> | undefined = this.rankCache.get(order);
    if (cached !== undefined && cached.length > 0 && this.rankItems.length === 0) {
      this.rankItems = cached;
    }
    if (skeleton && this.rankItems.length === 0) {
      this.rankLoading = true;
    }
    this.rankError = '';
    try {
      const list: Array<AlbumLite> = await jmApi.ranking('0', order, 1);
      if (seq !== this.rankSeq) {
        return false;
      }
      const filtered: Array<AlbumLite> = await this.filterBlocked(list);
      this.rankCache.set(order, filtered);
      this.rankItems = filtered;
      return true;
    } catch (e) {
      if (seq !== this.rankSeq) {
        return false;
      }
      const msg: string = errorMessage(e as Error);
      if (this.rankItems.length === 0) {
        this.rankError = msg;
      } else {
        this.toast(`榜单刷新失败，已保留旧内容：${msg}`);
      }
      return false;
    } finally {
      if (seq === this.rankSeq) {
        this.rankLoading = false;
      }
    }
  }

  private async fetchRandom(manual: boolean): Promise<boolean> {
    this.randomLoading = true;
    try {
      const list: Array<AlbumLite> = await jmApi.random();
      const filtered: Array<AlbumLite> = await this.filterBlocked(list);
      if (filtered.length > 0) {
        this.randomPool = filtered;
        this.applyRandomBatch();
        this.randomError = '';
      } else {
        this.randomPool = [];
        this.randomItems = [];
      }
      return true;
    } catch (e) {
      const msg: string = errorMessage(e as Error);
      if (this.randomItems.length === 0) {
        this.randomError = msg;
      } else {
        // E-05：失败 Toast 提示且保留旧内容（HomeStore.refreshRandom 行为）
        this.toast(manual ? `换一批失败，已保留旧内容：${msg}` : `随机推荐刷新失败，已保留旧内容：${msg}`);
      }
      return false;
    } finally {
      this.randomLoading = false;
    }
  }

  private async fetchLatestPage(page: number, isMore: boolean): Promise<boolean> {
    if (isMore) {
      this.latestMoreLoading = true;
      this.latestMoreError = false;
    } else if (this.latestItems.length === 0) {
      this.latestLoading = true;
    }
    try {
      const list: Array<AlbumLite> = await jmApi.latest(page);
      const filtered: Array<AlbumLite> = await this.filterBlocked(list);
      if (page === 1) {
        this.setLatestItems(filtered);
        this.latestPage = 1;
      } else if (filtered.length > 0) {
        this.appendLatest(filtered);
        this.latestPage = page;
      }
      this.latestHasMore = list.length > 0;
      return true;
    } catch (e) {
      const msg: string = errorMessage(e as Error);
      if (this.latestItems.length === 0) {
        this.latestError = msg;
      } else if (isMore) {
        this.latestMoreError = true;
      } else {
        this.toast(`最新更新刷新失败，已保留旧内容：${msg}`);
      }
      return false;
    } finally {
      this.latestLoading = false;
      this.latestMoreLoading = false;
    }
  }

  /** 屏蔽词过滤（E-06：title/author/category/categorySub 命中即隐藏） */
  private async filterBlocked(list: Array<AlbumLite>): Promise<Array<AlbumLite>> {
    const out: Array<AlbumLite> = [];
    for (const it of list) {
      const blocked: boolean = await blockTagsStore.isBlocked(it.title, it.author, it.category, it.categorySub);
      if (!blocked) {
        out.push(it);
      }
    }
    return out;
  }

  private setLatestItems(items: Array<AlbumLite>): void {
    this.latestItems = items.slice();
    this.latestSource.reload(this.latestItems);
  }

  private appendLatest(adds: Array<AlbumLite>): void {
    const ids: Array<string> = [];
    for (const it of this.latestItems) {
      ids.push(it.id);
    }
    const merged: Array<AlbumLite> = this.latestItems.slice();
    for (const it of adds) {
      if (ids.indexOf(it.id) < 0) {
        merged.push(it);
        ids.push(it.id);
      }
    }
    this.latestItems = merged;
    this.latestSource.reload(this.latestItems);
  }

  private loadMoreLatest(): void {
    if (this.pageLoading || this.latestLoading || this.latestMoreLoading) {
      return;
    }
    if (!this.latestHasMore || this.latestItems.length === 0) {
      return;
    }
    this.fetchLatestPage(this.latestPage + 1, true).catch((e: Error) => {
      console.info(`[ExplorePage] 加载更多失败: ${errorMessage(e)}`);
    });
  }

  /** 随机推荐本地洗牌出固定数量展示（E-05） */
  private applyRandomBatch(): void {
    const pool: Array<AlbumLite> = shuffle(this.randomPool);
    this.randomSeed++;
    this.randomItems = pool.slice(0, RANDOM_GRID_COUNT);
  }

  /** 节点测速（E-02：数据源 = jmApi.testDomains 镜像测速结果 SET-22/SET-28） */
  private async measureLatency(): Promise<void> {
    try {
      const list: Array<DomainSpeed> = await jmApi.testDomains();
      if (list.length > 0) {
        this.latencyDomain = list[0].domain;
        this.latencyMs = list[0].ok ? list[0].ms : -1;
      }
    } catch (e) {
      this.latencyMs = -1;
    }
  }

  /* ───────────────────────── 交互 ───────────────────────── */

  private openSearch(): void {
    const param: SearchRouteParam = new SearchRouteParam();
    this.navPathStack.pushPathByName(ROUTE_SEARCH, param);
  }

  private openAlbum(aid: string): void {
    const param: AlbumRouteParam = new AlbumRouteParam();
    param.aid = aid;
    this.navPathStack.pushPathByName(ROUTE_ALBUM, param);
  }

  /** 顶栏「榜单」入口：平滑滚动回榜单区（列表首区，E-07 方案 A 的滚动定位） */
  private scrollToRanking(): void {
    this.scroller.scrollToIndex(0, true, ScrollAlign.START);
  }

  private onRankTabTap(order: RankingType): void {
    if (this.currentRank === order) {
      return;
    }
    this.currentRank = order;
    const cached: Array<AlbumLite> | undefined = this.rankCache.get(order);
    if (cached !== undefined && cached.length > 0) {
      this.rankItems = cached;
      this.rankLoading = false;
      this.rankError = '';
    } else {
      this.rankItems = [];
      this.rankLoading = true;
      this.rankError = '';
    }
    this.fetchRanking(order, false).catch((e: Error) => {
      console.info(`[ExplorePage] 榜单切换加载失败: ${errorMessage(e)}`);
    });
  }

  private onShuffleTap(): void {
    if (this.randomLoading) {
      return;
    }
    // 换一批：图标旋转动效 + 重新请求并洗牌（E-05）
    this.getUIContext().animateTo({ duration: 450, curve: Curve.EaseInOut }, () => {
      this.refreshAngle += 360;
    });
    this.fetchRandom(true).catch((e: Error) => {
      console.info(`[ExplorePage] 换一批失败: ${errorMessage(e)}`);
    });
  }

  private showNodeInfo(): void {
    const message: string = this.latencyMs >= 0
      ? `镜像域名：${this.latencyDomain}\n最近测速：${this.latencyMs} ms`
      : '正在测速或测速失败，可点击「重新测速」';
    this.getUIContext().showAlertDialog({
      title: '当前节点',
      message: message,
      alignment: DialogAlignment.Default,
      buttons: [
        {
          value: '重新测速',
          action: (): void => {
            this.measureLatency().catch((e: Error) => {
              console.info(`[ExplorePage] 重新测速失败: ${errorMessage(e)}`);
            });
          }
        },
        {
          value: '知道了',
          action: (): void => {
          }
        }
      ]
    });
  }

  private retryPage(): void {
    this.pageError = '';
    this.rankError = '';
    this.randomError = '';
    this.latestError = '';
    this.rankLoading = this.rankItems.length === 0;
    this.randomLoading = this.randomItems.length === 0;
    this.latestLoading = this.latestItems.length === 0;
    this.refreshAll(true).catch((e: Error) => {
      console.info(`[ExplorePage] 重试失败: ${errorMessage(e)}`);
    });
  }

  private retryRanking(): void {
    this.rankError = '';
    this.rankLoading = this.rankItems.length === 0;
    this.fetchRanking(this.currentRank, true).catch((e: Error) => {
      console.info(`[ExplorePage] 榜单重试失败: ${errorMessage(e)}`);
    });
  }

  private retryRandom(): void {
    this.randomError = '';
    this.randomLoading = this.randomItems.length === 0;
    this.fetchRandom(true).catch((e: Error) => {
      console.info(`[ExplorePage] 随机重试失败: ${errorMessage(e)}`);
    });
  }

  private retryLatestInitial(): void {
    this.latestError = '';
    this.latestLoading = this.latestItems.length === 0;
    this.fetchLatestPage(1, false).catch((e: Error) => {
      console.info(`[ExplorePage] 最新重试失败: ${errorMessage(e)}`);
    });
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 2000, bottom: '38%' });
    } catch (e) {
      console.info(`[ExplorePage] Toast 显示失败: ${errorMessage(e as Error)}`);
    }
  }

  /* ───────────────────────── 布局辅助 ───────────────────────── */

  private chunkRows(items: Array<AlbumLite>, size: number): Array<Array<AlbumLite>> {
    const rows: Array<Array<AlbumLite>> = [];
    for (let i: number = 0; i < items.length; i += size) {
      rows.push(items.slice(i, i + size));
    }
    return rows;
  }

  private fillerIndexes(count: number): Array<number> {
    const list: Array<number> = [];
    for (let i: number = 0; i < count; i++) {
      list.push(i);
    }
    return list;
  }

  /* ───────────────────────── Builders ───────────────────────── */

  /** 吸顶光感栏（E-01）：品牌 + 延迟灯（E-02）+ 胶囊搜索入口 + 榜单入口 */
  @Builder
  TopBar() {
    Row({ space: SPACE_M }) {
      Column({ space: 1 }) {
        Text('禁漫姬')
          .fontSize(FONT_TITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_MAIN)
          .maxLines(1)
        Row({ space: 3 }) {
          Text('●')
            .fontSize(9)
            .fontColor(this.latencyMs >= 0 ? LAMP_GREEN : TAB_INACTIVE)
          Text(this.latencyMs >= 0 ? `${this.latencyMs} ms` : '测速中…')
            .fontSize(FONT_BADGE)
            .fontColor(TEXT_SUB)
            .maxLines(1)
        }
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          this.showNodeInfo();
        })
      }
      .alignItems(HorizontalAlign.Start)

      Row({ space: SPACE_S }) {
        Text('🔍')
          .fontSize(13)
        Text('搜索漫画名、作者或 JM 编号直达')
          .fontSize(FONT_CAPTION)
          .fontColor(TEXT_SUB)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      .layoutWeight(1)
      .height(34)
      .padding({ left: 12, right: 12 })
      .backgroundColor(CHIP_BG)
      .borderRadius(CHIP_R)
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.openSearch();
      })

      Text('🏆 榜单')
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(TEXT_MAIN)
        .padding({ top: 6, bottom: 6 })
        .maxLines(1)
        .onClick(() => {
          this.scrollToRanking();
        })
    }
    .width('100%')
    .height(TOP_BAR_H)
    .padding({ left: SPACE_L, right: SPACE_M })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(BAR_LIGHT)
    .backgroundBlurStyle(BlurStyle.Regular)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
  }

  /** 榜单分段（E-03：日/周/月/总，等价 SegmentButton 的稳定 API 实现） */
  @Builder
  RankSegments() {
    Row({ space: 2 }) {
      ForEach(this.rankTabs, (tab: RankTab) => {
        Text(tab.label)
          .fontSize(13)
          .fontWeight(this.currentRank === tab.order ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(this.currentRank === tab.order ? TEXT_MAIN : TEXT_SUB)
          .padding({ left: 14, right: 14, top: 6, bottom: 6 })
          .backgroundColor(this.currentRank === tab.order ? CARD : Color.Transparent)
          .borderRadius(CHIP_R - 3)
          .onClick(() => {
            this.onRankTabTap(tab.order);
          })
      }, (tab: RankTab) => 'seg_' + tab.order)
    }
    .padding(3)
    .backgroundColor(CHIP_BG)
    .borderRadius(CHIP_R)
    .margin({ left: SPACE_L })
  }

  /** 前 3 名数字角标（E-04：金/银/铜） */
  @Builder
  MedalBadge(rank: number) {
    Text(rank.toString())
      .fontSize(13)
      .fontWeight(FontWeight.Bold)
      .fontColor(rank === 2 ? MEDAL_SILVER_TEXT : Color.White)
      .textAlign(TextAlign.Center)
      .width(22)
      .height(22)
      .borderRadius(11)
      .backgroundColor(rank === 1 ? MEDAL_GOLD : (rank === 2 ? MEDAL_SILVER : MEDAL_BRONZE))
      .margin(6)
  }

  /** 榜单横滑卡片流（E-04：横向胶片 List + cachedCount） */
  @Builder
  RankCardList() {
    List({ space: SPACE_M }) {
      ForEach(this.rankItems, (it: AlbumLite, index: number) => {
        ListItem() {
          Stack({ alignContent: Alignment.TopStart }) {
            ComicCard({
              coverUrl: it.coverUrl,
              title: it.title,
              author: it.author,
              badge: badgeFor(it),
              onCardClick: (): void => {
                this.openAlbum(it.id);
              }
            })
            if (index < 3) {
              this.MedalBadge(index + 1)
            }
          }
          .width(RANK_CARD_W)
        }
      }, (it: AlbumLite) => 'rank_' + it.id)
    }
    .listDirection(Axis.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .padding({ left: SPACE_L, right: SPACE_L })
    .cachedCount(3)
  }

  /** 榜单骨架（E-13：ComicCard loading 骨架态） */
  @Builder
  RankSkeleton() {
    List({ space: SPACE_M }) {
      ForEach(this.fillerIndexes(4), (i: number) => {
        ListItem() {
          Column() {
            ComicCard({ loading: true })
          }
          .width(RANK_CARD_W)
        }
      }, (i: number) => 'rksk_' + i.toString())
    }
    .listDirection(Axis.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .padding({ left: SPACE_L, right: SPACE_L })
    .cachedCount(2)
  }

  /** 区块级错误行：错误信息 + 重试（conventions §8 错误态） */
  @Builder
  SectionErrorRow(message: string, onRetry: () => void) {
    Row({ space: SPACE_M }) {
      Text(message)
        .fontSize(FONT_CAPTION)
        .fontColor(TEXT_SUB)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      Text('重试')
        .fontSize(FONT_CAPTION)
        .fontColor(PRIMARY)
        .padding({ left: SPACE_M, right: SPACE_M, top: SPACE_S, bottom: SPACE_S })
        .onClick(() => {
          onRetry();
        })
    }
    .width('100%')
    .padding({ left: SPACE_L, right: SPACE_M, top: SPACE_S, bottom: SPACE_S })
    .backgroundColor(CARD)
    .borderRadius(CARD_R)
    .margin({ left: SPACE_L, right: SPACE_L })
  }

  /** 热门榜单区（E-03/E-04） */
  @Builder
  RankingSection() {
    Column({ space: SPACE_M }) {
      Text('热门榜单')
        .fontSize(FONT_TITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(TEXT_MAIN)
        .padding({ left: SPACE_L })
      this.RankSegments()
      if (this.rankLoading && this.rankItems.length === 0) {
        this.RankSkeleton()
      } else if (this.rankError !== '' && this.rankItems.length === 0) {
        this.SectionErrorRow(this.rankError, (): void => {
          this.retryRanking();
        })
      } else if (this.rankItems.length === 0) {
        Text('榜单暂无内容')
          .fontSize(FONT_CAPTION)
          .fontColor(TEXT_SUB)
          .padding({ left: SPACE_L })
      } else {
        this.RankCardList()
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 随机推荐骨架（E-13） */
  @Builder
  RandomSkeleton() {
    Column({ space: SPACE_M }) {
      ForEach(this.fillerIndexes(2), (r: number) => {
        Row({ space: SPACE_L }) {
          ForEach(this.fillerIndexes(3), (c: number) => {
            Column() {
              ComicCard({ loading: true })
            }
            .layoutWeight(1)
          }, (c: number) => `rnsk_${r}_${c}`)
        }
        .width('100%')
        .padding({ left: SPACE_L, right: SPACE_L })
      }, (r: number) => 'rnsk_row_' + r.toString())
    }
    .width('100%')
  }

  /** 随机推荐网格（2 行 × 3 列；key 含 randomSeed，换一批后重放交错淡入） */
  @Builder
  RandomGrid() {
    Column({ space: SPACE_M }) {
      ForEach(this.chunkRows(this.randomItems, 3), (row: Array<AlbumLite>, rIdx: number) => {
        Row({ space: SPACE_L }) {
          ForEach(row, (it: AlbumLite, cIdx: number) => {
            Column() {
              RandomCardCell({
                aid: it.id,
                coverUrl: it.coverUrl,
                title: it.title,
                author: it.author,
                badge: badgeFor(it),
                delayMs: (rIdx * 3 + cIdx) * 70,
                onOpen: (aid: string): void => {
                  this.openAlbum(aid);
                }
              })
            }
            .layoutWeight(1)
          }, (it: AlbumLite) => `rand_${this.randomSeed}_${it.id}`)
          ForEach(this.fillerIndexes(3 - row.length), (k: number) => {
            Column()
              .layoutWeight(1)
          }, (k: number) => `rf_${this.randomSeed}_${k}`)
        }
        .width('100%')
        .padding({ left: SPACE_L, right: SPACE_L })
      }, (row: Array<AlbumLite>) => `randrow_${this.randomSeed}_${row[0].id}`)
    }
    .width('100%')
  }

  /** 随机推荐区（E-05：「随机推荐 + ⟳ 换一批」区块头） */
  @Builder
  RandomSection() {
    Column({ space: SPACE_M }) {
      Row() {
        Text('随机推荐')
          .fontSize(FONT_TITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_MAIN)
          .layoutWeight(1)
        Row({ space: SPACE_S }) {
          Text('⟳')
            .fontSize(15)
            .fontColor(PRIMARY)
            .rotate({ angle: this.refreshAngle, centerX: '50%', centerY: '50%' })
          Text('换一批')
            .fontSize(13)
            .fontColor(PRIMARY)
          if (this.randomLoading) {
            LoadingProgress()
              .width(14)
              .height(14)
              .color(PRIMARY)
          }
        }
        .padding({ left: 12, right: 12, top: 5, bottom: 5 })
        .backgroundColor(CHIP_BG)
        .borderRadius(CHIP_R)
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          this.onShuffleTap();
        })
      }
      .width('100%')
      .padding({ left: SPACE_L, right: SPACE_M })

      if (this.randomLoading && this.randomItems.length === 0) {
        this.RandomSkeleton()
      } else if (this.randomError !== '' && this.randomItems.length === 0) {
        this.SectionErrorRow(this.randomError, (): void => {
          this.retryRandom();
        })
      } else if (this.randomItems.length === 0) {
        Text('点击「换一批」看看有什么新发现')
          .fontSize(FONT_CAPTION)
          .fontColor(TEXT_SUB)
          .padding({ left: SPACE_L })
      } else {
        this.RandomGrid()
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 最新更新区头：标题 + 页码指示（E-09 简化）+ 首屏骨架/错误/空态 */
  @Builder
  LatestHeader() {
    Column({ space: SPACE_M }) {
      Row() {
        Text('最新更新')
          .fontSize(FONT_TITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_MAIN)
          .layoutWeight(1)
        Text(`第 ${this.latestPage} 页`)
          .fontSize(FONT_CAPTION)
          .fontColor(TEXT_SUB)
      }
      .width('100%')
      .padding({ left: SPACE_L, right: SPACE_L })

      if (this.latestLoading && this.latestItems.length === 0) {
        SkeletonGrid({ columns: 3, rows: 3 })
          .padding({ left: SPACE_L, right: SPACE_L })
      } else if (this.latestError !== '' && this.latestItems.length === 0) {
        this.SectionErrorRow(this.latestError, (): void => {
          this.retryLatestInitial();
        })
      } else if (this.latestItems.length === 0) {
        Text('暂无更新，下拉刷新试试')
          .fontSize(FONT_CAPTION)
          .fontColor(TEXT_SUB)
          .padding({ left: SPACE_L })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 最新更新网格的一行（3 列，不足位补空白占位） */
  @Builder
  LatestRow(row: AlbumRow) {
    Row({ space: SPACE_L }) {
      ForEach(row.cards, (it: AlbumLite) => {
        Column() {
          ComicCard({
            coverUrl: it.coverUrl,
            title: it.title,
            author: it.author,
            badge: badgeFor(it),
            onCardClick: (): void => {
              this.openAlbum(it.id);
            }
          })
        }
        .layoutWeight(1)
      }, (it: AlbumLite) => 'lat_' + it.id)
      ForEach(this.fillerIndexes(3 - row.cards.length), (k: number) => {
        Column()
          .layoutWeight(1)
      }, (k: number) => `lf_${row.rowKey}_${k}`)
    }
    .width('100%')
    .padding({ left: SPACE_L, right: SPACE_L, top: SPACE_S, bottom: SPACE_S })
  }

  /** 底部页脚：加载更多 / 失败重试 / 没有更多了（conventions §8 分页态） */
  @Builder
  LatestFooter() {
    Column({ space: SPACE_XS }) {
      if (this.latestMoreLoading) {
        Row({ space: SPACE_S }) {
          LoadingProgress()
            .width(18)
            .height(18)
            .color(PRIMARY)
          Text('加载中…')
            .fontSize(FONT_CAPTION)
            .fontColor(TEXT_SUB)
        }
        .alignItems(VerticalAlign.Center)
      } else if (this.latestMoreError) {
        Text('加载失败，点击重试')
          .fontSize(FONT_CAPTION)
          .fontColor(PRIMARY)
          .padding({ top: SPACE_S, bottom: SPACE_S })
          .onClick(() => {
            this.loadMoreLatest();
          })
      } else if (this.latestItems.length > 0 && !this.latestHasMore) {
        Text('— 没有更多了 —')
          .fontSize(FONT_CAPTION)
          .fontColor(TEXT_SUB)
        Text(`已加载 ${this.latestItems.length} 部作品`)
          .fontSize(FONT_BADGE)
          .fontColor(TEXT_SUB)
      } else if (this.latestItems.length > 0 && this.latestHasMore) {
        Text('上拉加载更多')
          .fontSize(FONT_BADGE)
          .fontColor(TEXT_SUB)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding({ top: SPACE_S, bottom: TAB_BAR_HEIGHT + SPACE_XL })
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      if (this.pageError !== '') {
        // 整页错误态：空 + 失败（HomeScreen.kt:128-141 语义）
        Column() {
          EmptyView({
            message: this.pageError,
            retryText: '重试',
            showRetry: true,
            onRetry: (): void => {
              this.retryPage();
            }
          })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .padding({ bottom: TAB_BAR_HEIGHT })
      } else {
        // 主滚动流：下拉刷新（E-14 刷新）+ 上拉加载更多（E-08 分页）
        Refresh({ refreshing: $$this.refreshing, offset: 14, friction: 42 }) {
          List({ space: SPACE_M, scroller: this.scroller }) {
            ListItem() {
              // 吸顶栏下方让位（列表从光感栏底下滚过）
              Column()
                .height(TOP_BAR_H + SPACE_S)
            }
            ListItem() {
              this.RankingSection()
            }
            ListItem() {
              this.RandomSection()
            }
            ListItem() {
              this.LatestHeader()
            }
            LazyForEach(this.latestSource, (row: AlbumRow) => {
              ListItem() {
                this.LatestRow(row)
              }
            }, (row: AlbumRow) => row.rowKey)
            ListItem() {
              this.LatestFooter()
            }
          }
          .width('100%')
          .height('100%')
          .cachedCount(4)
          .scrollBar(BarState.Off)
          .onReachEnd(() => {
            this.loadMoreLatest();
          })
        }
        .width('100%')
        .height('100%')
        .onRefreshing(() => {
          this.refreshAll(true).catch((e: Error) => {
            console.info(`[ExplorePage] 下拉刷新失败: ${errorMessage(e)}`);
            this.refreshing = false;
          });
        })
      }
      this.TopBar()
    }
    .width('100%')
    .height('100%')
  }
}
