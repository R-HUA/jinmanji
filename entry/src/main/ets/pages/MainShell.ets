/**
 * pages/MainShell.ets —— 应用主壳（工程架构师维护）。
 * Navigation + 底部四栏 Tabs：发现/分类/书架/我的。
 * 契约：docs/conventions.md 第 3 节——
 *   - NavPathStack 通过 @Provide('navPathStack') 下发，子页 @Consume('navPathStack') 获取；
 *   - 全部路由页在本文件预注册（import 的导出名/路径与契约表严格一致，文件由各页面工程师补齐）；
 *   - 四个 Tab 页组件直接嵌入 Tabs，不经路由。
 *
 * 底部栏实现说明：Tabs 内建 bar 无法稳定应用 backgroundBlurStyle 并延展底部安全区，
 * 故采用 barHeight(0) + 自绘毛玻璃底栏（Tabs 仍承载四栏页面内容与切换），
 * 选中 #FF4D6D / 未选中 #8E8E93、SymbolGlyph 图标 + 11fp 文字，符合 uiux-design 第 1 节。
 */
import { ROUTE_SEARCH, ROUTE_ALBUM, ROUTE_READER, ROUTE_DOWNLOADS, NAV_STACK_DEPTH_KEY } from '../common/Route';
import { PRIMARY, TAB_INACTIVE, BG, CARD, CARD_R, TEXT_MAIN, TEXT_SUB, MASK_DARK, BAR_LIGHT, TAB_BAR_HEIGHT, CHIP_R, CHIP_BG } from '../common/Theme';
import { ExplorePage } from './ExplorePage';
import { CategoryPage } from './CategoryPage';
import { BookshelfPage } from './BookshelfPage';
import { SettingsPage } from './SettingsPage';
import { SearchPage } from './SearchPage';
import { AlbumDetailPage } from './AlbumDetailPage';
import { ReaderPage } from './ReaderPage';
import { DownloadsPage } from './DownloadsPage';
import { CURRENT_BREAKPOINT_KEY, TOP_RECT_HEIGHT_KEY } from '../entryability/EntryAbility';

/** EntryAbility 全局错误兜底写入 AppStorage 的 key */
const CRASH_MESSAGE_KEY: string = 'crashErrorMessage';

@Component
export struct MainShell {
  /** 全局路由栈：子页 @Consume('navPathStack') 后 pushPathByName(name, param) 跳转 */
  @Provide('navPathStack') pageStack: NavPathStack = new NavPathStack();
  /**
   * 当前 Tab 索引：经 AppStorage 与入口页 Index 双向同步（X-04 返回拦截——
   * 非发现 Tab 按系统返回先回发现；Index.onBackPress 读/写 'mainTabIndex'）。
   */
  @StorageLink('mainTabIndex') currentIndex: number = 0;
  /** Stack 模式下 NavBar（Tab 首页）是否可见；进入 NavDestination 时隐藏底栏与 md/lg 侧栏，页面全屏不遮挡阅读器 */
  @State navBarVisible: boolean = true;
  /** 全局未捕获异常信息（EntryAbility 写入）；非空时整层展示最简友好错误页 */
  @StorageProp(CRASH_MESSAGE_KEY) crashMessage: string = '';
  /** 一多断点（评审 Step4）：sm 底部 Tab 栏 / md|lg 左侧垂直侧边栏 */
  @StorageProp(CURRENT_BREAKPOINT_KEY) bp: string = 'sm';
  @StorageProp(TOP_RECT_HEIGHT_KEY) topInset: number = 38;

  aboutToAppear(): void {
    this.publishNavDepth(this.navBarVisible);
  }

  /** 栈深度：导航栏隐藏表示目的地盖住首页，至少记 1，供 Index 返回键判断 */
  private publishNavDepth(navBarVisible: boolean): void {
    let depth: number = this.pageStack.size();
    if (navBarVisible) {
      depth = 0;
    } else if (depth <= 0) {
      depth = 1;
    }
    AppStorage.setOrCreate(NAV_STACK_DEPTH_KEY, depth);
  }

  /** 路由表：全部 NavDestination 预注册（导出名与 conventions 第 3 节契约表一致） */
  @Builder
  PageMap(name: string) {
    if (name === ROUTE_SEARCH) {
      SearchPage()
    } else if (name === ROUTE_ALBUM) {
      AlbumDetailPage()
    } else if (name === ROUTE_READER) {
      ReaderPage()
    } else if (name === ROUTE_DOWNLOADS) {
      DownloadsPage()
    }
  }

  @Builder
  TabItem(index: number, label: string, icon: Resource) {
    Column({ space: 3 }) {
      SymbolGlyph(icon)
        .fontSize(22)
        .fontColor([this.currentIndex === index ? PRIMARY : TAB_INACTIVE])
      Text(label)
        .fontSize(11)
        .fontWeight(this.currentIndex === index ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.currentIndex === index ? PRIMARY : TAB_INACTIVE)
    }
    .layoutWeight(1)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      // 对齐原版 v0.5.0：已停在发现 Tab 时再次点击 → 滚回顶部并刷新（ExplorePage 监听该 tick）
      if (index === 0 && this.currentIndex === 0) {
        AppStorage.setOrCreate('exploreRefreshTick', Date.now());
        return;
      }
      this.currentIndex = index;
    })
  }

  /** md/lg 断点侧边导航项（垂直排列，无 layoutWeight 拉伸） */
  @Builder
  RailItem(index: number, label: string, icon: Resource) {
    Column({ space: 4 }) {
      SymbolGlyph(icon)
        .fontSize(24)
        .fontColor([this.currentIndex === index ? PRIMARY : TAB_INACTIVE])
      Text(label)
        .fontSize(10)
        .fontWeight(this.currentIndex === index ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.currentIndex === index ? PRIMARY : TAB_INACTIVE)
    }
    .width('100%')
    .padding({ top: 14, bottom: 14 })
    .borderRadius(CHIP_R)
    .backgroundColor(this.currentIndex === index ? CHIP_BG : Color.Transparent)
    .onClick(() => {
      if (index === 0 && this.currentIndex === 0) {
        AppStorage.setOrCreate('exploreRefreshTick', Date.now());
        return;
      }
      this.currentIndex = index;
    })
  }

  /** md/lg 断点左侧垂直毛玻璃侧边栏（评审 Step4：折叠屏展开/平板替代底部 Tab） */
  @Builder
  SideRail() {
    Column({ space: 6 }) {
      this.RailItem(0, '发现', $r('sys.symbol.compass'))
      this.RailItem(1, '分类', $r('sys.symbol.square_grid_2x2'))
      this.RailItem(2, '书架', $r('sys.symbol.book'))
      this.RailItem(3, '我的', $r('sys.symbol.person'))
    }
    .width(84)
    .height('100%')
    .padding({ top: this.topInset + 8, left: 8, right: 8 })
    .backgroundColor(BAR_LIGHT)
    .backgroundBlurStyle(BlurStyle.Regular)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  /** 底部栏：半透明 + backgroundBlurStyle 毛玻璃，延展到底部系统导航条安全区 */
  @Builder
  BottomBar() {
    Column() {
      Row() {
        this.TabItem(0, '发现', $r('sys.symbol.compass'))
        this.TabItem(1, '分类', $r('sys.symbol.square_grid_2x2'))
        this.TabItem(2, '书架', $r('sys.symbol.book'))
        this.TabItem(3, '我的', $r('sys.symbol.person'))
      }
      .width('100%')
      .height(TAB_BAR_HEIGHT)
    }
    .width('100%')
    .backgroundColor(BAR_LIGHT)
    .backgroundBlurStyle(BlurStyle.Regular)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  /** 最简全局错误页：EntryAbility 捕获未处理异常后触发 */
  @Builder
  CrashOverlay() {
    Column() {
      Column({ space: 12 }) {
        Text('应用出现了一点问题')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_MAIN)
        Text('异常已记录到本地日志，给你带来不便非常抱歉。')
          .fontSize(13)
          .fontColor(TEXT_SUB)
          .textAlign(TextAlign.Center)
        Text(this.crashMessage)
          .fontSize(11)
          .fontColor(TEXT_SUB)
          .maxLines(4)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .padding(8)
          .backgroundColor(BG)
          .borderRadius(8)
        Button('我知道了')
          .fontSize(15)
          .fontColor(Color.White)
          .backgroundColor(PRIMARY)
          .borderRadius(CARD_R)
          .width('100%')
          .margin({ top: 8 })
          .onClick(() => {
            AppStorage.set(CRASH_MESSAGE_KEY, '');
          })
      }
      .width('78%')
      .padding(24)
      .borderRadius(CARD_R)
      .backgroundColor(CARD)
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(MASK_DARK)
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Row() {
        // md/lg 侧边导航仅在 Tab 首页层显示；推入 NavDestination（详情/阅读器等）时随 navBarVisible 一起隐藏，页面全屏
        if (this.bp !== 'sm' && this.navBarVisible) {
          this.SideRail()
        }
        Navigation(this.pageStack) {
          Tabs({ index: this.currentIndex }) {
            TabContent() {
              ExplorePage()
            }
            TabContent() {
              CategoryPage()
            }
            TabContent() {
              BookshelfPage()
            }
            TabContent() {
              SettingsPage()
            }
          }
          .scrollable(false)
          .barHeight(0)
          .onChange((index: number) => {
            this.currentIndex = index;
          })
          .width('100%')
          .height('100%')
        }
        .navDestination(this.PageMap)
        // 恒用 Stack：Auto 在 ≥600vp 会进 Split 分栏，把四个 Tab 首页锁进默认 240vp NavBar 窄条；
        // 设计目标（uiux-design §3）是 SideRail + 全宽内容，推入页全屏覆盖
        .mode(NavigationMode.Stack)
        .hideTitleBar(true)
        .hideToolBar(true)
        .onNavBarStateChange((visible: boolean) => {
          this.navBarVisible = visible;
          this.publishNavDepth(visible);
        })
        .width('100%')
        .height('100%')
        .backgroundColor(BG)
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')

      // 底部 Tab 栏仅手机竖屏（sm）显示；md/lg 由左侧 SideRail 承担导航
      if (this.navBarVisible && this.bp === 'sm') {
        this.BottomBar()
      }
      if (this.crashMessage !== '') {
        this.CrashOverlay()
      }
    }
    .width('100%')
    .height('100%')
  }
}
