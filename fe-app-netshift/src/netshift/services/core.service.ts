import { TabServiceInstance } from './tab.service';
import { store } from './store.service';
import { logger } from './logger.service';
import { NetShiftLogWatcher } from './netshiftLogWatcher.service';
import { NetShiftShellMethods } from '../methods';
import { summarizeLogErrors } from '../../helpers/summarizeLogErrors';

// The error lines that arrive within this time become one group of notifications.
const ERROR_BATCH_DELAY_MS = 800;

export function coreService() {
  TabServiceInstance.onChange((activeId, tabs) => {
    logger.info('[TAB]', activeId);
    store.set({
      tabService: {
        current: activeId || '',
        all: tabs.map((tab) => tab.id),
      },
    });
  });

  const watcher = NetShiftLogWatcher.getInstance();
  let pendingErrors: string[] = [];
  let flushTimer: ReturnType<typeof setTimeout> | undefined;

  const flushErrors = () => {
    flushTimer = undefined;

    const batch = summarizeLogErrors(pendingErrors);

    pendingErrors = [];

    batch.shown.forEach((item) => {
      ui.addNotification(
        'NetShift Error',
        E(
          'div',
          {},
          item.count > 1 ? `${item.message} (×${item.count})` : item.message,
        ),
        'error',
      );
    });

    if (batch.hiddenLines > 0) {
      ui.addNotification(
        'NetShift Error',
        E(
          'div',
          {},
          `${_('And more errors')}: ${batch.hiddenLines}. ${_('See the log')}`,
        ),
        'error',
      );
    }
  };

  watcher.init(
    async () => {
      const logs = await NetShiftShellMethods.checkLogs();

      if (logs.success) {
        return logs.data as string;
      }

      return '';
    },
    {
      intervalMs: 3000,
      onNewLog: (line) => {
        if (
          line.toLowerCase().includes('[error]') ||
          line.toLowerCase().includes('[fatal]')
        ) {
          pendingErrors.push(line);

          if (flushTimer === undefined) {
            flushTimer = setTimeout(flushErrors, ERROR_BATCH_DELAY_MS);
          }
        }
      },
    },
  );

  watcher.start();
}
