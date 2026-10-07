import { afterEach, describe, expect, it } from 'vitest';
import { validateProxyUrl } from '../validateProxyUrl';
import {
  UNKNOWN_CORE_CAPABILITIES,
  parseCoreCapabilities,
  setCoreCapabilities,
} from '../../helpers/coreCapabilities';

const HY2 = 'hysteria2://secret@example.com:443?sni=example.com';
const VMESS =
  'vmess://eyJ2IjogIjIiLCAicHMiOiAibiIsICJhZGQiOiAiZXhhbXBsZS5jb20iLCAicG9ydCI6ICI0NDMiLCAiaWQiOiAiMTExMTExMTEtMjIyMi0zMzMzLTQ0NDQtNTU1NTU1NTU1NTU1IiwgImFpZCI6ICIwIiwgIm5ldCI6ICJ0Y3AifQ==';

describe('links the core cannot carry', () => {
  afterEach(() => setCoreCapabilities({ ...UNKNOWN_CORE_CAPABILITIES }));

  it('are accepted while the core is unknown', () => {
    expect(validateProxyUrl(HY2).valid).toBe(true);
  });

  it('Hysteria2 is refused on a core without QUIC', () => {
    setCoreCapabilities(parseCoreCapabilities({ quic: false }));
    expect(validateProxyUrl(HY2).valid).toBe(false);
    expect(validateProxyUrl(HY2).message).toContain('QUIC');
  });

  it('VMess is refused on a core that is not extended', () => {
    setCoreCapabilities(parseCoreCapabilities({ vmess: false }));
    expect(validateProxyUrl(VMESS).valid).toBe(false);
  });

  it('VMess passes on the extended core', () => {
    setCoreCapabilities(parseCoreCapabilities({ vmess: true }));
    expect(validateProxyUrl(VMESS).valid).toBe(true);
  });
});
