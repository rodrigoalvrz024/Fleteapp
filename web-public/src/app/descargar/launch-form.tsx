'use client';

import { FormEvent, useEffect, useRef, useState } from 'react';
import { downloadStores } from '../download-links';
import { StoreIcon } from '../store-badges';

const endpoint = process.env.NEXT_PUBLIC_PREREGISTRATION_API_URL?.replace(/\/$/, '');
const preview = process.env.NEXT_PUBLIC_PREREGISTRATION_PREVIEW === 'true';


export function LaunchAvailability() {
  const [platform, setPlatform] = useState('ambas');
  const [state, setState] = useState<'idle' | 'sending' | 'success' | 'error'>('idle');
  const [error, setError] = useState('');
  useEffect(() => {
    const requested = new URLSearchParams(window.location.search).get('plataforma');
    if (requested === 'android' || requested === 'ios') setPlatform(requested);
  }, []);
  const nameRef = useRef<HTMLInputElement>(null);
  const resultRef = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (state === 'success') { resultRef.current?.scrollIntoView({ block: 'center' }); resultRef.current?.focus({ preventScroll: true }); }
  }, [state]);
  const pending = downloadStores.some(store => !store.href);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!endpoint || state === 'sending') return;
    const data = new FormData(event.currentTarget);
    const emailConsent = data.get('email_consent') === 'on';
    const whatsappConsent = data.get('whatsapp_consent') === 'on';
    if (!emailConsent && !whatsappConsent) { setError('Elige al menos un canal para recibir el aviso.'); setState('error'); return; }
    setError(''); setState('sending');
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 20000);
    try {
      const response = await fetch(`${endpoint}/public/launch-signups`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' }, signal: controller.signal,
        body: JSON.stringify({ full_name: data.get('full_name'), email: data.get('email'), phone: data.get('phone'),
          platform, email_consent: emailConsent, whatsapp_consent: whatsappConsent,
          consent_version: 'lanzamiento-2026-09-v1', website: data.get('website') || '' }),
      });
      if (!response.ok) throw new Error(response.status === 429 ? 'Has realizado varios intentos. Vuelve a intentar más tarde.'
        : response.status === 422 ? 'Revisa el correo, el celular chileno y los canales seleccionados.'
        : 'No pudimos guardar tu solicitud. Intenta nuevamente o escribe a soporte@muvv.cl.');
      if ((await response.json()).status !== 'received') throw new Error('No pudimos confirmar tu solicitud. Intenta nuevamente.');
      setState('success');
    } catch (failure) {
      setError(failure instanceof Error && !['AbortError', 'TypeError'].includes(failure.name)
        ? failure.message : 'No pudimos confirmar la recepción. Revisa tu conexión y vuelve a intentar.');
      setState('error');
    } finally { clearTimeout(timeout); }
  }

  return <>
    <div className="storeOptions">
      {downloadStores.map(store => <article className="storeOption" key={store.id}>
        <p>{store.platform}</p><h2>{store.name}</h2>
        {store.href ? <a className="storeBadge" href={store.href} data-analytics-event="public.download_click" data-analytics-entity-id={store.id}><StoreIcon platform={store.id} /><span><small>Descargar en</small>{store.name}</span></a>
          : <><a className="storeBadge" href="#aviso-lanzamiento" onClick={() => { setPlatform(store.id); nameRef.current?.focus({ preventScroll: true }); }}><StoreIcon platform={store.id} /><span><small>Próximamente · Avísame</small>{store.name}</span></a><p>Déjanos tus datos para avisarte cuando puedas descargarla.</p></>}
      </article>)}
    </div>
    {pending && <div className="launchSignupLayout" id="aviso-lanzamiento">
      <div className="launchSignupCopy"><p className="eyebrow">Muvv está por llegar</p><h2>Tu próximo flete<br />empieza aquí.</h2><p>Te avisaremos cuando la app esté disponible para tu celular. Nuestro lanzamiento será en la Región Metropolitana.</p><p className="formHint">Sin costo y sin crear una cuenta. Tú eliges cómo recibir el aviso.</p><a className="textAction" href="/conductores#preinscripcion">¿Quieres conducir? Preinscríbete aquí →</a></div>
      <div className="preregCard">
        {preview && <p className="preregPreview">Vista de prueba local. Usa datos ficticios; no se enviarán avisos.</p>}
        {state === 'success' ? <div className="preregSuccess" ref={resultRef} tabIndex={-1} role="status"><span className="preregCheck" aria-hidden="true">✓</span><h2>Recibimos tu solicitud.</h2><p>Te avisaremos por los canales que autorizaste cuando Muvv esté disponible.</p><p className="formHint">Si ya habías inscrito este correo, conservamos tu registro anterior. Para modificar tus datos o retirar tu autorización, escribe a <a href="mailto:soporte@muvv.cl">soporte@muvv.cl</a>.</p></div>
          : <form onSubmit={submit} aria-labelledby="launch-form-title"><h2 id="launch-form-title">Avísame cuando llegue.</h2><p className="formHint">Completa tus datos y elige cómo prefieres recibir el aviso.</p>
            <fieldset className="preregFields" disabled={state === 'sending'}><legend className="srOnly">Datos para el aviso de lanzamiento</legend>
              <label className="formField">Nombre y apellido<input ref={nameRef} name="full_name" autoComplete="name" required minLength={3} maxLength={100} placeholder="Tu nombre completo" /></label>
              <label className="formField">Correo electrónico<input type="email" name="email" autoComplete="email" required maxLength={254} placeholder="nombre@correo.cl" /></label>
              <label className="formField">Celular<input type="tel" name="phone" autoComplete="tel" required maxLength={24} placeholder="+56 9 1234 5678" /><span className="formHint">Número móvil de Chile.</span></label>
              <label className="formField">Mi celular<select name="platform" value={platform} onChange={event => setPlatform(event.target.value)}><option value="android">Android · Google Play</option><option value="ios">iPhone · App Store</option><option value="ambas">Ambas plataformas</option></select></label>
              <div className="preregTrap" aria-hidden="true"><label>Sitio web<input name="website" tabIndex={-1} autoComplete="off" /></label></div>
              <p className="formHint">Autorizo a Muvv a avisarme del lanzamiento por (elige al menos uno):</p>
              <label className="formConsent"><input type="checkbox" name="email_consent" /><span>Correo electrónico.</span></label>
              <label className="formConsent"><input type="checkbox" name="whatsapp_consent" /><span>WhatsApp al número indicado.</span></label>
              <p className="formHint">Usaremos tus datos solo para gestionar este aviso. Puedes retirar tu autorización en soporte@muvv.cl. <a href="#privacidad-aviso">Cómo cuidamos tus datos</a>.</p>
              {!endpoint && <p className="formNotice">El registro aún no está habilitado. Escríbenos a soporte@muvv.cl.</p>}
              {error && <p className="formError" role="alert">{error}</p>}
              <button type="submit" className="primaryAction dark preregSubmit" disabled={!endpoint || state === 'sending'}>{state === 'sending' ? 'Guardando…' : 'Quiero recibir el aviso'}<span aria-hidden="true">→</span></button>
            </fieldset>
          </form>}
      </div>
    </div>}
    {pending && <section className="launchPrivacy" id="privacidad-aviso" aria-labelledby="launch-privacy-title"><h2 id="launch-privacy-title">Tus datos, para avisarte.</h2><p>SOLUCIONES INTEGRALES RA SpA (RUT 78.368.247-8), Santa Victoria 492, departamento 1705, Santiago, usará tu nombre, correo, celular, plataforma y autorizaciones para gestionar la lista y comunicar la disponibilidad de Muvv. El registro se guarda en nuestra base de datos y se copia en una planilla privada de Google Sheets accesible al equipo autorizado. No crea una cuenta en la app ni autoriza promociones adicionales.</p><p>Puedes solicitar acceso, corrección o eliminación de tus datos y retirar tu autorización escribiendo a <a href="mailto:soporte@muvv.cl">soporte@muvv.cl</a>. Consulta la <a href="/privacidad">política de privacidad</a>.</p></section>}
  </>;
}
