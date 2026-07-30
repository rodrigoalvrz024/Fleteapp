import Link from 'next/link';
import { termsSections } from '../legal-content';
import { pageMetadata } from '../seo';
import { SiteFooter } from '../site-shell';

export const metadata = pageMetadata({
  title: 'Terminos de uso',
  description:
    'Terminos de uso de muvv para clientes, conductores, pagos, documentos, seguridad y responsabilidades operacionales.',
  path: '/terminos',
  keywords: ['terminos muvv', 'condiciones fletes', 'legal fletes'],
});

export default function TermsPage() {
  return (
    <main className="legalPage">
      <header className="legalHeader">
        <Link className="legalBack" href="/">Volver a muvv</Link>
        <p className="eyebrow darkEyebrow">Legal</p>
        <h1>Terminos de uso muvv</h1>
        <p>
          Version 2026-05-26. Estos terminos regulan el uso de la plataforma
          publica y de la app operacional.
        </p>
      </header>
      <section className="legalSummary" aria-label="Resumen legal">
        <strong>Resumen</strong>
        <span>
          La app permite solicitar, aceptar y cerrar fletes con respaldo. Las
          cuentas deben usar informacion real y los conductores deben mantener
          sus documentos vigentes.
        </span>
      </section>
      <section className="legalContent" aria-label="Terminos de uso">
        {termsSections.map((section) => (
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
