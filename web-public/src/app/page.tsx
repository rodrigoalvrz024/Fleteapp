const trustItems = [
  'Conductores revisados',
  'Documentos privados',
  'Historial auditable',
  'Operacion monitoreada',
];

const audienceCards = [
  {
    title: 'Clientes',
    body: 'Solicita un flete, coordina origen y destino, y revisa el estado del servicio desde la app.',
    action: 'Entrar como cliente',
    href: 'https://fleteapp-8d8f7.web.app/#/login',
  },
  {
    title: 'Conductores',
    body: 'Completa tu onboarding, sube documentos y recibe solicitudes cuando tu cuenta este aprobada.',
    action: 'Postular como conductor',
    href: 'https://fleteapp-8d8f7.web.app/#/register',
  },
  {
    title: 'Equipo FleteApp',
    body: 'Administra usuarios, revisa documentos, monitorea metricas y consulta el historial operativo.',
    action: 'Abrir admin',
    href: 'https://fleteapp-8d8f7.web.app/#/admin',
  },
];

const steps = [
  'Cliente crea una solicitud',
  'Conductor aprobado acepta',
  'Operacion queda trazada',
];

export default function Home() {
  return (
    <main>
      <section className="hero">
        <nav className="nav" aria-label="Principal">
          <a className="brand" href="#inicio" aria-label="FleteApp inicio">
            <span className="brandIcon">F</span>
            <span>FleteApp</span>
          </a>
          <div className="navLinks">
            <a href="#soluciones">Soluciones</a>
            <a href="#operacion">Operacion</a>
            <a href="https://fleteapp-8d8f7.web.app/#/login">Ingresar</a>
          </div>
        </nav>

        <div className="heroContent" id="inicio">
          <p className="eyebrow">Fletes urbanos en Chile</p>
          <h1>FleteApp</h1>
          <p className="heroText">
            Una plataforma para pedir, aceptar y monitorear fletes con
            conductores verificados, documentos resguardados e historial
            operativo desde el primer viaje.
          </p>
          <div className="heroActions">
            <a className="primaryAction" href="https://fleteapp-8d8f7.web.app/#/register">
              Crear cuenta
            </a>
            <a className="secondaryAction" href="#soluciones">
              Ver como funciona
            </a>
          </div>
        </div>
      </section>

      <section className="section" id="soluciones">
        <div className="sectionHeader">
          <p className="eyebrow">Tres entradas, una misma operacion</p>
          <h2>Separado por tipo de usuario</h2>
        </div>
        <div className="audienceGrid">
          {audienceCards.map((card) => (
            <article className="audienceCard" key={card.title}>
              <h3>{card.title}</h3>
              <p>{card.body}</p>
              <a href={card.href}>{card.action}</a>
            </article>
          ))}
        </div>
      </section>

      <section className="operations" id="operacion">
        <div>
          <p className="eyebrow">Control operativo</p>
          <h2>Una base preparada para crecer con datos</h2>
          <p>
            FleteApp registra usuarios, documentos, fletes, pagos, auditoria y
            aceptaciones legales para que la operacion pueda analizarse con
            trazabilidad desde el inicio.
          </p>
        </div>
        <ol className="steps">
          {steps.map((step) => (
            <li key={step}>{step}</li>
          ))}
        </ol>
      </section>

      <section className="trust">
        {trustItems.map((item) => (
          <span key={item}>{item}</span>
        ))}
      </section>
    </main>
  );
}
