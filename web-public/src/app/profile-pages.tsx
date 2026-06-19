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
            <a
              className="primaryAction lightSolid"
              href={primaryHref}
              data-analytics-event="public.cta_click"
              data-analytics-entity-id={`${eyebrow.toLowerCase()}_hero_primary`}
            >
              {primaryAction}
            </a>
            <a
              className="secondaryAction light"
              href={`${appBaseUrl}/#/auth/login`}
              data-analytics-event="public.cta_click"
              data-analytics-entity-id={`${eyebrow.toLowerCase()}_hero_login`}
            >
              Ingresar
            </a>
          </div>
        </div>
      </section>

      <section className="audienceIntro">
        <div>
          <p className="eyebrow darkEyebrow">Operacion</p>
          <h2>Una experiencia clara antes, durante y despues del flete.</h2>
        </div>
        <p>
          FleteApp separa la informacion publica del espacio privado. La web
          explica; la app registra solicitudes, documentos, evidencia, pagos y
          seguimiento operativo.
        </p>
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
          <p className="eyebrow darkEyebrow">Siguiente paso</p>
          <h2>Continua en la app privada de FleteApp.</h2>
          <p>
            Crea tu cuenta para guardar solicitudes, documentos e historial en
            un espacio privado.
          </p>
        </div>
        <div className="ctaActions">
          <a
            className="primaryAction dark"
            href={primaryHref}
            data-analytics-event="public.cta_click"
            data-analytics-entity-id={`${eyebrow.toLowerCase()}_bottom_primary`}
          >
            {primaryAction}
          </a>
          <a
            className="secondaryAction darkLine"
            href={`${appBaseUrl}/#/auth/login`}
            data-analytics-event="public.cta_click"
            data-analytics-entity-id={`${eyebrow.toLowerCase()}_bottom_login`}
          >
            Ingresar
          </a>
        </div>
      </section>

      <SiteFooter />
    </main>
  );
}
