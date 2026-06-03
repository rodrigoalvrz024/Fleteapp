import { StartRequestPanel } from './start-request-panel';

const appBaseUrl = 'https://fleteapp-8d8f7.web.app';

const audienceCards = [
  {
    eyebrow: 'Clientes',
    title: 'Pide un flete sin llamadas eternas',
    body: 'Ingresa origen, destino y detalles de carga. La app mantiene el estado del servicio visible desde la solicitud.',
    action: 'Entrar como cliente',
    href: `${appBaseUrl}/#/auth/login`,
  },
  {
    eyebrow: 'Conductores',
    title: 'Postula con documentos al día',
    body: 'Completa tu perfil, registra vehículo y sube licencia, permiso, SOAP y revisión técnica para evaluación.',
    action: 'Postular',
    href: `${appBaseUrl}/#/auth/register`,
  },
  {
    eyebrow: 'Equipo',
    title: 'Opera con panel y trazabilidad',
    body: 'Revisa documentos, solicitudes, alertas, historial y actividad operacional desde el panel interno.',
    action: 'Abrir admin',
    href: `${appBaseUrl}/#/admin`,
  },
];

const processSteps = [
  {
    title: 'Solicita',
    body: 'El cliente crea una solicitud con ruta, carga, ayudantes y horario.',
  },
  {
    title: 'Valida',
    body: 'Solo conductores aprobados pueden operar dentro de la plataforma.',
  },
  {
    title: 'Monitorea',
    body: 'Cada cambio importante queda registrado para soporte y análisis futuro.',
  },
];

const trustItems = [
  'Conductores revisados',
  'Documentos privados',
  'Aceptación legal registrada',
  'Historial auditable',
  'Panel operacional',
  'Base lista para datos',
];

const metrics = [
  { value: '3', label: 'entradas claras' },
  { value: '24/7', label: 'web disponible' },
  { value: '100%', label: 'flujo trazable' },
];

export default function Home() {
  return (
    <main>
      <section className="hero" id="inicio">
        <nav className="nav" aria-label="Principal">
          <a className="brand" href="#inicio" aria-label="FleteApp inicio">
            <span className="brandIcon">F</span>
            <span>FleteApp</span>
          </a>
          <div className="navLinks">
            <a href="#soluciones">Soluciones</a>
            <a href="#proceso">Proceso</a>
            <a href="#confianza">Confianza</a>
            <a className="navAction" href={`${appBaseUrl}/#/auth/login`}>
              Ingresar
            </a>
          </div>
        </nav>

        <div className="heroContent heroGrid">
          <div className="heroCopy">
            <p className="eyebrow">Fletes urbanos en Chile</p>
            <h1>FleteApp</h1>
            <p className="heroText">
              Una plataforma para pedir, aceptar y monitorear fletes con
              conductores verificados, documentos resguardados e historial
              operativo desde el primer viaje.
            </p>
            <div className="heroActions">
              <a className="primaryAction" href={`${appBaseUrl}/#/auth/login`}>
                Entrar a la app
              </a>
              <a className="secondaryAction" href="#soluciones">
                Ver cómo funciona
              </a>
            </div>
            <dl className="metricStrip" aria-label="Resumen FleteApp">
              {metrics.map((metric) => (
                <div key={metric.label}>
                  <dt>{metric.value}</dt>
                  <dd>{metric.label}</dd>
                </div>
              ))}
            </dl>
          </div>
          <StartRequestPanel />
        </div>
      </section>

      <section className="section" id="soluciones">
        <div className="sectionHeader">
          <p className="eyebrow">Tres perfiles, una operación</p>
          <h2>Una web pública clara y una app interna para operar</h2>
          <p>
            La página pública explica, orienta y deriva. La app Flutter queda
            reservada para autenticación, solicitudes, conducción y panel admin.
          </p>
        </div>
        <div className="audienceGrid">
          {audienceCards.map((card) => (
            <article className="audienceCard" key={card.title}>
              <p>{card.eyebrow}</p>
              <h3>{card.title}</h3>
              <span>{card.body}</span>
              <a href={card.href}>{card.action}</a>
            </article>
          ))}
        </div>
      </section>

      <section className="processBand" id="proceso">
        <div className="processInner">
          <div className="sectionHeader compactHeader">
            <p className="eyebrow">Cómo funciona</p>
            <h2>Simple para usuarios, ordenado para operación</h2>
          </div>
          <ol className="steps">
            {processSteps.map((step) => (
              <li key={step.title}>
                <strong>{step.title}</strong>
                <span>{step.body}</span>
              </li>
            ))}
          </ol>
        </div>
      </section>

      <section className="section securitySection" id="confianza">
        <div>
          <p className="eyebrow">Confianza y datos</p>
          <h2>Preparada para crecer con control desde el inicio</h2>
          <p>
            FleteApp prioriza documentos protegidos, roles claros, aceptación
            de términos y registros históricos para decisiones data-driven.
          </p>
        </div>
        <div className="trustGrid">
          {trustItems.map((item) => (
            <span key={item}>{item}</span>
          ))}
        </div>
      </section>

      <footer className="footer">
        <div>
          <strong>FleteApp</strong>
          <span>Fletes urbanos verificados para Chile.</span>
        </div>
        <nav aria-label="Legal">
          <a href="/terminos">Términos</a>
          <a href="/privacidad">Privacidad</a>
          <a href={`${appBaseUrl}/#/auth/login`}>Ingresar</a>
        </nav>
      </footer>
    </main>
  );
}
