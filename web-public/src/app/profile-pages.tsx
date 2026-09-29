import { SiteFooter, SiteNav } from './site-shell';

type ProfilePageProps = {
  eyebrow: string;
  title: string;
  lead: string;
  imageClass: string;
  guideHref: string;
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
  guideHref,
  sections,
  highlights,
}: ProfilePageProps) {
  return (
    <>
      <SiteNav />
    <main id="contenido" tabIndex={-1}>
      <section className={`profileHero brandBackdrop ${imageClass}`}>
        <div className="profileHeroInner">
          <p className="eyebrow">{eyebrow}</p>
          <h1>{title}</h1>
          <p>{lead}</p>
          <div className="heroActions">
            <a
              className="primaryAction lightSolid"
              href="/descargar"
              data-analytics-event="public.cta_click"
              data-analytics-entity-id={`${eyebrow.toLowerCase()}_hero_primary`}
            >
              Descargar la app
            </a>
            <a
              className="secondaryAction light"
              href={guideHref}
              data-analytics-event="public.cta_click"
              data-analytics-entity-id={`${eyebrow.toLowerCase()}_hero_guide`}
            >
              Ver el paso a paso
            </a>
          </div>
        </div>
      </section>

      <section className="audienceIntro">
        <div>
          <h2>Claridad antes, durante y después del flete.</h2>
        </div>
        <p>
          {eyebrow === 'Conductores'
            ? 'Revisa las solicitudes y decide cuáles aceptar. Consulta ruta, carga y pago estimado antes de realizar un servicio.'
            : 'Prepara tu traslado, revisa sus detalles y consulta el historial del servicio en tu cuenta. La información que necesitas, en un solo lugar.'}
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

      <section className="ctaBand profileCta">
        <div>
          <h2>Tu próximo paso empieza en la app.</h2>
          <p>
            Descarga Muvv en tu celular. El registro, las solicitudes y el
            historial del servicio se encuentran dentro de la app.
          </p>
        </div>
        <div className="ctaActions">
          <a
            className="primaryAction dark"
            href="/descargar"
            data-analytics-event="public.cta_click"
            data-analytics-entity-id={`${eyebrow.toLowerCase()}_bottom_primary`}
          >
            Descargar la app
          </a>
          <a
            className="secondaryAction darkLine"
            href={guideHref}
            data-analytics-event="public.cta_click"
            data-analytics-entity-id={`${eyebrow.toLowerCase()}_bottom_guide`}
          >
            Ver el paso a paso
          </a>
        </div>
      </section>

    </main>
      <SiteFooter />
    </>
  );
}
