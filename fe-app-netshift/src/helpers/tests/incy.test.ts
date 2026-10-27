import { describe, expect, it } from 'vitest';
import { decodeIncyLink, decodeIncyLinks, isIncyLink } from '../incy';

const KEY_HEX =
  'f6d40ea0c8a8899d7c682d09ba0d4165dfe2b3dd45e6bb3e25cb233cf00c2462';

// the cross-platform test vector of the encoder (iv 000102...0b)
const VECTOR =
  'incy://crypt1/AAECAwQFBgcICQoLNyIQL3rDwRZqnyoD8pGKSLXP6o8NdSXQVSSALNbbUyIr__tWGFUexdIfKvvmDnuDGbmBvuppfNef6aKNZUwOm4c-Sg';

// a link built with WebCrypto of the runtime, independent of the code under test
async function seal(text: string): Promise<string> {
  const raw = new Uint8Array(
    KEY_HEX.match(/../g)!.map((byte) => parseInt(byte, 16)),
  );
  const key = await crypto.subtle.importKey('raw', raw, 'AES-GCM', false, [
    'encrypt',
  ]);
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const body = new Uint8Array(
    await crypto.subtle.encrypt(
      { name: 'AES-GCM', iv },
      key,
      new TextEncoder().encode(text),
    ),
  );
  const wire = new Uint8Array(iv.length + body.length);
  wire.set(iv);
  wire.set(body, iv.length);
  const payload = btoa(String.fromCharCode(...wire))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');

  return `incy://crypt1/${payload}`;
}

describe('decodeIncyLink', () => {
  it('reads the test vector of the encoder', () => {
    expect(decodeIncyLink(VECTOR)).toEqual({
      url: 'https://sub.example.com/test-vector',
    });
  });

  it('reads a link with a name and a long address, whatever its length', async () => {
    for (const size of [0, 1, 15, 16, 17, 31, 32, 33, 200]) {
      const url = `https://sub.example.com/${'a'.repeat(size)}?x=1&y=ж`;
      const link = await seal(JSON.stringify({ n: 'My VPN', url, v: 1 }));

      expect(decodeIncyLink(link)).toEqual({ url, name: 'My VPN' });
    }
  });

  it('tolerates spaces around the link and a slash at its end', () => {
    expect(decodeIncyLink(`  ${VECTOR}/ \n`)?.url).toBe(
      'https://sub.example.com/test-vector',
    );
  });

  it('rejects a link that was changed', () => {
    const flipped = VECTOR.slice(0, -4) + (VECTOR.endsWith('Sg') ? 'Sh' : 'Sg');

    expect(decodeIncyLink(flipped.replace('AAEC', 'AQEC'))).toBeNull();
    expect(decodeIncyLink(VECTOR.slice(0, -3))).toBeNull();
  });

  it('rejects what is not an incy link', () => {
    expect(decodeIncyLink('https://sub.example.com/x')).toBeNull();
    expect(decodeIncyLink('incy://add/https%3A%2F%2Ffoo.bar')).toBeNull();
    expect(decodeIncyLink('incy://crypt1/')).toBeNull();
    expect(decodeIncyLink('incy://crypt1/!!!')).toBeNull();
  });

  it('rejects a payload that is not the expected JSON', async () => {
    expect(decodeIncyLink(await seal('not json'))).toBeNull();
    expect(decodeIncyLink(await seal('{"v":1}'))).toBeNull();
  });
});

describe('decodeIncyLinks', () => {
  it('replaces the links and leaves the rest', () => {
    expect(
      decodeIncyLinks(['https://a.example/x', VECTOR, 'incy://crypt1/AAAA']),
    ).toEqual({
      values: [
        'https://a.example/x',
        'https://sub.example.com/test-vector',
        'incy://crypt1/AAAA',
      ],
      decoded: 1,
      undecoded: 1,
    });
  });

  it('knows an incy link by its scheme', () => {
    expect(isIncyLink(' INCY://crypt1/x')).toBe(true);
    expect(isIncyLink('https://a.example')).toBe(false);
  });
});
