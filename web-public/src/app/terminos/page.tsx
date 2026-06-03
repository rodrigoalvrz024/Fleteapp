import Link from 'next/link';
import { termsSections } from '../legal-content';

export default function TermsPage() {
  return (
    <main className="legalPage">
      <header className="legalHeader">
        <Link href="/">Volver a FleteApp</Link>
        <h1>Términos de uso FleteApp</h1>
        <p>
          Versión 2026-05-26. Estos términos regulan el uso de la plataforma
          pública y de la app operacional.
        </p>
      </header>
      <section className="legalContent" aria-label="Términos de uso">
        {termsSections.map((section) => (
          <article className="legalSection" key={section.title}>
            <h2>{section.title}</h2>
            <p>{section.body}</p>
          </article>
        ))}
      </section>
    </main>
  );
}
