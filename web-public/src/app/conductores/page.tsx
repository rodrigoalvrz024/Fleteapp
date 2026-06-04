import { appBaseUrl } from '../site-shell';
import { ProfilePage } from '../profile-pages';

export default function DriversPage() {
  return (
    <ProfilePage
      eyebrow="Conductores"
      title="Convierte tu vehiculo en oportunidades de trabajo"
      lead="Postula con tus documentos, conoce el valor de cada servicio y opera con un historial claro desde la app."
      imageClass="driversHero"
      primaryAction="Postular"
      primaryHref={`${appBaseUrl}/#/auth/register?role=driver`}
      sections={[
        {
          title: 'Postula',
          body: 'Crea tu cuenta de conductor y registra el vehiculo con el que quieres realizar fletes.',
        },
        {
          title: 'Verifica tus documentos',
          body: 'Licencia, permiso de circulacion, revision tecnica y SOAP se revisan de forma privada.',
        },
        {
          title: 'Revisa oportunidades',
          body: 'Una vez aprobado, consulta servicios disponibles, precios y detalles antes de aceptar.',
        },
      ]}
      highlights={[
        'Precios antes de aceptar',
        'Oportunidades disponibles',
        'Documentos privados',
        'Aprobacion antes de operar',
      ]}
    />
  );
}
