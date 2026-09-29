import { ProfilePage } from '../profile-pages';
import { pageMetadata } from '../seo';

export const metadata = pageMetadata({
  title: 'Fletes urbanos para empresas',
  description:
    'Coordina traslados urbanos de productos y compras con historial y evidencia por servicio desde la app Muvv.',
  path: '/empresas',
  keywords: ['fletes empresas', 'logistica urbana', 'traslados para negocios'],
});

export default function CompaniesPage() {
  return (
    <ProfilePage
      eyebrow="Empresas"
      title="Traslados urbanos con historial para tu operación."
      lead="Coordina traslados de productos, compras y entregas con registros útiles para consultar cada servicio."
      imageClass="teamsHero"
      guideHref="/como-funciona#clientes"
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
          body: 'Menos mensajes sueltos y más información disponible para seguimiento, soporte y análisis.',
        },
      ]}
      highlights={[
        'Servicios programados',
        'Historial operativo',
        'Fotos por servicio',
        'Precio antes de solicitar',
      ]}
    />
  );
}
