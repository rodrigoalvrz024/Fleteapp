// Set official store URLs before building. Empty values keep downloads unavailable.
function storeUrl(value: string | undefined, hostname: string): string | null {
  if (!value?.trim()) return null;
  try {
    const url = new URL(value.trim());
    if (url.protocol !== 'https:' || url.hostname !== hostname || url.username || url.password) return null;
    if (hostname === 'play.google.com' && (url.pathname !== '/store/apps/details' || !url.searchParams.get('id'))) return null;
    if (hostname === 'apps.apple.com' && !/\/id\d+\/?$/.test(url.pathname)) return null;
    return url.href;
  } catch {
    return null;
  }
}

export const downloadStores = [
  { id: 'android', name: 'Google Play', platform: 'Android', href: storeUrl(process.env.NEXT_PUBLIC_GOOGLE_PLAY_URL, 'play.google.com') },
  { id: 'ios', name: 'App Store', platform: 'iPhone', href: storeUrl(process.env.NEXT_PUBLIC_APP_STORE_URL, 'apps.apple.com') },
];
