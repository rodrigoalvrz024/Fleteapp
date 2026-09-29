'use client';

import Image from 'next/image';
import { useId, useState } from 'react';

const steps = [
  { label: 'Ruta', title: 'El punto de partida y de llegada.', body: 'Indica dónde se retira tu carga y a dónde debe llegar. Revisa ambas direcciones antes de continuar.', image: '01-route', alt: 'Pantalla Ruta de Muvv con origen y destino de prueba.' },
  { label: 'Carga', title: 'Cuéntanos qué necesitas mover.', body: 'Elige el tipo de servicio y agrega tus objetos. Puedes completar la descripción, adjuntar fotos y elegir ayuda para cargar.', image: '02-cargo', alt: 'Pantalla Carga de Muvv para elegir servicio y describir los objetos.' },
  { label: 'Vehículo', title: 'El espacio que necesita tu carga.', body: 'Revisa el vehículo recomendado para los objetos declarados. Puedes comparar otras opciones antes de elegir el horario.', image: '03-vehicle', alt: 'Pantalla Vehículo con una recomendación de furgón y precio de demostración.' },
  { label: 'Horario', title: 'Ahora o cuando lo tengas planeado.', body: 'Elige si necesitas el flete ahora o prefieres programarlo. Revisa la fecha, la hora y las opciones seleccionadas.', image: '04-time', alt: 'Pantalla Tiempo de Muvv con opciones Ahora y Programar.' },
  { label: 'Revisión', title: 'Revisa los detalles antes de solicitar.', body: 'Comprueba ruta, carga, vehículo, horario y precio. Si algo cambia, vuelve al paso correspondiente antes de solicitar el flete.', image: '05-price', alt: 'Pantalla de revisión del flete con resumen y precio ficticio de demostración.' },
];

export function AppTour() {
  const [selected, setSelected] = useState(0);
  const panelId = useId();
  const step = steps[selected];

  return <div className="appTour">
    <div className="tourSteps" role="group" aria-label="Pantallas de la solicitud">
      {steps.map((item, index) => <button key={item.label} type="button" aria-pressed={selected === index}
        aria-controls={panelId} onClick={() => setSelected(index)}>
        <span aria-hidden="true">{index + 1}</span>{item.label}
      </button>)}
    </div>
    <div className="tourPanel" id={panelId}>
      <div className="tourCopy">
        <div aria-live="polite" aria-atomic="true"><p className="tourCount">Paso {selected + 1} de {steps.length}</p><h3>{step.title}</h3><p>{step.body}</p></div>
        <p className="tourDisclaimer">Esta es una guía visual. Las direcciones y los precios de las capturas son ejemplos, no una cotización. Tu solicitud se realiza dentro de la app.</p>
        <div className="tourControls"><button className="secondaryAction darkLine" type="button" disabled={selected === 0} onClick={() => setSelected(selected - 1)}>Anterior</button><button className="primaryAction dark" type="button" disabled={selected === steps.length - 1} onClick={() => setSelected(selected + 1)}>Siguiente paso</button></div>
        <a className="textAction" href={`/app-screens/${step.image}.webp`} target="_blank" rel="noopener noreferrer">Ampliar captura <span className="srOnly">(se abre en otra pestaña)</span></a>
      </div>
      <figure className="tourScreen">
        <div className="phoneFrame"><Image key={step.image} src={`/app-screens/${step.image}.webp`} alt={step.alt} width={786} height={1704} sizes="(max-width: 760px) 280px, 310px" /></div>
        <figcaption>Pantalla real de la app · Datos de demostración</figcaption>
      </figure>
    </div>
  </div>;
}
