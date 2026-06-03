import { appBaseUrl, SiteFooter, SiteNav } from './site-shell';

type ProfilePageProps = {
  eyebrow: string;
  title: string;
  lead: string;
  imageClass: string;
  primaryAction: string;
  primaryHref: string;
  sections: Array<{
    title: string;
    body: string;
  }>;
  highlights: string[];
};

export function ProfilePage({
  eyebrow,
  title,
  lead,
  imageClass,
  primaryAction,
  primaryHref,
  sections,
  highlights,
}: ProfilePageProps) {
  return (
    <main>
      <section className={`profileHero ${imageClass}`}>
        <SiteNav />
        <div className="profileHeroInner">
          <p className="eyebrow">{eyebrow}</p>
          <h1>{title}</h1>
          <p>{lead}</p>
          <div className="heroActions">
            <a className="primaryAction lightSolid" href={primaryHref}>
              {primaryAction}
            </a>
            <a className="secondaryAction light" href={`${appBaseUrl}/#/auth/login`}>
              Ingresar
            </a>
          </div>
        </div>
      </section>

      <section className="profileContent">
        <div className="profileSections">
          {sections.map((section) => (
            <article key={section.title}>
              <h2>{section.title}</h2>
              <p>{section.body}</p>
            </article>
          ))}
        </div>
        <aside className="profileAside">
          <h2>Lo importante</h2>
          <div>
            {highlights.map((item) => (
              <span key={item}>{item}</span>
            ))}
          </div>
        </aside>
      </section>

      <section className="ctaBand">
        <div>
          <p className="eyebrow">Siguiente paso</p>
          <h2>La operacion ocurre dentro de la app</h2>
          <p>
            La web publica informa. Las cuentas, documentos, solicitudes y
            seguimiento se gestionan en el entorno autenticado.
          </p>
        </div>
        <div className="ctaActions">
          <a className="primaryAction dark" href={primaryHref}>
            {primaryAction}
          </a>
          <a className="secondaryAction darkLine" href={`${appBaseUrl}/#/auth/login`}>
            Ingresar
          </a>
        </div>
      </section>

      <SiteFooter />
    </main>
  );
}
