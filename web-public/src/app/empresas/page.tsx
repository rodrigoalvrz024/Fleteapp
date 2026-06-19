import { appBaseUrl } from '../site-shell';
import { ProfilePage } from '../profile-pages';
import { pageMetadata } from '../seo';

export const metadata = pageMetadata({
  title: 'Fletes urbanos para empresas',
  description:
    'Coordina traslados urbanos, inventario y entregas locales con historial operativo, evidencia por servicio y control para soporte.',
  path: '/empresas',
  keywords: ['fletes empresas', 'logistica urbana', 'traslados para negocios'],
});

export default function CompaniesPage() {
  return (
    <ProfilePage
      eyebrow="Empresas"
      title="Traslados urbanos con historial para tu operacion."
      lead="Coordina carga local, compras, inventario y entregas con registros utiles para control y soporte."
      imageClass="teamsHero"
      primaryAction="Crear cuenta"
      primaryHref={`${appBaseUrl}/#/auth/register`}
      sections={[
        {
          title: 'Centraliza solicitudes',
          body: 'Prepara servicios con ruta, carga, horario y ayudantes desde una cuenta operativa.',
        },
        {
          title: 'Mantiene respaldo',
          body: 'Cada flete conserva precio, estado, conductor asignado y evidencia cuando corresponde.',
        },
        {
          title: 'Reduce coordinaciones',
          body: 'Menos mensajes sueltos y mas informacion disponible para seguimiento, soporte y analisis.',
        },
      ]}
      highlights={[
        'Servicios programados',
        'Historial operativo',
        'Historial por traslado',
        'Control para admin',
      ]}
    />
  );
}
