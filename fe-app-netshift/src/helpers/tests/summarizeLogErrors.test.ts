import { describe, expect, it } from 'vitest';
import { logLineMessage, summarizeLogErrors } from '../summarizeLogErrors';

const line = (time: string, text: string) =>
  `Wed Oct 7 ${time} 2026 user.notice netshift: [error] ${text}`;

describe('logLineMessage', () => {
  it('drops the time and the facility', () => {
    expect(logLineMessage(line('14:34:24', 'Unknown security'))).toBe(
      '[error] Unknown security',
    );
  });

  it('keeps a line that is not in the usual form', () => {
    expect(logLineMessage('plain text')).toBe('plain text');
  });
});

describe('summarizeLogErrors', () => {
  it('counts the same message once, whatever the time', () => {
    const batch = summarizeLogErrors([
      line('14:34:24', 'Unknown security'),
      line('14:34:25', 'Unknown security'),
      line('14:34:26', 'Unknown security'),
    ]);

    expect(batch.shown).toEqual([
      { message: '[error] Unknown security', count: 3 },
    ]);
    expect(batch.hiddenMessages).toBe(0);
  });

  it('shows the first messages and counts the rest', () => {
    const lines = ['a', 'b', 'c', 'd', 'e', 'e', 'e'].map((text) =>
      line('14:34:24', text),
    );
    const batch = summarizeLogErrors(lines, 3);

    expect(batch.shown.map((item) => item.message)).toEqual([
      '[error] a',
      '[error] b',
      '[error] c',
    ]);
    expect(batch.hiddenMessages).toBe(2);
    expect(batch.hiddenLines).toBe(4);
  });

  it('is empty for no lines', () => {
    expect(summarizeLogErrors([])).toEqual({
      shown: [],
      hiddenMessages: 0,
      hiddenLines: 0,
    });
  });
});
