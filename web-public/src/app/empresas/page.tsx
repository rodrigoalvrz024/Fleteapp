import { appBaseUrl } from '../site-shell';
import { ProfilePage } from '../profile-pages';

export default function CompaniesPage() {
  return (
    <ProfilePage
      eyebrow="Equipos"
      title="Control operativo para administrar solicitudes y conductores"
      lead="El panel interno separa tareas de soporte, aprobacion documental, monitoreo y trazabilidad historica de la web publica."
      imageClass="teamsHero"
      primaryAction="Ingresar al panel"
      primaryHref={`${appBaseUrl}/#/auth/login`}
      sections={[
        {
          title: 'Monitoreo',
          body: 'Revisa solicitudes, conductores, alertas y actividad reciente desde un entorno autenticado.',
        },
        {
          title: 'Aprobaciones',
          body: 'Gestiona documentos y estados de conductores con una separacion clara entre web publica y operacion interna.',
        },
        {
          title: 'Datos',
          body: 'Mantiene historial, eventos y registros para analisis futuro sin exponerlos en el sitio publico.',
        },
      ]}
      highlights={[
        'Panel interno',
        'Roles separados',
        'Historial auditable',
        'Alertas operacionales',
      ]}
    />
  );
}
