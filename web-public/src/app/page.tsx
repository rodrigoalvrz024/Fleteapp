import Link from 'next/link';
import { appBaseUrl, SiteFooter, SiteNav } from './site-shell';

const routes = [
  {
    title: 'Para clientes',
    body: 'Planifica fletes urbanos con conductores revisados, precios visibles y seguimiento de cada solicitud.',
    href: '/clientes',
  },
  {
    title: 'Para conductores',
    body: 'Postula, registra tu vehiculo y mantén tus documentos al dia para operar cuando seas aprobado.',
    href: '/conductores',
  },
  {
    title: 'Para equipos',
    body: 'Administra documentos, solicitudes y trazabilidad operacional desde un panel interno separado.',
    href: '/empresas',
  },
];

const principles = [
  'Web publica para informar',
  'App privada para operar',
  'Conductores verificados',
  'Documentos protegidos',
];

const operatingModel = [
  {
    title: 'Conoce',
    body: 'La web explica la propuesta, perfiles y requisitos antes de crear una cuenta.',
  },
  {
    title: 'Registra',
    body: 'El acceso a solicitudes, documentos y paneles queda dentro de la app autenticada.',
  },
  {
    title: 'Opera',
    body: 'Cliente, conductor y administrador trabajan en vistas separadas, con roles y trazabilidad.',
  },
];

export default function Home() {
  return (
    <main>
      <section className="homeHero" id="inicio">
        <SiteNav />
        <div className="homeHeroInner">
          <p className="eyebrow">FleteApp en Chile</p>
          <h1>Fletes urbanos para mover carga con respaldo</h1>
          <p className="heroLead">
            Una red de clientes, conductores y operación interna para coordinar
            traslados con verificación documental, estados claros y soporte
            trazable.
          </p>
          <div className="heroActions">
            <Link className="primaryAction dark" href="/clientes">
              Ver soluciones
            </Link>
            <a className="secondaryAction light" href={`${appBaseUrl}/#/auth/login`}>
              Ingresar
            </a>
          </div>
        </div>
      </section>

      <section className="introBand" aria-label="Modelo publico">
        <div className="introInner">
          <p>
            La web publica no reemplaza la app. Presenta la marca, orienta a
            cada perfil y deriva al entorno autenticado solo cuando corresponde.
          </p>
          <div className="principleGrid">
            {principles.map((item) => (
              <span key={item}>{item}</span>
            ))}
          </div>
        </div>
      </section>

      <section className="section" id="soluciones">
        <div className="sectionHeader">
          <p className="eyebrow">Soluciones</p>
          <h2>Tres entradas publicas, una operacion separada</h2>
          <p>
            Cada perfil tiene una pagina publica propia. La accion operativa
            vive en la app, no dentro del sitio institucional.
          </p>
        </div>
        <div className="routeGrid">
          {routes.map((route) => (
            <Link className="routeCard" href={route.href} key={route.title}>
              <span>{route.title}</span>
              <p>{route.body}</p>
              <strong>Conocer mas</strong>
            </Link>
          ))}
        </div>
      </section>

      <section className="editorialSplit" id="modelo">
        <div>
          <p className="eyebrow">Como funciona</p>
          <h2>Separar comunicacion de operacion mantiene la experiencia clara</h2>
        </div>
        <ol className="modelList">
          {operatingModel.map((step) => (
            <li key={step.title}>
              <strong>{step.title}</strong>
              <span>{step.body}</span>
            </li>
          ))}
        </ol>
      </section>

      <section className="ctaBand">
        <div>
          <p className="eyebrow">Acceso privado</p>
          <h2>La solicitud de flete ocurre dentro de la app</h2>
          <p>
            Para proteger datos, documentos y seguimiento, el flujo operacional
            requiere cuenta autenticada.
          </p>
        </div>
        <div className="ctaActions">
          <a className="primaryAction dark" href={`${appBaseUrl}/#/auth/register`}>
            Crear cuenta
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
