import Link from 'next/link';
import Image from 'next/image';
import { HomeVisual } from './home-visual';
import { AppTour } from './app-tour';
import { SiteFooter, SiteNav } from './site-shell';
import { pageMetadata } from './seo';
import { downloadStores } from './download-links';
import { StoreBadges } from './store-badges';
import { paymentContent } from './payment-content';

export const metadata = pageMetadata({
  title: 'Fletes urbanos y mudanzas en Chile',
  description: '¿No cabe en tu auto? Pide un Muvv. Mueve muebles, compras grandes y mudanzas desde la app, con precio visible antes de solicitar.',
  path: '/',
  keywords: ['pedir flete', 'app de fletes', 'mudanzas urbanas'],
});

const audiences = [
  { label: 'Clientes', title: 'Eso que compraste. Ese nuevo comienzo.', body: 'Muebles, compras grandes o una mudanza pequeña. Prepara tu traslado con ruta, carga y precio claros.', href: '/clientes', action: 'Conocer Muvv para clientes' },
  { label: 'Conductores', title: 'Tu vehículo. Nuevas oportunidades.', body: 'Preinscríbete para el lanzamiento en la Región Metropolitana. La validación de documentos viene después, en la app.', href: '/conductores', action: 'Preinscribirme como conductor' },
  { label: 'Empresas', title: 'Tu negocio también se mueve.', body: 'Organiza tus traslados urbanos con historial y evidencia por servicio.', href: '/empresas', action: 'Conocer Muvv para empresas' },
];
const uses = [
  ['Muebles', 'Ese sofá que encontraste.', 'Una mesa, un sillón o un mueble que necesita más espacio para llegar a su destino.'],
  ['Electrodomésticos', 'Tu nueva lavadora.', 'Describe sus medidas y revisa el vehículo y la ayuda que necesitas para trasladarla.'],
  ['Mudanzas', 'Tu próximo comienzo.', 'Agrega los objetos que vas a mover de un hogar a otro y revisa las opciones de tu traslado.'],
  ['Compras grandes', 'Lo compraste. Ahora muévelo.', 'Indica dónde se retira tu compra y a dónde debe llegar. El resto empieza en la app.'],
];
const quickSteps = [
  ['Cuéntanos qué vas a mover.', 'Indica origen, destino y los objetos que necesitas transportar.'],
  ['Revisa tu traslado.', 'Elige el vehículo y el horario, y conoce el precio antes de solicitar.'],
  ['Sigue tu flete.', 'Consulta el estado en la app y confirma la recepción con tu PIN.'],
];
const questions = [
  { title: paymentContent.faqTitle, body: paymentContent.faqBody },
  { title: paymentContent.refundTitle, body: paymentContent.refundBody },
  { title: '¿Puedo pedir un flete desde esta web?', body: 'Esta web te explica cómo funciona Muvv y dónde descargarla. El registro, las solicitudes y el seguimiento se realizan en la app.' },
  { title: '¿Dónde puedo descargar la app?', body: 'Entra a Descargar la app para consultar las opciones de Android y iPhone. Mientras la descarga esté pendiente, puedes dejar tus datos para recibir el aviso de lanzamiento.' },
  { title: '¿Qué puedo mover con Muvv?', body: 'Muebles, compras grandes y carga urbana. Al solicitar tu flete, detalla lo que necesitas trasladar para preparar el servicio.' },
  { title: '¿Cuándo conozco el precio?', body: 'Antes de confirmar el servicio. Indica la ruta, el tipo de carga y los ayudantes que necesitas para preparar tu solicitud.' },
  { title: '¿Cómo se confirma la entrega?', body: 'El conductor registra fotos y la entrega se confirma con un PIN. La evidencia queda asociada al servicio en tu historial.' },
  { title: '¿Cómo puedo trabajar como conductor?', body: 'Visita la sección Conductores y preinscríbete para el lanzamiento. Te contactaremos con los próximos pasos. La preinscripción no crea una cuenta ni reemplaza la revisión de documentos en la app.' },
];

const appPreviews = [
  { image: '01-route', title: 'Define tu ruta', body: 'Indica el punto de retiro y el destino.', alt: 'Pantalla de Muvv para ingresar origen y destino de un flete.' },
  { image: '03-vehicle', title: 'Elige tu vehículo', body: 'Compara las opciones para tu carga.', alt: 'Pantalla de Muvv con opciones de vehículos para la carga declarada.' },
  { image: '05-price', title: 'Revisa antes de solicitar', body: 'Comprueba los detalles y el precio.', alt: 'Resumen de una solicitud en Muvv con un precio de demostración.' },
];

function Arrow() {
  return <svg className="arrowIcon" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M5 12h14M13 6l6 6-6 6" /></svg>;
}

export default function Home() {
  const downloadLabel = downloadStores.some(store => store.href) ? "Descargar Muvv" : "Ver disponibilidad de la app";
  return (
    <>
      <SiteNav />
      <main id="contenido" tabIndex={-1}>
        <section className="homeHero brandBackdrop" id="inicio" aria-labelledby="hero-title">
          <div className="homeHeroInner">
            <div className="heroCopy">
              <p className="eyebrow">Fletes urbanos y mudanzas desde tu celular</p>
              <h1 id="hero-title">¿No cabe en tu auto?<br /><span>Pide un Muvv.</span></h1>
              <p className="heroLead">Mueve muebles, electrodomésticos y tus cosas de un hogar a otro. En la app eliges la ruta, describes tu carga y revisas el precio antes de solicitar.</p>
              <div className="heroActions">
                <a className="primaryAction dark" href="/descargar" data-analytics-event="public.cta_click" data-analytics-entity-id="hero_download">{downloadLabel} <Arrow /></a>
                <a className="textAction" href="#recorrido">Ver cómo funciona <svg className="arrowIcon" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" aria-hidden="true"><path d="M12 5v14m-6-6 6 6 6-6" /></svg></a>
              </div>
              <StoreBadges />
              <p className="heroNote">Las solicitudes se realizan en la app. Consulta su disponibilidad antes de empezar.</p>
            </div>
            <HomeVisual />
          </div>
          <div className="heroAssurances" aria-label="Respaldo del servicio">
            <span><i aria-hidden="true" />Conductores verificados</span>
            <span><i aria-hidden="true" />Precio antes de solicitar</span>
            <span><i aria-hidden="true" />Confirmación con PIN</span>
          </div>
        </section>
        <section className="section useSection" id="que-puedes-mover" aria-labelledby="uses-title">
          <div className="sectionHeader"><p className="eyebrow">Un espacio más grande para tus planes</p><h2 id="uses-title">Para eso que no cabe<br />en tu auto.</h2><p>De una compra grande a un cambio de hogar. Cuéntanos qué necesitas mover.</p></div>
          <div className="useGrid">{uses.map(([label, title, body], index) => <article className="useCard" key={label}><span className="useNumber" aria-hidden="true">0{index + 1}</span><p className="useLabel">{label}</p><h3>{title}</h3><p>{body}</p><Link className="textAction" href="/descargar" data-analytics-event="public.cta_click" data-analytics-entity-id={`use_${index}`}>Ver la app <Arrow /></Link></article>)}</div>
        </section>
        <section className="section visualGuide" id="recorrido" aria-labelledby="steps-title">
          <div className="sectionHeader">
            <h2 id="steps-title">Así funciona Muvv.</h2>
            <p>Tu solicitud se prepara en el celular. Primero, descarga la app y crea tu cuenta.</p>
          </div>
          <ol className="quickSteps">{quickSteps.map(([title, body], index) => <li key={title}><span aria-hidden="true">0{index + 1}</span><h3>{title}</h3><p>{body}</p></li>)}</ol>
          <div className="appPreviewHeader"><h3>Así se ve en tu celular.</h3><p>Pantallas reales de Muvv. Las direcciones y los precios son ejemplos.</p></div>
          <p className="appPreviewHint">Desliza para ver las tres pantallas. Toca una para ampliarla.</p>
          <ul className="appPreviewGallery" aria-label="Vista previa de la app">
            {appPreviews.map(screen => <li key={screen.image}>
              <a className="appPreviewImage" href={`/app-screens/${screen.image}.webp`} target="_blank" rel="noopener noreferrer" aria-label={`Ampliar: ${screen.title} (se abre en otra pestaña)`}>
                <div className="phoneFrame"><Image src={`/app-screens/${screen.image}.webp`} alt={screen.alt} width={786} height={1704} sizes="240px" /></div>
              </a>
              <h4>{screen.title}</h4><p>{screen.body}</p>
            </li>)}
          </ul>
          <details className="tourDisclosure"><summary>Ver las cinco pantallas de la app <span className="faqPlus" aria-hidden="true" /></summary><AppTour /></details>
          <Link className="textAction" href="/como-funciona">Guía completa para clientes y conductores <Arrow /></Link>
        </section>
        <section className="section trustSection" aria-labelledby="trust-title">
          <div className="sectionHeader"><h2 id="trust-title">Lo importante<br />va con respaldo.</h2><p>La confianza también está en los detalles. Cada traslado reúne información útil para ti, el conductor y soporte.</p></div>
          <div className="trustList">
            <article><h3>Sabes con quién se mueve</h3><p>Conductores verificados y documentos resguardados en privado.</p></article>
            <article><h3>Queda registro de la entrega</h3><p>Fotos de retiro y entrega, confirmación con PIN e historial por flete.</p></article>
            <article><h3>Un vehículo para tu carga</h3><p>Revisa la opción recomendada según los objetos que declaras y compara los vehículos disponibles en la solicitud.</p></article>
          </div>
        </section>
        <section className="priceWrap" id="precio" aria-labelledby="price-title"><div className="section priceSection"><div className="sectionHeader"><p className="eyebrow">Decide con los detalles a la vista</p><h2 id="price-title">¿Cuánto cuesta<br />un Muvv?</h2></div><div><p>El valor depende de la ruta, la carga, el vehículo y las opciones de tu traslado. Revisa el precio en la app antes de solicitar.</p><p className="priceNote">Comprueba las direcciones, los objetos y la ayuda seleccionada antes de continuar.</p><Link className="textAction" href="/descargar">Ver opciones de descarga <Arrow /></Link></div></div></section>
        <section className="section paymentTrust" aria-labelledby="payment-title">
          <div><p className="eyebrow">Pagos y devoluciones</p><h2 id="payment-title">{paymentContent.title}</h2><p>{paymentContent.body}</p></div>
          <div className="paymentTrustDetail"><h3>Muvv gestiona tu devolución</h3><p>Si corresponde devolver un pago con Webpay, gestionamos la anulación o el reembolso a través de Transbank. Su reflejo en tu cuenta o tarjeta depende del procesamiento y de tu banco.</p><Link className="textAction" href="/terminos#pagos-devoluciones">Ver condiciones de pago y devolución <Arrow /></Link><a className="paymentSupport" href="mailto:soporte@muvv.cl">¿Necesitas ayuda? soporte@muvv.cl</a></div>
        </section>
        <section className="audienceSection" aria-labelledby="audience-title">
          <div className="section">
            <div className="sectionHeader"><h2 id="audience-title">Hay un Muvv<br />para lo que viene.</h2><p>Elige cómo quieres moverte.</p></div>
            <div className="audienceGrid">
              {audiences.map((item) => <Link className="audienceItem" href={item.href} key={item.label} data-analytics-event="public.audience_click" data-analytics-entity-id={item.label.toLowerCase()}>
                <span className="audienceLabel">{item.label}</span><h3>{item.title}</h3><p>{item.body}</p><span className="audienceAction">{item.action}<Arrow /></span>
              </Link>)}
            </div>
          </div>
        </section>
        <section className="section driverInvite" aria-labelledby="driver-invite-title"><div><p className="eyebrow">Conductores · Lanzamiento en la RM</p><h2 id="driver-invite-title">Tu vehículo puede<br />ser parte de Muvv.</h2><p>Estamos preparando nuestro lanzamiento en la Región Metropolitana. Preinscríbete y te avisaremos cómo completar tu incorporación como conductor.</p></div><div className="driverInviteAction"><Link className="primaryAction lightSolid" href="/conductores#preinscripcion" data-analytics-event="public.cta_click" data-analytics-entity-id="driver_preregister">Quiero preinscribirme <Arrow /></Link><p>Sin costo. Sujeto a revisión de requisitos.<br />No garantiza disponibilidad de fletes.</p></div></section>
        <section className="section faqSection" id="preguntas" aria-labelledby="faq-title">
          <div className="sectionHeader"><h2 id="faq-title">Antes de<br />ponernos en marcha.</h2><p>Resolvamos las primeras dudas.</p></div>
          <div className="faqList">{questions.map((question) => <details key={question.title}><summary>{question.title}<span className="faqPlus" aria-hidden="true" /></summary><p>{question.body}</p></details>)}</div>
        </section>
        <section className="ctaWrap"><div className="ctaBand"><div><h2>Pide un flete.<br />Que sea Muvv.</h2><p>Descarga Muvv y prepara tu próximo traslado desde la app.</p></div><div className="ctaActions"><a className="primaryAction lightSolid" href="/descargar" data-analytics-event="public.cta_click" data-analytics-entity-id="bottom_download">{downloadLabel} <Arrow /></a><a className="secondaryAction light" href="/como-funciona" data-analytics-event="public.cta_click" data-analytics-entity-id="bottom_guide">Ver el paso a paso</a></div></div></section>
      </main>
      <SiteFooter />
    </>
  );
}
