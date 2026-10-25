/**
 * pages/ReaderPage.ets —— 全屏沉浸式漫画阅读器（阅读器工程师）。
 *
 * 功能矩阵（docs/feature-spec.md §3 / uiux-design.md §四.3）：
 *  R-00 路由参数 {aid, chapterId?, chapterIndex?, page?}，章节列表 AlbumCache 优先，续读定位（M）
 *  R-01 纵向条漫：List + LazyForEach + cachedCount（M）
 *  R-02 左右翻页：Swiper LTR 单页适配（M）
 *  R-03/R-04/R-05 模式枚举 vertical/horizontal/rtl/double 可切换并持久化（rtl/double 为 S 级：
 *       保留枚举与切换，渲染与横向翻页相同，feature-spec R-04 原文「渲染与横向模式相同」）
 *  R-06 点按三分热区：中央=HUD 显隐；两侧=翻页/滚动一屏；日漫右翻自动镜像（M）
 *  R-07/R-08/R-10 上下双层光感 HUD + 进度 Slider（拖动实时页码、松手跳转）+ 四大金刚（M）
 *  R-11 目录 bindSheet 章节列表直达（M）
 *  R-12/R-13 亮度应用内遮罩 + 背景黑/米黄切换（S；米黄为一次性色，Theme 无此 token）
 *  R-16 设置面板：预加载档位（M 入口 + S 项）
 *  R-17 HUD 隐藏时右下角微型页码胶囊（M）
 *  R-18/R-19 尾部「本章完 + 上一章/下一章」+ HUD 上一话/下一话，边界去往提示（M）
 *  R-20 续读：进入恢复进度，阅读中节流写入 readProgressStore（M，鸿蒙新增 B-03）
 *  R-21/R-22/R-23 恒预加载后 N 页 + 下一章预载 + PagesCache 秒开失败保留（M）
 *  R-24 图片链路：jmApi 章节分页 + ImageDecode.loadPagePixelMap（网络字节→原尺寸重排→缩放）
 *  R-25 单页三态：加载/失败点按重试/成功（M）
 *  R-26 双指缩放：PinchGesture 1x~5x + 双指平移边界回弹（S；HUD 顶栏「x.x · 重置」入口，
 *       双击放大按 conventions §7 简化不做）
 *  R-27 expandSafeArea 全屏 + READER_BG 深色背景（M）
 *
 * 参考原实现：jinmanji-app .../ui/reader/ReaderScreen.kt（加载顺序/预取/边界语义逐段对应）。
 */
import display from '@ohos.display';
import image from '@ohos.multimedia.image';

import { window } from '@kit.ArkUI';
import { EmptyView } from '../common/Components';
import {
  READER_BG, MASK_DARK, PRIMARY, ACCENT, TEXT_MAIN, CHIP_R, CARD_R
} from '../common/Theme';
import {
  Album,
  Chapter,
  ReadingProgress,
  ReaderMode,
  asNumber,
  asRecord,
  asString,
  errorMessage
} from '../models/Models';
import { jmApi } from '../data/JmApi';
import { loadPagePixelMap } from '../data/ImageDecode';
import { albumCacheStore, pagesCacheStore, readProgressStore } from '../data/Stores';
import { Prefs, getAppContext } from '../util/Prefs';

/** 默认乱序参数（与云端值算法等价；ReaderScreen.kt:99/202） */
const SCRAMBLE_DEFAULT: number = 220980;
/** 护眼米黄背景（R-13 S 级一次性色，Theme 契约未提供 token） */
const PAPER_BG: string = '#F5EFE2';
/** 单页占位底色（阅读器深色画布内的一次性色） */
const PLACEHOLDER_BG: string = '#16161A';
/** 单页失败占位底色 */
const FAILED_BG: string = '#201619';
/** HUD 内层面板底色（一次性深色 rgba） */
const PANEL_BG: string = 'rgba(28,28,32,0.82)';
/** 进度节流间隔 ms */
const SAVE_THROTTLE_MS: number = 2000;
/** R-26 缩放范围（ReaderScreen.kt:104-118：scale ∈ [1,5]） */
const ZOOM_MIN: number = 1;
const ZOOM_MAX: number = 5;

// ───────────────────────── LazyForEach 数据源 ─────────────────────────

/** 章节图片文件名列表数据源（R-01 长列表懒加载） */
class PageListSource implements IDataSource {
  private list: Array<string> = [];
  private listeners: Array<DataChangeListener> = [];

  constructor(list: Array<string> = []) {
    this.list = list;
  }

  public totalCount(): number {
    return this.list.length;
  }

  public getData(index: number): string {
    return this.list[index];
  }

  public registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  public unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((l: DataChangeListener) => l !== listener);
  }

  public setList(list: Array<string>): void {
    this.list = list;
    for (const l of this.listeners) {
      l.onDataReloaded();
    }
  }
}

/** 章节目录数据源（R-11 目录半模态） */
class ChapterSource implements IDataSource {
  private list: Array<Chapter> = [];
  private listeners: Array<DataChangeListener> = [];

  constructor(list: Array<Chapter> = []) {
    this.list = list;
  }

  public totalCount(): number {
    return this.list.length;
  }

  public getData(index: number): Chapter {
    return this.list[index];
  }

  public registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  public unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((l: DataChangeListener) => l !== listener);
  }

  public setList(list: Array<Chapter>): void {
    this.list = list;
    for (const l of this.listeners) {
      l.onDataReloaded();
    }
  }
}

// ───────────────────────── 子组件 ─────────────────────────

/**
 * 单页渲染（R-24/R-25）：字节 → 原尺寸反混淆 → 缩放为 PixelMap 再显示（ImageDecode 整链路）。
 * 三态：加载（灰底 + 转圈）/ 失败（点按重试，fetchPageBytes 内部自动换图床域名 3 次）/ 成功。
 * scrambleId/photoId/filename 变化时经 @Watch 触发重载（乱序参数后台回填场景，ReaderScreen.kt:202-209）。
 */
@Component
struct ReaderImageItem {
  @Prop @Watch('onSourceChanged') photoId: string = '';
  @Prop @Watch('onSourceChanged') filename: string = '';
  @Prop @Watch('onSourceChanged') scrambleId: number = SCRAMBLE_DEFAULT;
  @Prop targetWidth: number = 0;
  /** true = 横向翻页整屏适配（ImageFit.Contain）；false = 纵向条漫整宽 */
  @Prop fitScreen: boolean = false;
  @State pixelMap: image.PixelMap | undefined = undefined;
  @State loading: boolean = true;
  @State failed: boolean = false;
  @State aspect: number = 0.7;
  private loadToken: number = 0;

  aboutToAppear(): void {
    this.doLoad();
  }

  aboutToDisappear(): void {
    this.loadToken++;
    this.releaseMap();
  }

  onSourceChanged(): void {
    this.doLoad();
  }

  private releaseMap(): void {
    const m: image.PixelMap | undefined = this.pixelMap;
    if (m !== undefined) {
      m.release().catch((e: Error): void => {
      });
      this.pixelMap = undefined;
    }
  }

  private async doLoad(): Promise<void> {
    if (this.photoId === '' || this.filename === '') {
      this.loading = false;
      this.failed = true;
      return;
    }
    const token: number = ++this.loadToken;
    this.loading = true;
    this.failed = false;
    this.releaseMap();
    try {
      const map: image.PixelMap | null = await loadPagePixelMap(
        this.photoId, this.filename, this.scrambleId, this.targetWidth);
      if (token !== this.loadToken) {
        if (map !== null) {
          map.release().catch((e: Error): void => {
          });
        }
        return;
      }
      if (map === null) {
        this.loading = false;
        this.failed = true;
        return;
      }
      const info: image.ImageInfo = map.getImageInfoSync();
      const h: number = info.size.height;
      this.aspect = h > 0 ? info.size.width / h : 0.7;
      this.pixelMap = map;
      this.loading = false;
    } catch (e) {
      if (token === this.loadToken) {
        this.loading = false;
        this.failed = true;
      }
    }
  }

  build() {
    Stack() {
      this.Content()
    }
    .width('100%')
    .height(this.fitScreen ? '100%' : 'auto')
  }

  @Builder
  private Content() {
    if (this.loading) {
      if (this.fitScreen) {
        Column() {
          LoadingProgress().width(26).height(26).color('rgba(255,255,255,0.45)')
        }
        .width('100%')
        .height('100%')
        .backgroundColor(PLACEHOLDER_BG)
        .justifyContent(FlexAlign.Center)
      } else {
        Column() {
          LoadingProgress().width(26).height(26).color('rgba(255,255,255,0.45)')
        }
        .width('100%')
        .aspectRatio(this.aspect)
        .backgroundColor(PLACEHOLDER_BG)
        .justifyContent(FlexAlign.Center)
      }
    } else if (this.failed) {
      if (this.fitScreen) {
        Column({ space: 8 }) {
          Text('加载失败').fontSize(14).fontColor('rgba(255,255,255,0.85)')
          Text('点按重试（自动切换线路）').fontSize(11).fontColor('rgba(255,255,255,0.5)')
        }
        .width('100%')
        .height('100%')
        .backgroundColor(FAILED_BG)
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.doLoad();
        })
      } else {
        Column({ space: 8 }) {
          Text('加载失败').fontSize(14).fontColor('rgba(255,255,255,0.85)')
          Text('点按重试（自动切换线路）').fontSize(11).fontColor('rgba(255,255,255,0.5)')
        }
        .width('100%')
        .aspectRatio(this.aspect)
        .backgroundColor(FAILED_BG)
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.doLoad();
        })
      }
    } else if (this.pixelMap !== undefined) {
      if (this.fitScreen) {
        Image(this.pixelMap)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Contain)
          .interpolation(ImageInterpolation.Medium)
      } else {
        Image(this.pixelMap)
          .width('100%')
          .aspectRatio(this.aspect)
          .objectFit(ImageFit.Fill)
          .interpolation(ImageInterpolation.Medium)
      }
    }
  }
}

/** HUD 四大金刚按钮（目录/模式/画面/设置） */
@Component
struct HudButton {
  @Prop label: string = '';
  @Prop glyph: string = '';
  @Prop active: boolean = false;
  onTap: () => void = (): void => {
  };

  build() {
    Column({ space: 4 }) {
      Text(this.glyph)
        .fontSize(19)
        .fontColor(this.active ? PRIMARY : '#F2F2F5')
      Text(this.label)
        .fontSize(10)
        .fontColor(this.active ? PRIMARY : 'rgba(255,255,255,0.78)')
    }
    .layoutWeight(1)
    .padding({ top: 9, bottom: 9 })
    .borderRadius(CHIP_R)
    .backgroundColor(this.active ? 'rgba(255,77,109,0.16)' : 'rgba(255,255,255,0.08)')
    .onClick(() => {
      this.onTap();
    })
  }
}

/** 通用选择胶囊（背景色 / 预加载档位），选中态品牌粉反白（对齐 TagChip 规范） */
@Component
struct ChipOption {
  @Prop label: string = '';
  @Prop selected: boolean = false;
  onTap: () => void = (): void => {
  };

  build() {
    Text(this.label)
      .fontSize(12)
      .fontColor(this.selected ? Color.White : 'rgba(255,255,255,0.75)')
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .borderRadius(CHIP_R)
      .backgroundColor(this.selected ? PRIMARY : 'rgba(255,255,255,0.12)')
      .onClick(() => {
        this.onTap();
      })
  }
}

/** 阅读模式选项行（R-03/R-04/R-05） */
@Component
struct ModeOptionRow {
  @Prop label: string = '';
  @Prop sub: string = '';
  @Prop selected: boolean = false;
  onPick: () => void = (): void => {
  };

  build() {
    Row({ space: 8 }) {
      Column({ space: 2 }) {
        Text(this.label)
          .fontSize(14)
          .fontColor(this.selected ? PRIMARY : 'rgba(255,255,255,0.88)')
        Text(this.sub)
          .fontSize(10)
          .fontColor('rgba(255,255,255,0.45)')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      if (this.selected) {
        Text('✓')
          .fontSize(15)
          .fontColor(PRIMARY)
      }
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 10, bottom: 10 })
    .borderRadius(CARD_R)
    .backgroundColor(this.selected ? 'rgba(255,77,109,0.12)' : 'rgba(255,255,255,0.06)')
    .onClick(() => {
      this.onPick();
    })
  }
}

// ───────────────────────── ReaderPage ─────────────────────────

@Component
export struct ReaderPage {
  /** 全局路由栈（MainShell @Provide） */
  @Consume('navPathStack') pageStack: NavPathStack;

  // ── 路由参数（R-00）──
  private routeChapterId: string = '';
  private routeChapterIndex: number = -1;
  private routePage: number = -1;
  private paramReady: boolean = false;

  // ── UI 状态 ──
  @State aid: string = '';
  @State albumTitle: string = '';
  @State authorLine: string = '';
  @State chapters: Array<Chapter> = [];
  @State chapterIndex: number = 0;
  @State pages: Array<string> = [];
  @State scrambleId: number = SCRAMBLE_DEFAULT;
  @State loadState: 'loading' | 'ready' | 'error' = 'loading';
  @State errorMsg: string = '';
  @State currentPage: number = 0;
  @State mode: ReaderMode = 'vertical';
  @State hudVisible: boolean = false;
  @State panel: 'none' | 'mode' | 'display' | 'settings' = 'none';
  @State sheetVisible: boolean = false;
  @State brightnessValue: number = 100;
  @State bgPaper: boolean = false;
  @State preloadCount: number = 3;
  @State sliderValue: number = 1;
  @State sliderDragging: boolean = false;
  @State canvasWidthVp: number = 0;
  @State canvasHeightVp: number = 0;
  @State topSafeVp: number = 38;
  @State bottomSafeVp: number = 18;

  // ── 双指缩放（R-26：1x~5x + 边界回弹 + HUD 重置）──
  @State zoomScale: number = 1;
  @State zoomOffsetX: number = 0;
  @State zoomOffsetY: number = 0;
  private pinchStartScale: number = 1;
  private panStartX: number = 0;
  private panStartY: number = 0;

  // ── 非渲染成员 ──
  private targetWidthPx: number = 1080;
  private pagesSource: PageListSource = new PageListSource();
  private chapterSource: ChapterSource = new ChapterSource();
  private listScroller: Scroller = new Scroller();
  private swiperController: SwiperController = new SwiperController();
  private prefetched: Set<string> = new Set<string>();
  private chapterToken: number = 0;
  private lastSavedAt: number = 0;
  private saveTimer: number = -1;
  private readingStarted: boolean = false;
  private readingResolved: boolean = false;
  private autoCacheOn: boolean = true;
  private destroyed: boolean = false;

  aboutToAppear(): void {
    try {
      this.targetWidthPx = display.getDefaultDisplaySync().width;
    } catch (e) {
      this.targetWidthPx = 1080;
    }
  }

  aboutToDisappear(): void {
    this.destroyed = true;
    if (this.saveTimer >= 0) {
      clearTimeout(this.saveTimer);
      this.saveTimer = -1;
    }
    this.saveProgressNow();
  }

  // ───────────────────────── 初始化（R-00 / R-20）─────────────────────────

  private initAfterParams(): void {
    this.measureSafeAreas().catch((e: Error): void => {
    });
    this.loadPrefs().catch((e: Error): void => {
    });
    this.loadAlbum().catch((e: Error): void => {
    });
  }

  private async loadPrefs(): Promise<void> {
    try {
      const prefs: Prefs = await Prefs.getInstance();
      const m: string = await prefs.readerMode();
      if (m === 'vertical' || m === 'horizontal' || m === 'rtl' || m === 'double') {
        this.mode = m;
      } else {
        this.mode = 'vertical';
      }
      this.preloadCount = this.clampPreload(await prefs.preloadPages());
      const b: number = await prefs.brightness();
      this.brightnessValue = b >= 0 && b <= 100 ? b : 100;
      this.autoCacheOn = await prefs.autoCache();
    } catch (e) {
      // 保持默认值
    }
  }

  private async measureSafeAreas(): Promise<void> {
    try {
      const win: window.Window = await window.getLastWindow(getAppContext());
      const top: window.AvoidArea = await win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const bottom: window.AvoidArea =
        await win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      const t: number = this.getUIContext().px2vp(top.topRect.height);
      const b: number = this.getUIContext().px2vp(bottom.bottomRect.height);
      if (t > 0) {
        this.topSafeVp = t;
      }
      if (b > 0) {
        this.bottomSafeVp = b;
      }
    } catch (e) {
      // 量取失败保持默认（全屏沉浸下 HUD 仅短暂偏移）
    }
  }

  /** 米黄背景时切深色状态栏图标（EntryAbility 默认浅色）；退出阅读器恢复浅色 */
  private async applySystemBarDarkText(darkText: boolean): Promise<void> {
    try {
      const win: window.Window = await window.getLastWindow(getAppContext());
      await win.setWindowSystemBarProperties({ statusBarContentColor: darkText ? TEXT_MAIN : '#FFFFFF' });
    } catch (e) {
      // 系统栏配置失败不影响阅读
    }
  }

  /** 章节列表：AlbumCache 秒开 → 网络刷新（失败保留缓存）；全失败且带 chapterId 时单章兜底 */
  private async loadAlbum(): Promise<void> {
    let cachedAlbum: Album | null = null;
    try {
      cachedAlbum = await albumCacheStore.get(this.aid);
    } catch (e) {
      cachedAlbum = null;
    }
    if (cachedAlbum !== null) {
      this.applyAlbum(cachedAlbum);
      this.beginReading();
    }
    try {
      const fresh: Album = await jmApi.album(this.aid);
      this.applyAlbum(fresh);
      albumCacheStore.put(fresh).catch((e: Error): void => {
      });
      this.beginReading();
    } catch (e) {
      if (cachedAlbum === null) {
        if (this.routeChapterId !== '') {
          const single: Chapter = new Chapter(this.routeChapterId, '', '1');
          this.chapters = [single];
          this.chapterSource.setList(this.chapters);
          this.albumTitle = `JM${this.aid}`;
          this.beginReading();
        } else if (!this.readingStarted) {
          this.loadState = 'error';
          this.errorMsg = errorMessage(e as Error);
          this.hudVisible = true;
        }
      }
    }
  }

  private applyAlbum(a: Album): void {
    if (a.name !== '') {
      this.albumTitle = a.name;
    }
    const authors: string = a.author.join(' · ');
    if (authors !== '') {
      this.authorLine = authors;
    }
    if (a.episodes.length > 0) {
      if (this.readingStarted) {
        // 网络刷新后的目录以章 id 对齐当前阅读位置
        const curId: string = this.currentChapterId();
        const idx: number = curId !== '' ? this.indexOfChapterIn(a.episodes, curId) : -1;
        this.chapters = a.episodes;
        this.chapterSource.setList(a.episodes);
        if (idx >= 0) {
          this.chapterIndex = idx;
        }
      } else {
        this.chapters = a.episodes;
        this.chapterSource.setList(a.episodes);
      }
    }
  }

  /** 进入定位：路由参数优先（R-00），仅 aid 时读精确进度续读（B-03/R-20） */
  private beginReading(): void {
    if (this.readingStarted) {
      return;
    }
    this.readingStarted = true;
    if (this.chapters.length === 0) {
      return;
    }
    if (this.routeChapterIndex >= 0 && this.routeChapterIndex < this.chapters.length) {
      this.resolveStart(this.routeChapterIndex, this.routePage >= 0 ? this.routePage : 0);
      return;
    }
    if (this.routeChapterId !== '') {
      const found: number = this.indexOfChapter(this.routeChapterId);
      this.resolveStart(found >= 0 ? found : 0, this.routePage >= 0 ? this.routePage : 0);
      return;
    }
    readProgressStore.get(this.aid).then((p: ReadingProgress | null): void => {
      if (this.readingResolved) {
        return;
      }
      if (p === null) {
        this.resolveStart(0, 0);
        return;
      }
      const byId: number = p.chapterId !== '' ? this.indexOfChapter(p.chapterId) : -1;
      const idx: number = byId >= 0 ? byId : (p.chapterIndex >= 0 && p.chapterIndex < this.chapters.length
        ? p.chapterIndex : 0);
      const page: number = this.routePage >= 0 ? this.routePage : p.page;
      this.resolveStart(idx, page);
    }).catch((e: Error): void => {
      this.resolveStart(0, 0);
    });
  }

  private resolveStart(chapterIdx: number, page: number): void {
    if (this.readingResolved) {
      return;
    }
    this.readingResolved = true;
    this.loadChapter(chapterIdx, page).catch((e: Error): void => {
    });
  }

  // ───────────────────────── 章节加载（R-23 缓存秒开→网络刷新→失败保留）─────────────────────────

  private async loadChapter(chapterIdx: number, targetPage: number): Promise<void> {
    const ch: Chapter | undefined = this.chapters[chapterIdx];
    if (ch === undefined) {
      this.loadState = 'error';
      this.errorMsg = '章节不存在';
      this.hudVisible = true;
      return;
    }
    this.chapterIndex = chapterIdx;
    this.loadState = 'loading';
    this.errorMsg = '';
    this.scrambleId = SCRAMBLE_DEFAULT;
    this.prefetched.clear();
    this.pages = [];
    this.resetZoom(false); // 切章复位缩放（R-26）
    this.pagesSource.setList(this.pages);
    const token: number = ++this.chapterToken;
    const initialTarget: number = targetPage;

    // 1) 秒开：章节图片列表缓存
    let cached: Array<string> | null = null;
    try {
      cached = await pagesCacheStore.get(ch.id);
    } catch (e) {
      cached = null;
    }
    if (token !== this.chapterToken) {
      return;
    }
    if (cached !== null && cached.length > 0) {
      this.pages = cached;
      this.pagesSource.setList(cached);
      const t: number = this.clampPage(initialTarget, cached.length);
      this.currentPage = t;
      this.loadState = 'ready';
      this.scrollToPageDelayed(t);
      this.prefetchAhead(t);
    }

    // 2) 网络刷新：先撤 loading 再定位（防「布局等 loading、定位等布局」死锁，ReaderScreen.kt:177-182）
    try {
      const fresh: Array<string> = await jmApi.chapterImages(ch.id);
      if (token !== this.chapterToken) {
        return;
      }
      const hadCache: boolean = cached !== null && cached.length > 0;
      const changed: boolean = !hadCache || !this.samePages(fresh, cached as Array<string>);
      if (fresh.length > 0 && changed) {
        this.pages = fresh;
        this.pagesSource.setList(fresh);
        const t: number = this.clampPage(initialTarget, fresh.length);
        this.currentPage = t;
        this.loadState = 'ready';
        pagesCacheStore.put(ch.id, fresh).catch((e: Error): void => {
        });
        this.prefetched.clear();
        this.scrollToPageDelayed(t);
        this.prefetchAhead(t);
      } else {
        this.loadState = 'ready';
      }
    } catch (e) {
      if (token !== this.chapterToken) {
        return;
      }
      if (cached === null || cached.length === 0) {
        this.loadState = 'error';
        this.errorMsg = errorMessage(e as Error);
        this.hudVisible = true;
        return;
      }
      this.loadState = 'ready'; // 失败保留缓存继续阅读
    }

    // 3) 乱序参数后台获取（默认 220980 与云端值算法等价）
    try {
      const sid: number = await jmApi.scrambleId(ch.id);
      if (token !== this.chapterToken) {
        return;
      }
      if (sid !== this.scrambleId) {
        this.scrambleId = sid;
        this.prefetched.clear();
        this.prefetchAhead(this.currentPage);
      }
    } catch (e) {
      // 保留默认值
    }

    // 4) 预加载下一章（目录 + 前 5 页）
    this.preloadNextChapter().catch((e: Error): void => {
    });
    this.saveProgressNow();
  }

  private retryLoad(): void {
    if (this.chapters.length > 0) {
      this.loadChapter(this.chapterIndex, 0).catch((e: Error): void => {
      });
    } else {
      this.readingStarted = false;
      this.readingResolved = false;
      this.loadAlbum().catch((e: Error): void => {
      });
    }
  }

  // ───────────────────────── 预加载（R-21 / R-22）─────────────────────────

  /** 恒预加载当前页后 N 页（N = 预加载档位；受 autoCache 开关控制，ReaderScreen.kt:120-134） */
  private prefetchAhead(fromIndex: number): void {
    if (!this.autoCacheOn) {
      return;
    }
    if (this.pages.length === 0) {
      return;
    }
    const photoId: string = this.currentChapterId();
    if (photoId === '') {
      return;
    }
    const last: number = Math.min(this.pages.length - 1, fromIndex + this.preloadCount);
    for (let i: number = fromIndex + 1; i <= last; i++) {
      const filename: string = this.pages[i];
      const key: string = `${photoId}/${filename}@${this.scrambleId}`;
      if (this.prefetched.has(key)) {
        continue;
      }
      this.prefetched.add(key);
      this.prefetchOne(photoId, filename, key);
    }
  }

  private async prefetchOne(photoId: string, filename: string, key: string): Promise<void> {
    try {
      const pm: image.PixelMap | null =
        await loadPagePixelMap(photoId, filename, this.scrambleId, this.targetWidthPx);
      if (pm !== null) {
        await pm.release();
      }
    } catch (e) {
      this.prefetched.delete(key);
    }
  }

  /** 下一章预载：目录（缓存优先）+ scrambleId + 前 5 页字节入缓存（ReaderScreen.kt:211-225） */
  private async preloadNextChapter(): Promise<void> {
    if (!this.autoCacheOn) {
      return;
    }
    const next: Chapter | undefined = this.chapters[this.chapterIndex + 1];
    if (next === undefined) {
      return;
    }
    try {
      let list: Array<string> | null = null;
      try {
        list = await pagesCacheStore.get(next.id);
      } catch (e) {
        list = null;
      }
      if (list === null || list.length === 0) {
        list = await jmApi.chapterImages(next.id);
        if (list.length > 0) {
          pagesCacheStore.put(next.id, list).catch((e: Error): void => {
          });
        }
      }
      if (list.length === 0) {
        return;
      }
      const sid: number = await jmApi.scrambleId(next.id);
      const count: number = Math.min(5, list.length);
      for (let i: number = 0; i < count; i++) {
        const pm: image.PixelMap | null =
          await loadPagePixelMap(next.id, list[i], sid, this.targetWidthPx);
        if (pm !== null) {
          await pm.release();
        }
      }
    } catch (e) {
      // 下一章预载失败静默
    }
  }

  // ───────────────────────── 阅读进度（R-20 节流保存）─────────────────────────

  private buildProgress(): ReadingProgress {
    const progress: ReadingProgress = new ReadingProgress();
    progress.aid = this.aid;
    progress.chapterId = this.currentChapterId();
    progress.chapterIndex = this.chapterIndex;
    progress.page = this.currentPage;
    progress.totalPages = this.pages.length;
    progress.title = this.albumTitle;
    progress.author = this.authorLine;
    progress.coverUrl = jmApi.albumThumbUrl(this.aid);
    return progress;
  }

  private saveProgressNow(): void {
    if (this.aid === '' || this.pages.length === 0) {
      return;
    }
    readProgressStore.save(this.buildProgress()).catch((e: Error): void => {
    });
    this.lastSavedAt = Date.now();
  }

  private scheduleProgressSave(): void {
    const now: number = Date.now();
    if (now - this.lastSavedAt >= SAVE_THROTTLE_MS) {
      this.saveProgressNow();
      return;
    }
    if (this.saveTimer >= 0) {
      return;
    }
    const delay: number = SAVE_THROTTLE_MS - (now - this.lastSavedAt);
    this.saveTimer = setTimeout((): void => {
      this.saveTimer = -1;
      this.saveProgressNow();
    }, delay);
  }

  // ───────────────────────── 翻页 / 热区 / 模式（R-02/R-03/R-06）─────────────────────────

  /** 点按三分：中央=HUD；两侧=翻页（条漫=滚动一屏）。方向按 uiux §四.3：点左=下一页、点右=上一页，日漫右翻镜像 */
  private handleCanvasClick(x: number): void {
    const w: number = this.canvasWidthVp;
    if (w <= 0) {
      this.toggleHud();
      return;
    }
    const mirrored: boolean = this.mode === 'rtl';
    if (x < w / 3) {
      this.turnPage(!mirrored);
    } else if (x > (w * 2) / 3) {
      this.turnPage(mirrored);
    } else {
      this.toggleHud();
    }
  }

  private toggleHud(): void {
    this.hudVisible = !this.hudVisible;
    if (!this.hudVisible) {
      this.panel = 'none';
    }
  }

  // ───────────────────────── 双指缩放（R-26：1x~5x + 边界回弹 + 重置）─────────────────────────

  /**
   * 缩放/平移边界：放大后内容超出画布的部分允许平移看到，偏移量被夹在
   * ±(画布尺寸 × (scale-1) / 2)（以缩放中心为画布中心的简化口径）；越界回弹。
   */
  private maxZoomOffsetX(): number {
    return Math.max(0, (this.canvasWidthVp * (this.zoomScale - 1)) / 2);
  }

  private maxZoomOffsetY(): number {
    return Math.max(0, (this.canvasHeightVp * (this.zoomScale - 1)) / 2);
  }

  /** 松手边界回弹：越界偏移动画夹回；scale<1 回弹到 1 */
  private bounceZoomBack(): void {
    const targetScale: number = Math.max(ZOOM_MIN, Math.min(ZOOM_MAX, this.zoomScale));
    const maxX: number = Math.max(0, (this.canvasWidthVp * (targetScale - 1)) / 2);
    const maxY: number = Math.max(0, (this.canvasHeightVp * (targetScale - 1)) / 2);
    const targetX: number = Math.max(-maxX, Math.min(maxX, this.zoomOffsetX));
    const targetY: number = Math.max(-maxY, Math.min(maxY, this.zoomOffsetY));
    if (targetScale === this.zoomScale && targetX === this.zoomOffsetX && targetY === this.zoomOffsetY) {
      return;
    }
    this.getUIContext().animateTo({ duration: 200, curve: Curve.Friction }, (): void => {
      this.zoomScale = targetScale;
      this.zoomOffsetX = targetX;
      this.zoomOffsetY = targetY;
    });
  }

  /** HUD 顶栏「x.x · 重置」：复位缩放与平移（ReaderScreen.kt:246-259） */
  private resetZoom(animated: boolean): void {
    if (this.zoomScale === ZOOM_MIN && this.zoomOffsetX === 0 && this.zoomOffsetY === 0) {
      return;
    }
    if (animated) {
      this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, (): void => {
        this.zoomScale = ZOOM_MIN;
        this.zoomOffsetX = 0;
        this.zoomOffsetY = 0;
      });
    } else {
      this.zoomScale = ZOOM_MIN;
      this.zoomOffsetX = 0;
      this.zoomOffsetY = 0;
    }
  }

  private onPinchStart(event: GestureEvent): void {
    this.pinchStartScale = this.zoomScale;
  }

  private onPinchUpdate(event: GestureEvent): void {
    // 实时缩放硬夹 [1,5]（ReaderScreen.kt:104-118 transformable 语义）
    const raw: number = this.pinchStartScale * event.scale;
    this.zoomScale = Math.max(ZOOM_MIN, Math.min(ZOOM_MAX, raw));
  }

  private onTwoFingerPanStart(event: GestureEvent): void {
    this.panStartX = this.zoomOffsetX;
    this.panStartY = this.zoomOffsetY;
  }

  private onTwoFingerPanUpdate(event: GestureEvent): void {
    this.zoomOffsetX = this.panStartX + event.offsetX;
    this.zoomOffsetY = this.panStartY + event.offsetY;
  }

  private turnPage(forward: boolean): void {
    if (this.pages.length === 0) {
      return;
    }
    if (this.mode === 'vertical') {
      this.scrollScreen(forward);
      return;
    }
    const target: number = this.currentPage + (forward ? 1 : -1);
    if (target < 0) {
      this.toastMsg('已经是第一页了');
      return;
    }
    if (target >= this.pages.length) {
      if (this.chapterIndex < this.chapters.length - 1) {
        this.toastMsg('本章完，可点「下一话」继续');
      } else {
        this.toastMsg('已经是最后一页了');
      }
      return;
    }
    this.jumpToPage(target);
  }

  /** 条漫模式两侧点按滚动一屏（0.85 屏，避免视觉跳跃） */
  private scrollScreen(forward: boolean): void {
    if (this.canvasHeightVp > 0) {
      const cur: OffsetResult = this.listScroller.currentOffset();
      const delta: number = this.canvasHeightVp * 0.85;
      const target: number = forward ? cur.yOffset + delta : Math.max(0, cur.yOffset - delta);
      this.listScroller.scrollTo({
        xOffset: 0,
        yOffset: target,
        animation: { duration: 220, curve: Curve.EaseOut }
      });
    } else {
      const idx: number = forward ? this.currentPage + 1 : this.currentPage - 1;
      if (idx >= 0 && idx < this.pages.length) {
        this.jumpToPage(idx);
      }
    }
  }

  private jumpToPage(page: number): void {
    const total: number = this.pages.length;
    if (total === 0) {
      return;
    }
    const p: number = this.clampPage(page, total);
    this.currentPage = p;
    if (this.mode === 'vertical') {
      this.listScroller.scrollToIndex(p, false);
    } else {
      this.swiperController.changeIndex(p, false);
    }
    this.scheduleProgressSave();
  }

  /** 非阻塞定位：章节就绪后延迟滚动（等列表/翻页器完成布局） */
  private scrollToPageDelayed(page: number): void {
    setTimeout((): void => {
      if (this.destroyed) {
        return;
      }
      this.jumpToPage(page);
    }, 120);
  }

  private switchMode(m: ReaderMode): void {
    if (this.mode === m) {
      this.panel = 'none';
      return;
    }
    const keepPage: number = this.currentPage;
    this.mode = m;
    this.panel = 'none';
    Prefs.getInstance().then((p: Prefs): Promise<void> => p.setReaderMode(m)).catch((e: Error): void => {
    });
    setTimeout((): void => {
      if (this.destroyed) {
        return;
      }
      if (m === 'vertical') {
        this.listScroller.scrollToIndex(keepPage, false);
      } else {
        this.swiperController.changeIndex(keepPage, false);
      }
    }, 120);
  }

  private setPreload(n: number): void {
    this.preloadCount = n;
    Prefs.getInstance().then((p: Prefs): Promise<void> => p.setPreloadPages(n)).catch((e: Error): void => {
    });
  }

  private toggleBackground(paper: boolean): void {
    if (this.bgPaper === paper) {
      return;
    }
    this.bgPaper = paper;
    this.applySystemBarDarkText(paper).catch((e: Error): void => {
    });
  }

  private goChapter(delta: number): void {
    const target: number = this.chapterIndex + delta;
    if (target < 0) {
      this.toastMsg('已经是第一话了');
      return;
    }
    if (target >= this.chapters.length) {
      this.toastMsg('已经是最后一话了');
      return;
    }
    this.saveProgressNow();
    this.loadChapter(target, 0).catch((e: Error): void => {
    });
  }

  private goBack(): void {
    this.saveProgressNow();
    this.pageStack.pop();
  }

  private toastMsg(msg: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: msg, duration: 1600, bottom: '35%' });
    } catch (e) {
      // Toast 失败可忽略
    }
  }

  // ───────────────────────── 辅助 ─────────────────────────

  private currentChapterId(): string {
    const ch: Chapter | undefined = this.chapters[this.chapterIndex];
    return ch === undefined ? '' : ch.id;
  }

  private chapterTitle(): string {
    const ch: Chapter | undefined = this.chapters[this.chapterIndex];
    if (ch !== undefined && ch.title !== '') {
      return ch.title;
    }
    return `第 ${this.chapterIndex + 1} 話`;
  }

  private modeShortLabel(): string {
    if (this.mode === 'vertical') {
      return '条漫';
    }
    if (this.mode === 'horizontal') {
      return '翻页';
    }
    if (this.mode === 'rtl') {
      return '右翻';
    }
    return '双页';
  }

  private indexOfChapter(id: string): number {
    return this.indexOfChapterIn(this.chapters, id);
  }

  private indexOfChapterIn(list: Array<Chapter>, id: string): number {
    for (let i: number = 0; i < list.length; i++) {
      if (list[i].id === id) {
        return i;
      }
    }
    return -1;
  }

  private clampPage(page: number, total: number): number {
    if (total <= 0) {
      return 0;
    }
    return Math.max(0, Math.min(page, total - 1));
  }

  private clampPreload(n: number): number {
    return Math.max(1, Math.min(8, Math.floor(n)));
  }

  private samePages(a: Array<string>, b: Array<string>): boolean {
    if (a.length !== b.length) {
      return false;
    }
    for (let i: number = 0; i < a.length; i++) {
      if (a[i] !== b[i]) {
        return false;
      }
    }
    return true;
  }

  // ───────────────────────── 画布（R-01 / R-02）─────────────────────────

  @Builder
  private VerticalList() {
    List({ scroller: this.listScroller }) {
      LazyForEach(this.pagesSource, (filename: string) => {
        ListItem() {
          ReaderImageItem({
            photoId: this.currentChapterId(),
            filename: filename,
            scrambleId: this.scrambleId,
            targetWidth: this.targetWidthPx,
            fitScreen: false
          })
        }
      }, (filename: string) => filename)
      // R-18 尾部：本章完 + 上一章/下一章（边界隐藏，ReaderScreen.kt:409-431）
      ListItem() {
        Column({ space: 14 }) {
          Text('—— 本章完 ——')
            .fontSize(13)
            .fontColor('rgba(255,255,255,0.45)')
          Row({ space: 12 }) {
            if (this.chapterIndex > 0) {
              Text('上一章')
                .fontSize(14)
                .fontColor('rgba(255,255,255,0.9)')
                .padding({ left: 22, right: 22, top: 9, bottom: 9 })
                .borderRadius(CHIP_R)
                .backgroundColor('rgba(255,255,255,0.12)')
                .onClick(() => {
                  this.goChapter(-1);
                })
            }
            if (this.chapterIndex < this.chapters.length - 1) {
              Text('下一章')
                .fontSize(14)
                .fontColor(Color.White)
                .padding({ left: 22, right: 22, top: 9, bottom: 9 })
                .borderRadius(CHIP_R)
                .backgroundColor(ACCENT)
                .onClick(() => {
                  this.goChapter(1);
                })
            }
          }
          if (this.chapters.length <= 1) {
            Text('本作品仅此一话')
              .fontSize(12)
              .fontColor('rgba(255,255,255,0.35)')
          }
        }
        .width('100%')
        .padding({ top: 28, bottom: 64 })
        .alignItems(HorizontalAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .cachedCount(this.preloadCount)
    .onScrollIndex((first: number, end: number) => {
      if (first !== this.currentPage) {
        this.currentPage = first;
        this.prefetchAhead(first);
        this.scheduleProgressSave();
      }
    })
    .onClick((event: ClickEvent) => {
      this.handleCanvasClick(event.x);
    })
  }

  /** 横向翻页（rtl/double 为 S 级：保留枚举与切换，渲染与横向相同） */
  @Builder
  private HorizontalSwiper() {
    Swiper(this.swiperController) {
      LazyForEach(this.pagesSource, (filename: string) => {
        Column() {
          ReaderImageItem({
            photoId: this.currentChapterId(),
            filename: filename,
            scrambleId: this.scrambleId,
            targetWidth: this.targetWidthPx,
            fitScreen: true
          })
        }
        .width('100%')
        .height('100%')
      }, (filename: string) => filename)
    }
    .index(this.currentPage > 0 ? this.currentPage : 0)
    .loop(false)
    .indicator(false)
    .duration(240)
    .cachedCount(Math.max(2, this.preloadCount))
    .width('100%')
    .height('100%')
    .onChange((index: number) => {
      this.currentPage = index;
      this.prefetchAhead(index);
      this.scheduleProgressSave();
    })
    .onClick((event: ClickEvent) => {
      this.handleCanvasClick(event.x);
    })
  }

  // ───────────────────────── 全屏状态（四态）─────────────────────────

  @Builder
  private LoadingView() {
    Column({ space: 14 }) {
      LoadingProgress().width(38).height(38).color(PRIMARY)
      Text('正在加载章节…')
        .fontSize(13)
        .fontColor('rgba(255,255,255,0.6)')
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private ErrorView() {
    Column() {
      EmptyView({
        message: this.errorMsg !== '' ? this.errorMsg : '加载失败，请检查网络后重试',
        retryText: '重试',
        showRetry: true,
        onRetry: (): void => {
          this.retryLoad();
        }
      })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ top: this.topSafeVp })
  }

  @Builder
  private EmptyPagesView() {
    Column() {
      EmptyView({ message: '本章暂无内容', showRetry: false })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ top: this.topSafeVp })
  }

  // ───────────────────────── HUD（R-07 / R-08 / R-10）─────────────────────────

  @Builder
  private TopHud() {
    Row({ space: 10 }) {
      Text('←')
        .fontSize(20)
        .fontColor(Color.White)
        .width(36)
        .height(36)
        .textAlign(TextAlign.Center)
        .borderRadius(18)
        .backgroundColor('rgba(255,255,255,0.14)')
        .onClick(() => {
          this.goBack();
        })
      Text(this.chapterTitle())
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(Color.White)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      if (this.pages.length > 0) {
        Text(`${Math.min(this.currentPage + 1, this.pages.length)}/${this.pages.length}`)
          .fontSize(12)
          .fontColor('rgba(255,255,255,0.7)')
      }
      // R-26 缩放重置入口（ReaderScreen.kt:246-259 顶栏「1.6x · 重置」）
      if (this.pages.length > 0) {
        Text(`${this.zoomScale.toFixed(1)}x · 重置`)
          .fontSize(12)
          .fontColor(this.zoomScale > ZOOM_MIN ? PRIMARY : 'rgba(255,255,255,0.7)')
          .padding({ left: 8, right: 8, top: 5, bottom: 5 })
          .borderRadius(CHIP_R)
          .backgroundColor('rgba(255,255,255,0.14)')
          .onClick(() => {
            this.resetZoom(true);
          })
      }
      Text(this.modeShortLabel())
        .fontSize(12)
        .fontColor(PRIMARY)
        .padding({ left: 10, right: 10, top: 5, bottom: 5 })
        .borderRadius(CHIP_R)
        .backgroundColor('rgba(255,77,109,0.18)')
        .onClick(() => {
          this.panel = this.panel === 'mode' ? 'none' : 'mode';
        })
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: this.topSafeVp + 6, bottom: 8 })
    .backgroundColor(MASK_DARK)
    .backgroundBlurStyle(BlurStyle.Thin)
  }

  @Builder
  private ModePanel() {
    Column({ space: 6 }) {
      ModeOptionRow({
        label: '纵向条漫', sub: '上下连续滚动', selected: this.mode === 'vertical',
        onPick: (): void => {
          this.switchMode('vertical');
        }
      })
      ModeOptionRow({
        label: '左右翻页', sub: '从左向右单页适配', selected: this.mode === 'horizontal',
        onPick: (): void => {
          this.switchMode('horizontal');
        }
      })
      ModeOptionRow({
        label: '日漫右翻', sub: 'S 级：暂以左右翻页渲染，热区已镜像', selected: this.mode === 'rtl',
        onPick: (): void => {
          this.switchMode('rtl');
        }
      })
      ModeOptionRow({
        label: '双页拼合', sub: 'S 级：暂以左右翻页渲染', selected: this.mode === 'double',
        onPick: (): void => {
          this.switchMode('double');
        }
      })
    }
    .width('100%')
    .padding(10)
    .borderRadius(CARD_R)
    .backgroundColor(PANEL_BG)
  }

  @Builder
  private DisplayPanel() {
    Column({ space: 12 }) {
      Row({ space: 10 }) {
        Text('亮度')
          .fontSize(13)
          .fontColor('#F2F2F4')
          .width(38)
        Slider({ value: this.brightnessValue, min: 10, max: 100, step: 1, style: SliderStyle.OutSet })
          .selectedColor(PRIMARY)
          .trackColor('rgba(255,255,255,0.25)')
          .blockColor(Color.White)
          .layoutWeight(1)
          .onChange((value: number, mode: SliderChangeMode) => {
            this.brightnessValue = value;
            if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
              Prefs.getInstance()
                .then((p: Prefs): Promise<void> => p.setBrightness(value))
                .catch((e: Error): void => {
                });
            }
          })
      }
      .width('100%')
      Text('亮度为应用内遮罩调光（S 级），退出阅读器后恢复系统亮度')
        .fontSize(10)
        .fontColor('rgba(255,255,255,0.45)')
        .width('100%')
      Row({ space: 10 }) {
        Text('背景')
          .fontSize(13)
          .fontColor('#F2F2F4')
          .width(38)
        ChipOption({
          label: '深邃黑', selected: !this.bgPaper,
          onTap: (): void => {
            this.toggleBackground(false);
          }
        })
        ChipOption({
          label: '米黄纸', selected: this.bgPaper,
          onTap: (): void => {
            this.toggleBackground(true);
          }
        })
      }
      .width('100%')
    }
    .width('100%')
    .padding(12)
    .borderRadius(CARD_R)
    .backgroundColor(PANEL_BG)
  }

  @Builder
  private SettingsPanel() {
    Column({ space: 12 }) {
      Text('预加载档位')
        .fontSize(13)
        .fontColor('#F2F2F4')
        .width('100%')
      Row({ space: 8 }) {
        ChipOption({
          label: '省流 1', selected: this.preloadCount === 1,
          onTap: (): void => {
            this.setPreload(1);
          }
        })
        ChipOption({
          label: '标准 3', selected: this.preloadCount === 3,
          onTap: (): void => {
            this.setPreload(3);
          }
        })
        ChipOption({
          label: '进取 5', selected: this.preloadCount === 5,
          onTap: (): void => {
            this.setPreload(5);
          }
        })
        ChipOption({
          label: '极速 8', selected: this.preloadCount === 8,
          onTap: (): void => {
            this.setPreload(8);
          }
        })
      }
      .width('100%')
      Text('预加载当前话后 N 页并预热下一章；同时受「我的 · 缓存 · 自动缓存」开关控制')
        .fontSize(10)
        .fontColor('rgba(255,255,255,0.45)')
        .width('100%')
    }
    .width('100%')
    .padding(12)
    .borderRadius(CARD_R)
    .backgroundColor(PANEL_BG)
  }

  @Builder
  private BottomHud() {
    Column({ space: 10 }) {
      if (this.panel === 'mode') {
        this.ModePanel()
      } else if (this.panel === 'display') {
        this.DisplayPanel()
      } else if (this.panel === 'settings') {
        this.SettingsPanel()
      }
      // R-08/R-19：进度滑动条 + 上一话/下一话（拖动实时页码、松手跳转）
      Row({ space: 10 }) {
        Text('上一话')
          .fontSize(13)
          .fontColor(this.chapterIndex > 0 ? 'rgba(255,255,255,0.9)' : 'rgba(255,255,255,0.35)')
          .padding({ left: 12, right: 12, top: 7, bottom: 7 })
          .borderRadius(CHIP_R)
          .backgroundColor('rgba(255,255,255,0.1)')
          .onClick(() => {
            this.goChapter(-1);
          })
        Column({ space: 2 }) {
          Slider({
            value: this.sliderDragging ? this.sliderValue
              : Math.min(this.currentPage + 1, Math.max(this.pages.length, 1)),
            min: 1,
            max: Math.max(this.pages.length, 1),
            step: 1,
            style: SliderStyle.OutSet
          })
          .selectedColor(PRIMARY)
          .trackColor('rgba(255,255,255,0.25)')
          .blockColor(Color.White)
          .layoutWeight(1)
          .onChange((value: number, mode: SliderChangeMode) => {
            if (mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving) {
              this.sliderDragging = true;
              this.sliderValue = value;
            } else {
              this.sliderDragging = false;
              if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
                this.jumpToPage(value - 1);
              }
            }
          })
          Text(`${this.sliderDragging ? this.sliderValue : Math.min(this.currentPage + 1, this.pages.length)} / ${this.pages.length}`)
            .fontSize(11)
            .fontColor('rgba(255,255,255,0.7)')
            .textAlign(TextAlign.Center)
        }
        .layoutWeight(1)
        Text('下一话')
          .fontSize(13)
          .fontColor(this.chapterIndex < this.chapters.length - 1
            ? 'rgba(255,255,255,0.9)' : 'rgba(255,255,255,0.35)')
          .padding({ left: 12, right: 12, top: 7, bottom: 7 })
          .borderRadius(CHIP_R)
          .backgroundColor('rgba(255,255,255,0.1)')
          .onClick(() => {
            this.goChapter(1);
          })
      }
      .width('100%')
      // R-10 四大金刚：目录 / 阅读模式 / 画面调节 / 设置
      Row({ space: 6 }) {
        HudButton({
          label: '目录', glyph: '☰',
          onTap: (): void => {
            this.sheetVisible = true;
          }
        })
        HudButton({
          label: '模式', glyph: '⇄', active: this.panel === 'mode',
          onTap: (): void => {
            this.panel = this.panel === 'mode' ? 'none' : 'mode';
          }
        })
        HudButton({
          label: '画面', glyph: '◐', active: this.panel === 'display',
          onTap: (): void => {
            this.panel = this.panel === 'display' ? 'none' : 'display';
          }
        })
        HudButton({
          label: '设置', glyph: '⚙', active: this.panel === 'settings',
          onTap: (): void => {
            this.panel = this.panel === 'settings' ? 'none' : 'settings';
          }
        })
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: this.bottomSafeVp + 10 })
    .backgroundColor(MASK_DARK)
    .backgroundBlurStyle(BlurStyle.Thin)
  }

  @Builder
  private HudLayer() {
    Column() {
      this.TopHud()
      Blank().layoutWeight(1)
      if (this.pages.length > 0) {
        this.BottomHud()
      }
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.Transparent)
    .transition(TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseOut }))
  }

  /** R-17 HUD 隐藏时的微型常驻页码胶囊（右下角，不拦截触摸） */
  @Builder
  private PagePill() {
    Column() {
      Text(`${this.chapterTitle()} ${Math.min(this.currentPage + 1, this.pages.length)}/${this.pages.length}`)
        .fontSize(10)
        .fontColor('rgba(255,255,255,0.82)')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: '72%' })
        .padding({ left: 10, right: 10, top: 4, bottom: 4 })
        .borderRadius(CHIP_R)
        .backgroundColor(MASK_DARK)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.End)
    .alignItems(HorizontalAlign.End)
    .padding({ right: 12, bottom: this.bottomSafeVp + 14 })
    .hitTestBehavior(HitTestMode.None)
  }

  /** R-11 章节目录半模态：点击直达对应话 */
  @Builder
  private ChapterSheet() {
    Column() {
      Row({ space: 8 }) {
        Text('章节目录')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor('#F2F2F4')
          .layoutWeight(1)
        Text(`共 ${this.chapters.length} 话`)
          .fontSize(12)
          .fontColor('rgba(255,255,255,0.5)')
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 14, bottom: 10 })
      List() {
        LazyForEach(this.chapterSource, (ch: Chapter, index?: number) => {
          ListItem() {
            Row({ space: 10 }) {
              Text(`${(index === undefined ? 0 : index) + 1}`)
                .fontSize(13)
                .fontColor('rgba(255,255,255,0.45)')
                .width(34)
              Text(ch.title !== '' ? ch.title : `第 ${(index === undefined ? 0 : index) + 1} 話`)
                .fontSize(14)
                .fontColor(index === this.chapterIndex ? '#FFFFFF' : 'rgba(255,255,255,0.75)')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
              if (index === this.chapterIndex) {
                Text('阅读中')
                  .fontSize(10)
                  .fontColor(PRIMARY)
                  .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                  .borderRadius(CHIP_R)
                  .backgroundColor('rgba(255,77,109,0.16)')
              }
            }
            .width('100%')
            .padding({ left: 18, right: 18, top: 13, bottom: 13 })
            .onClick(() => {
              const idx: number = index === undefined ? 0 : index;
              this.sheetVisible = false;
              if (idx !== this.chapterIndex) {
                this.loadChapter(idx, 0).catch((e: Error): void => {
                });
              }
            })
          }
        }, (ch: Chapter) => `ch_${ch.id}`)
      }
      .width('100%')
      .layoutWeight(1)
      .divider({ strokeWidth: 0.5, color: 'rgba(255,255,255,0.08)', startMargin: 18, endMargin: 18 })
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .height('100%')
  }

  // ───────────────────────── 页面 ─────────────────────────

  build() {
    NavDestination() {
      Stack() {
        // R-26 缩放画布：外层平移（父坐标系）+ 内层缩放 + 双指手势（不拦截单指滚动/翻页）
        Column() {
          Stack() {
            if (this.loadState === 'loading') {
              this.LoadingView()
            } else if (this.loadState === 'error') {
              this.ErrorView()
            } else if (this.pages.length === 0) {
              this.EmptyPagesView()
            } else if (this.mode === 'vertical') {
              this.VerticalList()
            } else {
              this.HorizontalSwiper()
            }
          }
          .width('100%')
          .height('100%')
          .scale({ x: this.zoomScale, y: this.zoomScale })
          .gesture(
            GestureGroup(GestureMode.Parallel,
              PinchGesture({ fingers: 2 })
                .onActionStart((event: GestureEvent): void => {
                  this.onPinchStart(event);
                })
                .onActionUpdate((event: GestureEvent): void => {
                  this.onPinchUpdate(event);
                })
                .onActionEnd((): void => {
                  this.bounceZoomBack();
                }),
              PanGesture({ fingers: 2, distance: 1 })
                .onActionStart((event: GestureEvent): void => {
                  this.onTwoFingerPanStart(event);
                })
                .onActionUpdate((event: GestureEvent): void => {
                  this.onTwoFingerPanUpdate(event);
                })
                .onActionEnd((): void => {
                  this.bounceZoomBack();
                })
            )
          )
        }
        .width('100%')
        .height('100%')
        .translate({ x: this.zoomOffsetX, y: this.zoomOffsetY })
        // 亮度遮罩（S 级：应用内调光，不拦截触摸）
        if (this.brightnessValue < 100) {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor(`rgba(0,0,0,${(((100 - this.brightnessValue) / 100) * 0.72).toFixed(2)})`)
            .hitTestBehavior(HitTestMode.None)
        }
        // 微型页码胶囊（HUD 隐藏时常驻）
        if (!this.hudVisible && this.pages.length > 0) {
          this.PagePill()
        }
        // 上下双层 HUD
        if (this.hudVisible) {
          this.HudLayer()
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.bgPaper ? PAPER_BG : READER_BG)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .onAreaChange((oldArea: Area, newArea: Area) => {
        const w: number = Number(newArea.width);
        const h: number = Number(newArea.height);
        if (!Number.isNaN(w) && w > 0) {
          this.canvasWidthVp = w;
        }
        if (!Number.isNaN(h) && h > 0) {
          this.canvasHeightVp = h;
        }
      })
      .bindSheet($$this.sheetVisible, this.ChapterSheet(), {
        height: '62%',
        dragBar: true,
        backgroundColor: '#17171B',
        onDisappear: (): void => {
          this.sheetVisible = false;
        }
      })
    }
    .hideTitleBar(true)
    .backgroundColor(this.bgPaper ? PAPER_BG : READER_BG)
    .onReady((ctx: NavDestinationContext) => {
      if (this.paramReady) {
        return;
      }
      this.paramReady = true;
      const raw: Object | undefined = ctx.pathInfo.param as Object | undefined;
      if (raw !== undefined) {
        const rec: Record<string, Object> | null = asRecord(raw);
        if (rec !== null) {
          this.aid = asString(rec['aid']);
          // 契约参数 chapterId?: number，模型/Store 侧为 string —— asString 容忍数字统一转字符串
          this.routeChapterId = asString(rec['chapterId']);
          this.routeChapterIndex = asNumber(rec['chapterIndex'], -1);
          this.routePage = asNumber(rec['page'], -1);
        }
      }
      this.initAfterParams();
    })
    .onShown(() => {
      if (this.bgPaper) {
        this.applySystemBarDarkText(true).catch((e: Error): void => {
        });
      }
    })
    .onHidden(() => {
      this.saveProgressNow();
    })
    .onWillDisappear(() => {
      this.saveProgressNow();
      if (this.bgPaper) {
        this.applySystemBarDarkText(false).catch((e: Error): void => {
        });
      }
    })
    .onBackPressed(() => {
      this.saveProgressNow();
      return false;
    })
  }
}
