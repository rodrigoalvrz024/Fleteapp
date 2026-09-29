import Link from 'next/link';
import { AppTour } from '../app-tour';
import { SiteFooter, SiteNav } from '../site-shell';
import { pageMetadata } from '../seo';

export const metadata = pageMetadata({ title: 'Cómo usar Muvv paso a paso', description: 'Aprende a crear tu cuenta, solicitar un flete y confirmar la entrega en la app Muvv. Guía para clientes y conductores.', path: '/como-funciona' });

const guides = [
  { id: 'conductores', title: 'Para trabajar como conductor', lead: 'El registro y la revisión de documentos se realizan dentro de la app.', steps: [
    ['Descarga Muvv y elige Conductor', 'Crea tu cuenta seleccionando el perfil de conductor.'],
    ['Completa tus datos y documentos', 'Agrega los datos solicitados y fotos claras de tu licencia, permiso de circulación, revisión técnica y SOAP vigentes.'],
    ['Registra tu vehículo y envía a revisión', 'Completa la información de tu vehículo y envía tu registro a revisión. Revisa en la app si debes actualizar algún documento.'],
    ['Revisa los fletes disponibles', 'Cuando tu perfil esté aprobado, consulta ruta, carga, requisitos y pago estimado antes de aceptar un servicio.'],
    ['Realiza el traslado y registra la entrega', 'Sigue las indicaciones de la app, registra las fotos del servicio y confirma la entrega con el PIN del cliente.'],
  ] },
];

export default function HowItWorksPage() {
  return <>
    <SiteNav />
    <main id="contenido" tabIndex={-1}>
      <div className="brandBackdrop">
      <section className="section guideIntro">
        <h1>Muvv, paso a paso.</h1>
        <p>Conoce el recorrido antes de descargarla. Las solicitudes, el registro y el seguimiento se hacen en la app.</p>
        <nav className="guideNav" aria-label="Elige tu guía"><a className="secondaryAction darkLine" href="#clientes">Quiero pedir un flete</a><a className="secondaryAction darkLine" href="#conductores">Soy conductor</a></nav>
      </section>
      </div>
      <section className="section visualGuide" id="clientes" aria-labelledby="client-guide-title">
        <div className="sectionHeader"><h2 id="client-guide-title">Tu solicitud, en cinco pasos.</h2><p>Primero, descarga Muvv y crea tu cuenta como cliente. Después, abre la opción para solicitar un flete y sigue este recorrido.</p></div>
        <div id="recorrido"><AppTour /></div>
        <div className="afterRequest"><h3>¿Y después de solicitar?</h3><p>Consulta el estado de tu flete y el conductor asignado desde la app. Sigue las indicaciones de pago y confirma la recepción con tu PIN al momento de la entrega. Las fotos quedan asociadas al servicio.</p></div>
      </section>
      <section className="section preparationSection" aria-labelledby="prepare-title">
        <div className="sectionHeader"><h2 id="prepare-title">Antes de moverlo,<br />ten esto a mano.</h2><p>Unos detalles ayudan a describir mejor tu carga y coordinar el retiro.</p></div>
        <dl className="preparationList">
          <div><dt>Qué y cuánto vas a llevar</dt><dd>Cuenta los objetos e indica sus medidas aproximadas. Agrega fotos si ayudan a entender el tamaño o el estado de la carga.</dd></div>
          <div><dt>Cómo se entra y se sale</dt><dd>Ten a mano el piso, la disponibilidad de ascensor y los detalles de acceso para retirar y entregar.</dd></div>
          <div><dt>Si necesitas manos extra</dt><dd>Revisa quién ayudará a cargar y descargar. Selecciona ayudantes en la app si los necesitas.</dd></div>
          <div><dt>Cuándo estará todo listo</dt><dd>Elige un horario en que puedan recibir al conductor y prepara los objetos para el traslado.</dd></div>
        </dl>
      </section>
      {guides.map((guide) => <section className="section editorialSection guideSection" id={guide.id} key={guide.id} aria-labelledby={`${guide.id}-title`}>
        <div className="sectionHeader"><h2 id={`${guide.id}-title`}>{guide.title}</h2><p>{guide.lead}</p><Link className="textAction" href="/descargar">Ver opciones de descarga</Link></div>
        <ol className="stepRail" role="list">{guide.steps.map(([title, body], index) => <li className="stepItem" key={title}><span aria-hidden="true">{String(index + 1).padStart(2, '0')}</span><div><h3>{title}</h3><p>{body}</p></div></li>)}</ol>
      </section>)}
      <section className="ctaWrap"><div className="ctaBand"><div><h2>Todo continúa en la app.</h2><p>Consulta la disponibilidad para tu celular.</p></div><Link className="primaryAction lightSolid" href="/descargar">Descargar la app</Link></div></section>
    </main>
    <SiteFooter />
  </>;
}
