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

  it('reads the options that an import skipped', () => {
    expect(
      parseWarpResult({ ok: true, interface: 'warp', skipped: ['i1', 'i2'] })
        .skipped,
    ).toEqual(['i1', 'i2']);
    expect(
      parseWarpResult({ ok: true, interface: 'warp', skipped: [] }).skipped,
    ).toBeUndefined();
  });

  it('reads an error with a hint', () => {
    expect(
      parseWarpResult({ ok: false, error: 'no answer', hint: 'use a proxy' }),
    ).toEqual({
      ok: false,
      error: 'no answer',
      hint: 'use a proxy',
      attempts: [],
    });
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
      attempts: [],
    });
  });

  it('reads the ways that were tried', () => {
    expect(
      parseWarpResult({
        ok: false,
        error: 'x',
        attempts: [
          { route: 'plain', curl: 28, http: '000' },
          { route: 'ip:104.16.192.82', curl: 7, http: '000' },
          { curl: 1 },
          null,
        ],
      }).attempts,
    ).toEqual([
      { route: 'plain', curl: 28, http: '000' },
      { route: 'ip:104.16.192.82', curl: 7, http: '000' },
    ]);
  });

  it('offers the three Cloudflare endpoints', () => {
    expect(WARP_ENDPOINTS).toHaveLength(3);
    expect(WARP_ENDPOINTS[0]).toBe('engage.cloudflareclient.com:4500');
  });
});
