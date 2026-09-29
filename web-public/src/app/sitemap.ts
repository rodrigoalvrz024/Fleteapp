import type { MetadataRoute } from 'next';
import { publicSiteUrl } from './seo';

export const dynamic = 'force-static';

export default function sitemap(): MetadataRoute.Sitemap {
  return ['', '/clientes', '/conductores', '/empresas', '/como-funciona', '/descargar', '/terminos', '/privacidad']
    .map((path) => ({ url: `${publicSiteUrl}${path}` }));
}
