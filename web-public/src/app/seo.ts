import type { Metadata } from 'next';

export const publicSiteUrl =
  process.env.NEXT_PUBLIC_SITE_URL ?? 'https://fleteapp-public-8d8f7.web.app';
export const appBaseUrl =
  process.env.NEXT_PUBLIC_APP_URL ?? 'https://fleteapp-8d8f7.web.app';
export const publicApiBaseUrl =
  process.env.NEXT_PUBLIC_API_URL ??
  'https://fleteapp-api-i3wy5watea-uc.a.run.app';

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
      'mudanzas pequenas',
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
    },
    twitter: {
      card: 'summary_large_image',
      title: fullTitle,
      description,
    },
  };
}
