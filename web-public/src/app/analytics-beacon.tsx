'use client';

import { useEffect } from 'react';
import { usePathname } from 'next/navigation';
import { publicApiBaseUrl } from './seo';

type AnalyticsPayload = {
  event_type: string;
  entity_type: string;
  entity_id: string;
  metadata?: Record<string, string | number | boolean | null>;
};

function sendAnalytics(payload: AnalyticsPayload) {
  const body = JSON.stringify({
    ...payload,
    metadata: {
      source: 'web_public',
      path: window.location.pathname,
      referrer: document.referrer || null,
      title: document.title,
      ...payload.metadata,
    },
  });

  const url = `${publicApiBaseUrl}/analytics/events`;
  if (navigator.sendBeacon) {
    const blob = new Blob([body], { type: 'application/json' });
    navigator.sendBeacon(url, blob);
    return;
  }

  fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body,
    keepalive: true,
  }).catch(() => {
    // Analytics should never block the public site.
  });
}

export function AnalyticsBeacon() {
  const pathname = usePathname();

  useEffect(() => {
    sendAnalytics({
      event_type: 'public.page_view',
      entity_type: 'public_page',
      entity_id: pathname || '/',
    });
  }, [pathname]);

  useEffect(() => {
    const onClick = (event: MouseEvent) => {
      const target = event.target;
      if (!(target instanceof Element)) return;
      const element = target.closest<HTMLElement>('[data-analytics-event]');
      if (!element) return;
      sendAnalytics({
        event_type: element.dataset.analyticsEvent || 'public.cta_click',
        entity_type: element.dataset.analyticsEntityType || 'public_cta',
        entity_id: element.dataset.analyticsEntityId || element.textContent?.trim() || 'unknown',
        metadata: {
          label: element.textContent?.trim() || null,
          href: element.getAttribute('href'),
        },
      });
    };

    document.addEventListener('click', onClick, true);
    return () => document.removeEventListener('click', onClick, true);
  }, []);

  return null;
}
