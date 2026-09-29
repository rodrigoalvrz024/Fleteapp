import type { Metadata } from 'next';

export const publicSiteUrl =
  (process.env.NEXT_PUBLIC_SITE_URL ?? 'https://muvv.cl').replace(/\/$/, '');
export const appBaseUrl =
  process.env.NEXT_PUBLIC_APP_URL ?? 'https://muvv-dev.web.app';
export const publicApiBaseUrl =
  process.env.NEXT_PUBLIC_API_URL ??
  'https://muvv-api-production.up.railway.app';

type SeoConfig = {
  title: string;
  description: string;
  path?: string;
  keywords?: string[];
};

export function pageMetadata({
  title,
  description,
  path = '/',
  keywords = [],
}: SeoConfig): Metadata {
  const canonical = `${publicSiteUrl}${path === '/' ? '' : path}`;
  const fullTitle = `${title} | Muvv`;

  return {
    title: fullTitle,
    description,
    keywords: [
      'fletes urbanos',
      'fletes Chile',
      'conductores verificados',
      'mudanzas urbanas',
      'transporte de carga urbana',
      ...keywords,
    ],
    alternates: {
      canonical,
    },
    openGraph: {
      title: fullTitle,
      description,
      url: canonical,
      siteName: 'Muvv',
      locale: 'es_CL',
      type: 'website',
      images: [{ url: '/muvv-social.jpg', width: 1200, height: 630, alt: 'Muvv: traslado de objetos con un vehículo urbano.' }],
    },
    twitter: {
      card: 'summary_large_image',
      title: fullTitle,
      description,
      images: ['/muvv-social.jpg'],
    },
  };
}
