// The answer of `netshift warp_generate`: a free Cloudflare WARP device
// registered on the router, with an interface and a VPN section made for it.

export const WARP_ENDPOINTS = [
  'engage.cloudflareclient.com:4500',
  'engage.cloudflareclient.com:2408',
  'engage.cloudflareclient.com:500',
];

export interface WarpAttempt {
  route: string;
  curl: number;
  http: string;
}

export interface WarpResult {
  ok: boolean;
  interface?: string;
  proto?: string;
  endpoint?: string;
  // Options of an imported config that the protocol handler does not know.
  skipped?: string[];
  error?: string;
  hint?: string;
  // The ways to reach Cloudflare that were tried, when none worked.
  attempts?: WarpAttempt[];
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
      ...(Array.isArray(value.skipped) && value.skipped.length
        ? { skipped: value.skipped.map(String) }
        : {}),
    };
  }

  const attempts = Array.isArray(value.attempts)
    ? value.attempts
        .filter(
          (item): item is Record<string, unknown> =>
            !!item && typeof item === 'object',
        )
        .map((item) => ({
          route: String(item.route ?? ''),
          curl: Number(item.curl ?? 0),
          http: String(item.http ?? ''),
        }))
        .filter((item) => item.route)
    : [];

  return {
    ok: false,
    error: text(value.error) ?? '',
    hint: text(value.hint),
    attempts,
  };
}
