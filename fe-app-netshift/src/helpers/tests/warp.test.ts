import { describe, expect, it } from 'vitest';
import { parseWarpResult, WARP_ENDPOINTS } from '../warp';

describe('parseWarpResult', () => {
  it('reads a success', () => {
    expect(
      parseWarpResult(
        JSON.stringify({
          ok: true,
          interface: 'warp',
          proto: 'amneziawg',
          endpoint: 'engage.cloudflareclient.com:4500',
          addresses: ['172.16.0.2'],
        }),
      ),
    ).toEqual({
      ok: true,
      interface: 'warp',
      proto: 'amneziawg',
      endpoint: 'engage.cloudflareclient.com:4500',
    });
  });

  it('reads an error with a hint', () => {
    expect(
      parseWarpResult({ ok: false, error: 'no answer', hint: 'use a proxy' }),
    ).toEqual({ ok: false, error: 'no answer', hint: 'use a proxy' });
  });

  it('survives garbage', () => {
    expect(parseWarpResult('Usage: netshift')).toEqual({
      ok: false,
      error: '',
    });
    expect(parseWarpResult(null)).toEqual({ ok: false, error: '' });
    expect(parseWarpResult({ ok: 'yes' })).toEqual({
      ok: false,
      error: '',
      hint: undefined,
    });
  });

  it('offers the three Cloudflare endpoints', () => {
    expect(WARP_ENDPOINTS).toHaveLength(3);
    expect(WARP_ENDPOINTS[0]).toBe('engage.cloudflareclient.com:4500');
  });
});
