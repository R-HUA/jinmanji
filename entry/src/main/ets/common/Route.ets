/**
 * 路由名常量 —— docs/conventions.md 第 3 节契约表。
 * MainShell 预注册以下全部路由；页面用 @Consume('navPathStack') 获取栈后
 * pushPathByName(name, param) 跳转，NavDestination.onReady 中 ctx.pathInfo.param 取参。
 */
export const ROUTE_SEARCH: string = 'search';
export const ROUTE_ALBUM: string = 'albumDetail';
export const ROUTE_READER: string = 'reader';
export const ROUTE_DOWNLOADS: string = 'downloads';

/** MainShell 写入、Index.onBackPress 读取：NavDestination 在栈上时 > 0，Tab 首页为 0 */
export const NAV_STACK_DEPTH_KEY: string = 'navStackDepth';
