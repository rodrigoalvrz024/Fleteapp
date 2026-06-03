import { appBaseUrl } from '../site-shell';
import { ProfilePage } from '../profile-pages';

export default function ClientsPage() {
  return (
    <ProfilePage
      eyebrow="Clientes"
      title="Mueve carga urbana con informacion clara antes de confirmar"
      lead="FleteApp orienta a clientes que necesitan coordinar traslados urbanos con conductores revisados, precios visibles y soporte trazable."
      imageClass="clientsHero"
      primaryAction="Crear cuenta"
      primaryHref={`${appBaseUrl}/#/auth/register`}
      sections={[
        {
          title: 'Antes del traslado',
          body: 'Conoce que datos se revisan antes de coordinar un servicio y cuando conviene crear una cuenta.',
        },
        {
          title: 'Durante el servicio',
          body: 'Mantente informado sobre el avance del servicio desde el entorno privado cuando ya estes registrado.',
        },
        {
          title: 'Despues del viaje',
          body: 'Conserva respaldo de cada servicio para soporte, consultas y futuras decisiones.',
        },
      ]}
      highlights={[
        'Cuenta privada',
        'Precios visibles',
        'Estados por servicio',
        'Historial del cliente',
      ]}
    />
  );
}
