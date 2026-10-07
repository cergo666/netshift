// The log lines that become notifications. A list of thousands of servers can write a
// line for every odd link, and a wall of identical notifications hides the one that
// matters, so the lines of one moment are grouped: the same message (the time of the
// line aside) is shown once with how many times it came, and only the first few
// different messages are shown at all.

export interface LogErrorSummary {
  message: string;
  count: number;
}

export interface LogErrorBatch {
  shown: LogErrorSummary[];
  // The different messages that were left out.
  hiddenMessages: number;
  // All the lines that were left out with them.
  hiddenLines: number;
}

// "Wed Oct 7 14:34:24 2026 user.notice netshift: [error] text" -> "[error] text"
export function logLineMessage(line: string): string {
  const marker = line.indexOf('netshift: ');

  return (marker >= 0 ? line.slice(marker + 'netshift: '.length) : line).trim();
}

export function summarizeLogErrors(
  lines: string[],
  maxShown = 3,
): LogErrorBatch {
  const groups = new Map<string, LogErrorSummary>();

  lines.forEach((line) => {
    const message = logLineMessage(line);
    const group = groups.get(message);

    if (group) {
      group.count += 1;
    } else {
      groups.set(message, { message, count: 1 });
    }
  });

  const all = Array.from(groups.values());
  const shown = all.slice(0, maxShown);
  const hidden = all.slice(maxShown);

  return {
    shown,
    hiddenMessages: hidden.length,
    hiddenLines: hidden.reduce((sum, item) => sum + item.count, 0),
  };
}
