'use client';

import Link from 'next/link';
import { FormEvent, useEffect, useRef, useState } from 'react';

const endpoint = process.env.NEXT_PUBLIC_PREREGISTRATION_API_URL?.replace(/\/$/, '');
const preview = process.env.NEXT_PUBLIC_PREREGISTRATION_PREVIEW === 'true';

export function PreregistrationForm() {
  const [state, setState] = useState<'idle' | 'sending' | 'success' | 'error'>('idle');
  const [error, setError] = useState('');
  const resultRef = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (state === 'success') {
      resultRef.current?.scrollIntoView({ block: 'center' });
      resultRef.current?.focus({ preventScroll: true });
    }
  }, [state]);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (state === 'sending' || !endpoint) return;
    const data = new FormData(event.currentTarget);
    setState('sending');
    setError('');
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 20000);
    try {
      const response = await fetch(`${endpoint}/public/driver-preregistrations`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' }, signal: controller.signal,
        body: JSON.stringify({
          full_name: data.get('full_name'), email: data.get('email'), phone: data.get('phone'),
          commune: data.get('commune'), vehicle_type: data.get('vehicle_type'),
          availability: data.get('availability') || null, contact_consent: data.get('contact_consent') === 'on',
          marketing_consent: data.get('marketing_consent') === 'on',
          consent_version: 'preregistro-2026-09-v1', website: data.get('website') || '',
        }),
      });
      if (!response.ok) {
        throw new Error(response.status === 429 ? 'Has realizado varios intentos. Espera un momento antes de volver a intentar.'
          : response.status === 422 ? 'Revisa tus datos. El celular debe ser chileno y el correo debe tener un formato válido.'
          : 'No pudimos confirmar tu preinscripción. Intenta nuevamente o escríbenos a soporte@muvv.cl.');
      }
      const result = await response.json();
      if (result.status !== 'received') throw new Error('No pudimos confirmar tu preinscripción. Intenta nuevamente.');
      setState('success');
    } catch (failure) {
      setError(failure instanceof Error && failure.name !== 'AbortError' && failure.name !== 'TypeError'
        ? failure.message : 'No pudimos confirmar la recepción. Revisa tu conexión y vuelve a intentar; no duplicaremos tu correo.');
      setState('error');
    } finally { clearTimeout(timeout); }
  }

  return <div className="preregCard" id="preinscripcion">
    {preview && <p className="preregPreview">Vista de prueba local. Usa datos ficticios; esta inscripción no llega al lanzamiento.</p>}
    {state === 'success' ? <div className="preregSuccess" tabIndex={-1} ref={resultRef} role="status">
      <span className="preregCheck" aria-hidden="true">✓</span>
      <h2>Recibimos tu preinscripción.</h2>
      <p>Te contactaremos con los próximos pasos para el lanzamiento. Aún no necesitas enviar documentos.</p>
      <p className="formHint">Si ya habías enviado este correo, conservamos tu registro anterior. Para corregir datos, escribe a <a href="mailto:soporte@muvv.cl">soporte@muvv.cl</a>.</p>
      <Link className="textAction" href="/como-funciona#conductores">Conoce cómo funciona Muvv →</Link>
    </div> : <form onSubmit={submit} aria-labelledby="form-title">
      <p className="eyebrow">Primer paso · Sin documentos</p>
      <h2 id="form-title">Preinscríbete aquí.</h2>
      <p className="formHint">Todos los campos son obligatorios, salvo donde indicamos opcional.</p>
      <fieldset disabled={state === 'sending'} className="preregFields">
        <legend className="srOnly">Datos para la preinscripción</legend>
        <label className="formField">Nombre y apellido<input name="full_name" autoComplete="name" required minLength={3} maxLength={100} placeholder="Tu nombre completo" /></label>
        <div className="formRow">
          <label className="formField">Celular<input type="tel" name="phone" autoComplete="tel" inputMode="tel" required maxLength={24} placeholder="+56 9 1234 5678" aria-describedby="phone-hint" /><span id="phone-hint" className="formHint">Número móvil de Chile.</span></label>
          <label className="formField">Correo electrónico<input type="email" name="email" autoComplete="email" required maxLength={254} placeholder="nombre@correo.cl" /></label>
        </div>
        <div className="formRow">
          <label className="formField">Comuna base en la RM<input name="commune" autoComplete="address-level3" required minLength={2} maxLength={80} placeholder="Ej. Puente Alto" /></label>
          <label className="formField">Tipo de vehículo<select name="vehicle_type" defaultValue="" required><option value="" disabled>Selecciona tu vehículo</option><option value="camioneta">Camioneta</option><option value="furgon">Furgón</option><option value="camion">Camión</option><option value="otro">Otro / por confirmar</option></select></label>
        </div>
        <label className="formField">Disponibilidad <span className="optionalLabel">(opcional)</span><select name="availability" defaultValue=""><option value="">Prefiero indicarla después</option><option value="semana">Días de semana</option><option value="fin_semana">Fines de semana</option><option value="ambas">Ambas</option></select></label>
        <div className="preregTrap" aria-hidden="true"><label>Sitio web<input name="website" tabIndex={-1} autoComplete="off" /></label></div>
        <label className="formConsent"><input type="checkbox" name="contact_consent" required /><span>Autorizo a Muvv a usar estos datos para gestionar mi preinscripción y contactarme por correo, llamada o WhatsApp sobre el lanzamiento. He leído el <a href="#datos-preinscripcion">aviso de privacidad de la preinscripción</a>.</span></label>
        <label className="formConsent"><input type="checkbox" name="marketing_consent" /><span>También quiero recibir novedades y promociones de Muvv. <span className="optionalLabel">(Opcional)</span></span></label>
        {!endpoint && <p className="formNotice" role="status">Pronto habilitaremos el envío. Por ahora puedes contactarnos en <a href="mailto:soporte@muvv.cl">soporte@muvv.cl</a>.</p>}
        {error && <p className="formError" role="alert">{error}</p>}
        <button className="primaryAction dark preregSubmit" disabled={!endpoint || state === 'sending'} type="submit">{state === 'sending' ? 'Enviando…' : 'Quiero preinscribirme'}<span aria-hidden="true">→</span></button>
      </fieldset>
      <p className="formHint formFootnote">Sin costo. No crea una cuenta de conductor ni garantiza aprobación o disponibilidad de fletes.</p>
    </form>}
  </div>;
}
