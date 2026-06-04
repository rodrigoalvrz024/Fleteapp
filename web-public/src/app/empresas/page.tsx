import { appBaseUrl } from '../site-shell';
import { ProfilePage } from '../profile-pages';

export default function CompaniesPage() {
  return (
    <ProfilePage
      eyebrow="Negocios"
      title="Entregas urbanas con respaldo para tu operacion"
      lead="Coordina traslados para compras, inventario y entregas locales conservando informacion clara de cada servicio."
      imageClass="teamsHero"
      primaryAction="Crear cuenta"
      primaryHref={`${appBaseUrl}/#/auth/register`}
      sections={[
        {
          title: 'Coordina entregas',
          body: 'Prepara servicios urbanos con ruta, carga, horario y ayudantes cuando sean necesarios.',
        },
        {
          title: 'Conserva historial',
          body: 'Consulta solicitudes anteriores y mantén respaldo de precios, rutas y estados.',
        },
        {
          title: 'Opera con claridad',
          body: 'Centraliza la informacion de cada traslado para reducir coordinaciones informales y llamadas.',
        },
      ]}
      highlights={[
        'Servicios programados',
        'Precios visibles',
        'Historial por traslado',
        'Soporte trazable',
      ]}
    />
  );
}
