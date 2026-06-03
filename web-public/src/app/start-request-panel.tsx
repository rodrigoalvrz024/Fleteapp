'use client';

import { FormEvent, useState } from 'react';

const appLoginUrl = 'https://fleteapp-8d8f7.web.app/#/auth/login';

export function StartRequestPanel() {
  const [origin, setOrigin] = useState('');
  const [destination, setDestination] = useState('');

  function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();

    const freightParams = new URLSearchParams();
    if (origin.trim()) freightParams.set('origin_address', origin.trim());
    if (destination.trim()) {
      freightParams.set('dest_address', destination.trim());
    }

    const nextPath = freightParams.toString()
      ? `/app/client/create-freight?${freightParams.toString()}`
      : '/app/client/create-freight';

    window.location.href = `${appLoginUrl}?next=${encodeURIComponent(nextPath)}`;
  }

  return (
    <form className="requestPanel" onSubmit={handleSubmit}>
      <div className="panelHeader">
        <p className="panelKicker">Solicita un flete</p>
        <span>Completa ruta y continúa en la app.</span>
      </div>
      <label>
        <span>Origen</span>
        <input
          value={origin}
          onChange={(event) => setOrigin(event.target.value)}
          placeholder="Dirección de retiro"
          autoComplete="street-address"
        />
      </label>
      <label>
        <span>Destino</span>
        <input
          value={destination}
          onChange={(event) => setDestination(event.target.value)}
          placeholder="Dirección de entrega"
          autoComplete="street-address"
        />
      </label>
      <button type="submit">Continuar</button>
      <div className="panelFooter">
        <span>¿Aún no tienes cuenta?</span>
        <a href="https://fleteapp-8d8f7.web.app/#/auth/register">
          Crear cuenta
        </a>
      </div>
    </form>
  );
}
