import { appBaseUrl } from '../site-shell';
import { ProfilePage } from '../profile-pages';

export default function DriversPage() {
  return (
    <ProfilePage
      eyebrow="Conductores"
      title="Postula con documentos revisados y una operacion ordenada"
      lead="Los conductores registran datos, vehiculo y documentos para ser evaluados antes de operar dentro de FleteApp."
      imageClass="driversHero"
      primaryAction="Postular"
      primaryHref={`${appBaseUrl}/#/auth/register`}
      sections={[
        {
          title: 'Registro',
          body: 'Crea una cuenta de conductor y completa los datos requeridos para iniciar el proceso.',
        },
        {
          title: 'Documentos',
          body: 'Licencia, permiso de circulacion, revision tecnica y SOAP se revisan de forma privada.',
        },
        {
          title: 'Operacion',
          body: 'Una vez aprobado, el conductor puede revisar oportunidades y gestionar servicios desde la app.',
        },
      ]}
      highlights={[
        'Perfil de conductor',
        'Vehiculo registrado',
        'Documentos privados',
        'Aprobacion antes de operar',
      ]}
    />
  );
}
