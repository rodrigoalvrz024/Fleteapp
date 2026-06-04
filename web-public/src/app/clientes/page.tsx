import { appBaseUrl } from '../site-shell';
import { ProfilePage } from '../profile-pages';

export default function ClientsPage() {
  return (
    <ProfilePage
      eyebrow="Clientes"
      title="Tu carga llega mejor cuando el traslado se prepara bien"
      lead="Coordina muebles, compras grandes, mudanzas pequenas y otros traslados urbanos con informacion clara antes de confirmar."
      imageClass="clientsHero"
      primaryAction="Crear cuenta"
      primaryHref={`${appBaseUrl}/#/auth/register`}
      sections={[
        {
          title: 'Prepara lo necesario',
          body: 'Describe la carga, indica la ruta, elige el horario y agrega ayudantes cuando los necesites.',
        },
        {
          title: 'Confirma con claridad',
          body: 'Revisa el precio estimado y los datos del servicio antes de crear la solicitud.',
        },
        {
          title: 'Conserva el respaldo',
          body: 'Consulta el estado y el historial de cada traslado para soporte y futuras referencias.',
        },
      ]}
      highlights={[
        'Conductores revisados',
        'Precios visibles',
        'Ayudantes opcionales',
        'Historial del cliente',
      ]}
    />
  );
}
