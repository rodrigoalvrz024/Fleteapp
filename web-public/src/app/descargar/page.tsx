import Link from 'next/link';
import { SiteFooter, SiteNav } from '../site-shell';
import { LaunchAvailability } from './launch-form';
import { downloadStores } from '../download-links';
import { pageMetadata } from '../seo';

export const metadata = pageMetadata({ title: 'Descarga la app Muvv', description: 'Consulta la disponibilidad de Muvv para Android y iPhone y conoce cómo empezar a usar la app.', path: '/descargar' });

export default function DownloadPage() {
  const available = downloadStores.some((store) => store.href);
  return <>
    <SiteNav />
    <main id="contenido" tabIndex={-1}>
      <div className="brandBackdrop">
      <section className="section downloadSection" aria-labelledby="download-title">
        <div className="sectionHeader">
          <h1 id="download-title">Tu próximo Muvv<br />empieza en tu celular.</h1>
          <p>Descarga la app para crear tu cuenta, pedir un flete o postular como conductor. Si aún no está disponible, inscríbete para recibir el aviso de lanzamiento.</p>
          <p className="downloadNotice">{available ? 'Elige la tienda de tu celular. Las opciones habilitadas te llevan a la ficha oficial de Muvv.' : 'Próximamente en Google Play y App Store. Elige tu tienda y déjanos tus datos para avisarte.'}</p>
        </div>
        <LaunchAvailability />
        <Link className="textAction" href="/como-funciona">Conoce la app paso a paso</Link>
      </section>
      </div>
    </main>
    <SiteFooter />
  </>;
}
