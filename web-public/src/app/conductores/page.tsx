import Image from 'next/image';
import Link from 'next/link';
import { SiteFooter, SiteNav } from '../site-shell';
import { pageMetadata } from '../seo';
import { PreregistrationForm } from './preregistration-form';

export const metadata = pageMetadata({
  title: 'Preinscripción de conductores en la Región Metropolitana',
  description: 'Sé parte del lanzamiento de Muvv. Preinscríbete con tu vehículo para recibir información sobre la incorporación de conductores en la Región Metropolitana.',
  path: '/conductores', keywords: ['preinscripción conductores', 'conductor fletes RM'],
});

export default function DriversPage() {
  return <><SiteNav /><main id="contenido" tabIndex={-1}>
    <section className="driverLaunchHero brandBackdrop" aria-labelledby="driver-title">
      <div className="driverLaunchLayout section">
        <div className="driverLaunchCopy">
          <p className="eyebrow">Conductores · Lanzamiento en la RM</p>
          <h1 id="driver-title">Tu vehículo.<br />El próximo<br /><span>movimiento.</span></h1>
          <p className="driverLaunchLead">Sé parte del lanzamiento de Muvv.</p>
          <p>Estamos preparando nuestra red de conductores en toda la Región Metropolitana. Déjanos tus datos y te avisaremos cómo completar tu incorporación.</p>
          <a className="textAction driverJump" href="#preinscripcion">Ir a la preinscripción ↓</a>
          <figure className="driverLaunchPhoto"><Image src="/muvv-moving.webp" alt="Imagen de campaña Muvv: conductor junto a un furgón con carga." width={941} height={1024} sizes="(max-width: 760px) 90vw, 460px" /><figcaption>Fletes urbanos. Personas que los hacen posibles.</figcaption></figure>
        </div>
        <PreregistrationForm />
      </div>
    </section>
    <section className="section driverBenefits" aria-labelledby="driver-benefits-title">
      <div className="sectionHeader"><p className="eyebrow">Conoce lo que viene</p><h2 id="driver-benefits-title">Información para decidir<br />antes de aceptar.</h2></div>
      <div className="trustList"><article><h3>La ruta a la vista</h3><p>Consulta el origen y el destino de las solicitudes desde la app.</p></article><article><h3>Sabes qué vas a mover</h3><p>Revisa los objetos y la ayuda indicada para preparar tu vehículo.</p></article><article><h3>Revisa el pago</h3><p>Conoce el pago estimado del servicio antes de decidir si lo aceptas.</p></article></div>
    </section>
    <section className="section driverNext" aria-labelledby="driver-next-title"><div className="sectionHeader"><h2 id="driver-next-title">Hoy te preinscribes.<br />Después, te acompañamos.</h2></div>
      <ol className="quickSteps"><li><span>01</span><h3>Déjanos tus datos</h3><p>Cuéntanos desde qué comuna te moverías y qué vehículo tienes.</p></li><li><span>02</span><h3>Recibe los próximos pasos</h3><p>Te contactaremos sobre el lanzamiento y el proceso de incorporación.</p></li><li><span>03</span><h3>Completa tu registro</h3><p>Cuando se habilite la incorporación, registra y valida tus documentos en la app. La preinscripción no reemplaza esa revisión.</p></li></ol>
    </section>
    <section className="section faqSection" aria-labelledby="driver-faq-title"><div className="sectionHeader"><h2 id="driver-faq-title">Antes de sumarte.</h2></div><div className="faqList">
      <details><summary>¿Dónde comenzará Muvv?<span className="faqPlus" aria-hidden="true" /></summary><p>La primera etapa contempla toda la Región Metropolitana. La asignación de servicios dependerá de la disponibilidad y la demanda.</p></details>
      <details><summary>¿Qué vehículo puedo preinscribir?<span className="faqPlus" aria-hidden="true" /></summary><p>Puedes indicar camioneta, furgón o camión. Si tienes otro vehículo, selecciona “Otro / por confirmar”. La compatibilidad se revisará durante la incorporación.</p></details>
      <details><summary>¿Tengo que enviar documentos ahora?<span className="faqPlus" aria-hidden="true" /></summary><p>No. En esta etapa solo pedimos datos de contacto, comuna y tipo de vehículo. La licencia, documentación del vehículo y demás requisitos se revisan después, dentro de la app.</p></details>
      <details><summary>¿Preinscribirme tiene costo o garantiza trabajo?<span className="faqPlus" aria-hidden="true" /></summary><p>No tiene costo y no garantiza aprobación, ingresos ni una cantidad de fletes. Es una forma de recibir los próximos pasos del lanzamiento.</p></details>
    </div></section>
    <section className="section preregPrivacy" id="datos-preinscripcion" aria-labelledby="prereg-privacy-title"><h2 id="prereg-privacy-title">Tus datos, para este primer paso.</h2>
      <p>SOLUCIONES INTEGRALES RA SpA, RUT 78.368.247-8, con domicilio en Santa Victoria #492, departamento 1705, Santiago, utiliza los datos que ingreses para gestionar tu interés y contactarte sobre la incorporación a Muvv.</p>
      <p>Los registros se guardan en la base de datos de Muvv. La gestión interna puede incluir una copia en una planilla privada de Google Sheets, con acceso limitado al equipo autorizado. No son un directorio público. Las promociones solo se enviarán si seleccionas la autorización opcional.</p>
      <p>Puedes pedir la corrección o eliminación de tu preinscripción y retirar tu autorización escribiendo a <a href="mailto:soporte@muvv.cl">soporte@muvv.cl</a>. Consulta también nuestra <Link href="/privacidad">política de privacidad</Link>. Versión del aviso: preregistro-2026-09-v1.</p>
    </section>
  </main><SiteFooter /></>;
}
