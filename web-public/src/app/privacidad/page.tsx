import Link from 'next/link';
import { privacySections } from '../legal-content';
import { pageMetadata } from '../seo';
import { SiteFooter } from '../site-shell';

export const metadata = pageMetadata({
  title: 'Politica de privacidad',
  description:
    'Politica de privacidad de FleteApp sobre datos de cuenta, ubicacion operativa, solicitudes, pagos y documentos de conductor.',
  path: '/privacidad',
  keywords: ['privacidad fleteapp', 'datos personales chile', 'proteccion de datos'],
});

export default function PrivacyPage() {
  return (
    <main className="legalPage">
      <header className="legalHeader">
        <Link className="legalBack" href="/">Volver a FleteApp</Link>
        <p className="eyebrow darkEyebrow">Privacidad</p>
        <h1>Politica de privacidad FleteApp</h1>
        <p>
          Version 2026-05-26. Este documento explica que datos tratamos, para
          que los usamos y como protegemos la informacion operacional.
        </p>
      </header>
      <section className="legalSummary" aria-label="Resumen de privacidad">
        <strong>Resumen</strong>
        <span>
          En esta etapa no pedimos biometria. Si se suben documentos de
          conductor o vehiculo, deben mantenerse privados, con acceso limitado
          y registro de revision.
        </span>
      </section>
      <section className="legalContent" aria-label="Politica de privacidad">
        {privacySections.map((section) => (
          <article className="legalSection" key={section.title}>
            <h2>{section.title}</h2>
            <p>{section.body}</p>
          </article>
        ))}
      </section>
      <SiteFooter />
    </main>
  );
}
