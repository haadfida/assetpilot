// The BYOK Anthropic key lives only in this tab's sessionStorage: it is gone when the tab closes,
// is never sent anywhere except the AssetPilot API's x-anthropic-key header, and is not logged.

const STORAGE_KEY = "assetpilot.anthropicKey";

export function loadKey(): string | null {
  try {
    return sessionStorage.getItem(STORAGE_KEY);
  } catch {
    return null;
  }
}

export function saveKey(key: string | null): void {
  try {
    if (key) sessionStorage.setItem(STORAGE_KEY, key);
    else sessionStorage.removeItem(STORAGE_KEY);
  } catch {
    // storage unavailable (private mode); the key stays in memory for this page only
  }
}

/** Basic shape check, mirroring the server's (printable ASCII, at most 256 characters). */
export function isPlausibleKey(key: string): boolean {
  return key.length >= 10 && key.length <= 256 && /^[\x21-\x7e]+$/.test(key);
}

export function maskKey(key: string): string {
  return key.length <= 12 ? "••••" : `${key.slice(0, 7)}…${key.slice(-4)}`;
}
