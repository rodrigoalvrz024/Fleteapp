'use client';

import { FormEvent, useState } from 'react';

const appLoginUrl = 'https://fleteapp-8d8f7.web.app/#/login';

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

    window.location.href =
      `${appLoginUrl}?next=${encodeURIComponent(nextPath)}`;
  }

  return (
    <form className="requestPanel" onSubmit={handleSubmit}>
      <p className="panelKicker">Solicita un flete</p>
      <label>
        <span>Origen</span>
        <input
          value={origin}
          onChange={(event) => setOrigin(event.target.value)}
          placeholder="Direccion de retiro"
          autoComplete="street-address"
        />
      </label>
      <label>
        <span>Destino</span>
        <input
          value={destination}
          onChange={(event) => setDestination(event.target.value)}
          placeholder="Direccion de entrega"
          autoComplete="street-address"
        />
      </label>
      <button type="submit">Continuar</button>
      <a href="https://fleteapp-8d8f7.web.app/#/register">Crear cuenta</a>
    </form>
  );
}
