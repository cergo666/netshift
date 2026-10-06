// The answer of `netshift warp_generate`: a free Cloudflare WARP device
// registered on the router, with an interface and a VPN section made for it.

export const WARP_ENDPOINTS = [
  'engage.cloudflareclient.com:4500',
  'engage.cloudflareclient.com:2408',
  'engage.cloudflareclient.com:500',
];

export interface WarpResult {
  ok: boolean;
  interface?: string;
  proto?: string;
  endpoint?: string;
  error?: string;
  hint?: string;
}

export function parseWarpResult(input: unknown): WarpResult {
  let data: unknown = input;

  if (typeof input === 'string') {
    try {
      data = JSON.parse(input);
    } catch {
      return { ok: false, error: '' };
    }
  }

  if (!data || typeof data !== 'object') {
    return { ok: false, error: '' };
  }

  const value = data as Record<string, unknown>;
  const text = (item: unknown) =>
    typeof item === 'string' && item ? item : undefined;

  if (value.ok === true) {
    return {
      ok: true,
      interface: text(value.interface),
      proto: text(value.proto),
      endpoint: text(value.endpoint),
    };
  }

  return { ok: false, error: text(value.error) ?? '', hint: text(value.hint) };
}
