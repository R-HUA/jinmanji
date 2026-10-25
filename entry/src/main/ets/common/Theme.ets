/**
 * common/Theme.ets —— 全局主题 token（工程架构师维护）。
 * 契约来源：docs/conventions.md 第 6 节（下述「契约 token」不得改名改值）。
 * 规则：页面一律引用本文件常量，不得散落硬编码颜色；
 *       例外：一次性半透明遮罩 rgba 可内联（通用遮罩已统一收口在文末）。
 */
/* ===== 品牌色（契约 token） ===== */
/** 品牌粉：Tab 激活、收藏、强调 */
export const PRIMARY: string = '#FF4D6D';
/** 主 CTA 蓝：开始阅读等主行动按钮 */
export const ACCENT: string = '#3B5BDB';

/* ===== 背景与表面（契约 token） ===== */
/** 页面背景 */
export const BG: string = '#F7F8FA';
/** 卡片表面 */
export const CARD: string = '#FFFFFF';
/** 阅读器画布背景（深邃黑） */
export const READER_BG: string = '#0D0D0D';

/* ===== 文本（契约 token） ===== */
/** 主文本 */
export const TEXT_MAIN: string = '#1E293B';
/** 次级文本 */
export const TEXT_SUB: string = '#64748B';

/* ===== 功能色（契约 token） ===== */
/** 胶囊/标签底色（半透明） */
export const CHIP_BG: string = 'rgba(226,232,240,0.65)';
/** 分割线 */
export const DIVIDER: string = '#E2E8F0';
/** Tab 未选中 */
export const TAB_INACTIVE: string = '#8E8E93';

/* ===== 圆角 vp（契约 token） ===== */
/** 封面圆角 */
export const COVER_R: number = 12;
/** 卡片圆角 */
export const CARD_R: number = 12;
/** 胶囊圆角 */
export const CHIP_R: number = 14;

/* ===== 结构与布局（派生 token） ===== */
/** 封面宽高比 3:4（传给 aspectRatio 的宽/高值） */
export const COVER_ASPECT_RATIO: number = 0.75;
/** 底部 Tab 栏高度 vp */
export const TAB_BAR_HEIGHT: number = 56;

/* ===== 通用字号 fp（派生 token，统一定义避免页面各自硬编码） ===== */
/** 区块标题 */
export const FONT_TITLE: number = 17;
/** 正文 */
export const FONT_BODY: number = 14;
/** 辅助说明/标签 */
export const FONT_CAPTION: number = 12;
/** Tab 文字（契约：11fp） */
export const FONT_TAB: number = 11;
/** 角标（契约卡片规范：10fp） */
export const FONT_BADGE: number = 10;

/* ===== 间距 vp（派生 token） ===== */
export const SPACE_XS: number = 4;
export const SPACE_S: number = 8;
export const SPACE_M: number = 12;
export const SPACE_L: number = 16;
export const SPACE_XL: number = 24;

/* ===== 通用半透明遮罩（高频一次性 rgba 收口，避免各页重复内联） ===== */
/** 深色全屏遮罩：错误弹层、阅读器 HUD 底 */
export const MASK_DARK: string = 'rgba(0,0,0,0.45)';
/** 底部栏浅色毛玻璃底 */
export const BAR_LIGHT: string = 'rgba(255,255,255,0.78)';
