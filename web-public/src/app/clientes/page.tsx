import { appBaseUrl } from '../site-shell';
import { ProfilePage } from '../profile-pages';
import { pageMetadata } from '../seo';

export const metadata = pageMetadata({
  title: 'Pedir fletes para muebles, compras y carga urbana',
  description:
    'Solicita fletes urbanos con precio visible, ayudantes opcionales, seguimiento del servicio, fotos de respaldo y PIN de entrega.',
  path: '/clientes',
  keywords: ['pedir flete online', 'flete para muebles', 'flete para compras grandes'],
});

export default function ClientsPage() {
  return (
    <ProfilePage
      eyebrow="Clientes"
      title="Pide un flete para mover muebles, compras y carga urbana."
      lead="Crea una solicitud, revisa el precio y coordina el traslado con respaldo desde tu cuenta."
      imageClass="clientsHero"
      primaryAction="Crear cuenta"
      primaryHref={`${appBaseUrl}/#/auth/register`}
      sections={[
        {
          title: 'Define la ruta',
          body: 'Indica origen, destino, tipo de carga y horario para preparar el servicio con informacion suficiente.',
        },
        {
          title: 'Confirma con precio visible',
          body: 'El valor se informa antes de avanzar para que puedas decidir sin coordinaciones informales.',
        },
        {
          title: 'Recibe con respaldo',
          body: 'Fotos de retiro, fotos de entrega y PIN ayudan a cerrar el servicio con evidencia clara.',
        },
      ]}
      highlights={[
        'Precio antes de confirmar',
        'Pago protegido',
        'Ayudantes opcionales',
        'Historial por flete',
      ]}
    />
  );
}
