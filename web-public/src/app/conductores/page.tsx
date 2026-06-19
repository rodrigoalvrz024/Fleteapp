import { appBaseUrl } from '../site-shell';
import { ProfilePage } from '../profile-pages';
import { pageMetadata } from '../seo';

export const metadata = pageMetadata({
  title: 'Trabajar como conductor de fletes',
  description:
    'Postula como conductor, registra tu vehiculo, valida documentos y revisa fletes disponibles con ruta, carga y pago antes de aceptar.',
  path: '/conductores',
  keywords: ['trabajo conductor fletes', 'conductor con camioneta', 'postular conductor'],
});

export default function DriversPage() {
  return (
    <ProfilePage
      eyebrow="Conductores"
      title="Conduce fletes con informacion clara antes de aceptar."
      lead="Postula con tu vehiculo, valida tus documentos y revisa solicitudes disponibles desde la app."
      imageClass="driversHero"
      primaryAction="Postular"
      primaryHref={`${appBaseUrl}/#/auth/register?role=driver`}
      sections={[
        {
          title: 'Registra tu perfil',
          body: 'Crea tu cuenta de conductor y agrega los datos necesarios para operar con trazabilidad.',
        },
        {
          title: 'Valida documentos',
          body: 'Licencia, permiso de circulacion, revision tecnica, SOAP y datos del vehiculo se revisan en privado.',
        },
        {
          title: 'Acepta servicios',
          body: 'Cuando tu perfil este aprobado, puedes revisar ruta, carga, pago estimado y requisitos antes de aceptar.',
        },
      ]}
      highlights={[
        'Precios antes de aceptar',
        'Rutas visibles',
        'Documentos privados',
        'Liquidaciones revisables',
      ]}
    />
  );
}
