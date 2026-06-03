import Link from 'next/link';
import { privacySections } from '../legal-content';

export default function PrivacyPage() {
  return (
    <main className="legalPage">
      <header className="legalHeader">
        <Link href="/">Volver a FleteApp</Link>
        <h1>Política de privacidad FleteApp</h1>
        <p>
          Versión 2026-05-26. Este documento explica qué datos tratamos, para
          qué los usamos y cómo protegemos la información operacional.
        </p>
      </header>
      <section className="legalContent" aria-label="Política de privacidad">
        {privacySections.map((section) => (
          <article className="legalSection" key={section.title}>
            <h2>{section.title}</h2>
            <p>{section.body}</p>
          </article>
        ))}
      </section>
    </main>
  );
}
