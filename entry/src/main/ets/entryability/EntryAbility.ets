import { AbilityConstant, UIAbility, Want, errorManager } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import fs from '@ohos.file.fs';

const DOMAIN: number = 0x0000;
const TAG: string = 'EntryAbility';
// 全局错误信息在 AppStorage 中的 key，MainShell 监听该 key 展示友好错误页
const CRASH_MESSAGE_KEY: string = 'crashErrorMessage';

/**
 * 全局未捕获异常观察者：写 crash 日志文件 + 通知 UI 层展示友好错误页。
 * 说明：本 SDK 的 errorManager.ErrorObserver 声明为 class（ArkTS 禁止 implements class，
 * 且 ErrorObserver 仅是命名空间里的类型别名、无法 extends），故这里定义结构兼容的
 * 具名 class（含 onUnhandledException(errMsg: string): void），按结构化类型直接传给
 * errorManager.on('error', ...)。
 */
class GlobalErrorObserver {
  private owner: EntryAbility;

  constructor(owner: EntryAbility) {
    this.owner = owner;
  }

  onUnhandledException(err: string): void {
    this.owner.handleGlobalError(err);
  }
}

export default class EntryAbility extends UIAbility {
  private errorObserver: GlobalErrorObserver = new GlobalErrorObserver(this);
  /** errorManager.on('error') 返回的观察者 id，off 时必须回传该 number */
  private observerId: number = -1;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.observerId = errorManager.on('error', this.errorObserver);
  }

  onDestroy(): void {
    if (this.observerId >= 0) {
      errorManager.off('error', this.observerId);
      this.observerId = -1;
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err: BusinessError<void>) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'loadContent failed, cause: %{public}s', JSON.stringify(err));
        return;
      }
      this.applyImmersiveWindow();
    });
  }

  /**
   * 沉浸式：全屏布局 + 状态栏浅色图标。
   * statusBarContentColor 为一次性系统栏配置，不进 Theme 契约。
   */
  private async applyImmersiveWindow(): Promise<void> {
    try {
      const win: window.Window = await window.getLastWindow(this.context);
      await win.setWindowLayoutFullScreen(true);
      await win.setWindowSystemBarProperties({ statusBarContentColor: '#FFFFFF' });
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'apply immersive window failed: %{public}s', JSON.stringify(e));
    }
  }

  /**
   * 最简全局错误兜底：hilog 记录 + 写 crash 日志文件（filesDir/crash/）+ 通过 AppStorage 通知 UI。
   */
  handleGlobalError(detail: string): void {
    hilog.error(DOMAIN, TAG, 'unhandled exception: %{public}s', detail);
    this.writeCrashLog(detail);
    AppStorage.setOrCreate(CRASH_MESSAGE_KEY, detail);
  }

  private writeCrashLog(detail: string): void {
    try {
      const crashDir: string = this.context.filesDir + '/crash';
      if (!fs.accessSync(crashDir)) {
        fs.mkdirSync(crashDir, true);
      }
      const logPath: string = crashDir + '/crash_' + Date.now().toString() + '.log';
      const time: string = new Date().toISOString();
      const content: string = 'time=' + time + '\ndetail=' + detail + '\n';
      const file: fs.File = fs.openSync(logPath,
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, content);
      fs.closeSync(file);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'write crash log failed: %{public}s', JSON.stringify(e));
    }
  }
}
