import Link from 'next/link';
import { appBaseUrl, SiteFooter, SiteNav } from './site-shell';
import { pageMetadata } from './seo';

export const metadata = pageMetadata({
  title: 'Fletes urbanos verificados en Chile',
  description:
    'Pide, acepta y monitorea fletes urbanos con conductores verificados, pago protegido, fotos de retiro y entrega, PIN e historial operativo.',
  path: '/',
  keywords: ['pedir flete', 'app de fletes', 'fletes Santiago'],
});

const audiences = [
  {
    label: 'Clientes',
    title: 'Pide un flete cuando necesitas mover algo grande.',
    body: 'Carga, ruta, ayudantes y precio se preparan antes de confirmar.',
    href: '/clientes',
    action: 'Ver para clientes',
  },
  {
    label: 'Conductores',
    title: 'Recibe solicitudes con informacion clara antes de aceptar.',
    body: 'Postula, valida tus documentos y revisa oportunidades desde la app.',
    href: '/conductores',
    action: 'Ver para conductores',
  },
  {
    label: 'Empresas',
    title: 'Ordena traslados urbanos con respaldo por servicio.',
    body: 'Historial, evidencia, precios y estados para operaciones recurrentes.',
    href: '/empresas',
    action: 'Ver para empresas',
  },
];

const steps = [
  {
    title: 'Solicita',
    body: 'El cliente define ruta, carga, horario y ayudantes.',
  },
  {
    title: 'Asegura',
    body: 'El pago queda protegido antes de iniciar el servicio.',
  },
  {
    title: 'Entrega',
    body: 'El conductor registra fotos y confirma la entrega con PIN.',
  },
  {
    title: 'Liquida',
    body: 'Admin revisa el ciclo y libera el pago al conductor.',
  },
];

const trust = [
  'Conductores verificados',
  'Documentos privados',
  'Fotos de retiro y entrega',
  'PIN de confirmacion',
  'Pago protegido',
  'Historial auditable',
];

export default function Home() {
  return (
    <main>
      <section className="homeHero" id="inicio">
        <SiteNav />
        <div className="homeHeroInner">
          <p className="eyebrow">Fletes urbanos en Chile</p>
          <h1>Fletes para mover lo importante, sin improvisar.</h1>
          <p className="heroLead">
            muvv conecta clientes con conductores verificados para mover
            muebles, compras y carga urbana con trazabilidad desde la solicitud
            hasta la entrega.
          </p>
          <div className="heroActions">
            <a
              className="primaryAction lightSolid"
              href={`${appBaseUrl}/#/auth/register`}
              data-analytics-event="public.cta_click"
              data-analytics-entity-id="hero_request_freight"
            >
              Pedir un flete
            </a>
            <Link
              className="secondaryAction light"
              href="/conductores"
              data-analytics-event="public.cta_click"
              data-analytics-entity-id="hero_driver"
            >
              Trabajar como conductor
            </Link>
          </div>
        </div>
      </section>

      <section className="choiceBand" aria-label="Entradas principales">
        <div className="choiceInner">
          {audiences.map((item) => (
            <Link
              className="choiceItem"
              href={item.href}
              key={item.label}
              data-analytics-event="public.audience_click"
              data-analytics-entity-id={item.label.toLowerCase()}
            >
              <span>{item.label}</span>
              <strong>{item.title}</strong>
              <small>{item.action}</small>
            </Link>
          ))}
        </div>
      </section>

      <section className="section editorialSection" id="soluciones">
        <div className="sectionHeader">
          <p className="eyebrow darkEyebrow">Como funciona</p>
          <h2>Un flujo simple para una operacion seria.</h2>
          <p>
            La web publica orienta. La app se encarga de solicitar, aceptar,
            pagar, registrar evidencia y cerrar el servicio.
          </p>
        </div>
        <div className="stepRail">
          {steps.map((step, index) => (
            <article className="stepItem" key={step.title}>
              <span>{String(index + 1).padStart(2, '0')}</span>
              <h3>{step.title}</h3>
              <p>{step.body}</p>
            </article>
          ))}
        </div>
      </section>

      <section className="featureBand">
        <div className="featureImage" aria-hidden="true" />
        <div className="featureCopy">
          <p className="eyebrow darkEyebrow">Pago recomendado</p>
          <h2>Pago protegido antes del viaje, liquidacion despues de la entrega.</h2>
          <p>
            Para reducir riesgos, el cliente deberia dejar el pago autorizado o
            pagado antes de iniciar. Cuando el servicio queda completado con
            evidencia y PIN, admin valida la liquidacion al conductor.
          </p>
          <a
            className="primaryAction dark"
            href={`${appBaseUrl}/#/auth/register`}
            data-analytics-event="public.cta_click"
            data-analytics-entity-id="payment_section_register"
          >
            Crear cuenta
          </a>
        </div>
      </section>

      <section className="section trustSection">
        <div className="sectionHeader compact">
          <p className="eyebrow darkEyebrow">Confianza operacional</p>
          <h2>Mas que pedir un camion.</h2>
          <p>
            muvv esta pensada para registrar lo que pasa en cada traslado y
            dejar evidencia util para clientes, conductores y soporte.
          </p>
        </div>
        <div className="trustGrid">
          {trust.map((item) => (
            <span key={item}>{item}</span>
          ))}
        </div>
      </section>

      <section className="ctaBand">
        <div>
          <p className="eyebrow darkEyebrow">Empieza en la app</p>
          <h2>Usa la web para conocer muvv. Usa la app para operar.</h2>
          <p>
            Esta separacion mantiene la experiencia publica simple y la
            operacion privada, segura y trazable.
          </p>
        </div>
        <div className="ctaActions">
          <a
            className="primaryAction dark"
            href={`${appBaseUrl}/#/auth/register`}
            data-analytics-event="public.cta_click"
            data-analytics-entity-id="bottom_register"
          >
            Registrarse
          </a>
          <a
            className="secondaryAction darkLine"
            href={`${appBaseUrl}/#/auth/login`}
            data-analytics-event="public.cta_click"
            data-analytics-entity-id="bottom_login"
          >
            Ingresar
          </a>
        </div>
      </section>

      <SiteFooter />
    </main>
  );
}
