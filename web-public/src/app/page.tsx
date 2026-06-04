import Link from 'next/link';
import { appBaseUrl, SiteFooter, SiteNav } from './site-shell';

const routes = [
  {
    title: 'Para clientes',
    body: 'Mueve muebles, compras voluminosas y carga urbana con precio visible antes de confirmar.',
    href: '/clientes',
  },
  {
    title: 'Para conductores',
    body: 'Accede a oportunidades de flete con precios claros y un proceso de verificacion ordenado.',
    href: '/conductores',
  },
  {
    title: 'Para negocios',
    body: 'Coordina entregas urbanas y conserva respaldo de cada servicio para tu operacion.',
    href: '/empresas',
  },
];

const principles = [
  'Precio antes de confirmar',
  'Conductores verificados',
  'Ayudantes cuando los necesitas',
  'Historial de cada servicio',
];

const operatingModel = [
  {
    title: 'Describe',
    body: 'Indica que necesitas mover, la ruta, el horario y si requieres ayudantes.',
  },
  {
    title: 'Confirma',
    body: 'Revisa el precio estimado y crea la solicitud cuando estes listo.',
  },
  {
    title: 'Sigue',
    body: 'Consulta el estado del servicio y conserva su historial para futuras referencias.',
  },
];

export default function Home() {
  return (
    <main>
      <section className="homeHero" id="inicio">
        <SiteNav />
        <div className="homeHeroInner">
          <p className="eyebrow">FleteApp en Chile</p>
          <h1>Mueve muebles, compras y carga urbana sin improvisar</h1>
          <p className="heroLead">
            Coordina tu traslado con conductores revisados, precios visibles y
            un historial claro desde la solicitud hasta la entrega.
          </p>
          <div className="heroActions">
            <a className="primaryAction dark" href={`${appBaseUrl}/#/auth/register`}>
              Comenzar
            </a>
            <a className="secondaryAction light" href={`${appBaseUrl}/#/auth/login`}>
              Ingresar
            </a>
          </div>
        </div>
      </section>

      <section className="introBand" aria-label="Beneficios principales">
        <div className="introInner">
          <p>
            Para una compra grande, un mueble nuevo, una mudanza pequena o una
            entrega de negocio: prepara el servicio con la informacion que
            necesitas antes de confirmar.
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
          <h2>Una solucion para cada necesidad de traslado</h2>
          <p>
            Conoce como FleteApp ayuda a clientes, conductores y negocios a
            coordinar fletes urbanos con mayor claridad.
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
          <h2>De la necesidad al traslado en tres pasos claros</h2>
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
          <p className="eyebrow">Tu proximo traslado</p>
          <h2>Crea tu cuenta y prepara tu primer flete</h2>
          <p>
            Guarda tus solicitudes, revisa precios y consulta el estado de cada
            servicio desde un espacio privado.
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
