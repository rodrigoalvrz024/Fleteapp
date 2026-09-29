import { paymentContent } from './payment-content';

export const termsSections = [
  {
    title: 'Quién opera Muvv',
    body: 'Muvv es operada por SOLUCIONES INTEGRALES RA SpA, RUT 78.368.247-8, con domicilio en Santa Victoria 492, departamento 1705, Santiago. El canal de contacto para consultas, pagos y devoluciones es soporte@muvv.cl.',
  },
  {
    title: 'Uso de la plataforma',
    body: 'Muvv conecta clientes que solicitan fletes con conductores independientes. La plataforma permite crear solicitudes, aceptar servicios, coordinar traslados y revisar el estado de cada flete.',
  },
  {
    title: 'Cuentas de usuario',
    body: 'Cada persona debe entregar informacion verdadera, mantener segura su contrasena y usar una cuenta propia. Muvv puede suspender cuentas cuando exista fraude, uso indebido o riesgo para otros usuarios.',
  },
  {
    title: 'Conductores y documentos',
    body: 'Los conductores deben mantener licencia vigente, permiso de circulacion, revision tecnica, SOAP y datos del vehiculo actualizados. La aprobacion puede ser rechazada o suspendida si la informacion no es verificable.',
  },
  {
    title: 'Servicios y pagos',
    body: paymentContent.faqBody + ' Los valores pueden variar según la ruta, la carga, el vehículo y las opciones seleccionadas. Las comisiones y los pagos al conductor se informan en la app según corresponda.',
  },
  {
    id: 'pagos-devoluciones',
    title: 'Cancelaciones y devoluciones durante el piloto',
    body: 'Si no se consigue conductor o el servicio no se realiza por una cancelación atribuible al conductor o a Muvv, se devuelve la totalidad del importe cobrado. Durante el piloto, si el cliente cancela antes de comenzar el traslado, la cancelación es gratuita y se devuelve la totalidad del importe cobrado, sin cargo por desplazamiento del conductor. Si el traslado ya comenzó, contacta a soporte para coordinar la situación y la entrega de la carga.',
  },
  {
    title: 'Gestión y plazos de devolución',
    body: paymentContent.refundBody + ' Solicitar la devolución no significa que el dinero ya esté disponible. No se garantiza un abono inmediato ni un plazo bancario único. Si la operación es rechazada o presenta un error, Muvv gestionará la incidencia y dará seguimiento a la devolución que corresponda. Transbank procesa la operación de pago; la gestión del servicio y la atención de solicitudes corresponden a Muvv.',
  },
  {
    title: 'Seguridad y responsabilidad',
    body: 'Usuarios y conductores deben actuar de buena fe, cuidar la carga y respetar la normativa aplicable. Muvv puede investigar incidentes y limitar el acceso para proteger la operacion.',
  },
  {
    title: 'Uso del chat de fletes',
    body: 'El chat se usa para coordinar el servicio dentro de Muvv. No debe utilizarse para ofrecer o acordar servicios por fuera de la plataforma. Cuando exista una necesidad concreta de seguridad, soporte, fraude o cumplimiento, personal autorizado puede revisar una conversacion de forma limitada, de solo lectura y con registro de la consulta.',
  },
];

export const privacySections = [
  {
    title: 'Datos que tratamos',
    body: 'Podemos tratar datos de identificacion, contacto, ubicacion operativa, solicitudes de flete, pagos, calificaciones y documentos necesarios para validar conductores y vehiculos.',
  },
  {
    title: 'Finalidades',
    body: 'Usamos los datos para crear cuentas, autenticar usuarios, coordinar fletes, calcular rutas y precios, validar conductores, prevenir fraude, entregar soporte y cumplir obligaciones legales. Esto puede incluir revisar de forma limitada mensajes y fotos del chat de un flete cuando sea necesario para investigar fraude, incidentes, incumplimientos o intentos de coordinar servicios fuera de Muvv.',
  },
  {
    title: 'Acceso limitado a conversaciones',
    body: 'Las conversaciones no son publicas ni se usan para publicidad. El acceso excepcional se limita a personal autorizado, es de solo lectura, requiere un motivo y queda registrado. Las fotos compartidas se almacenan de manera privada y se consultan mediante enlaces temporales.',
  },
  {
    title: 'Documentos de conductor',
    body: 'La licencia, permiso de circulacion, revision tecnica y SOAP se usan para revisar la aptitud del conductor y del vehiculo. No pediremos reconocimiento facial ni verificacion biometrica en esta etapa.',
  },
  {
    title: 'Conservacion y seguridad',
    body: 'Guardamos la informacion mientras sea necesaria para operar la cuenta, cumplir obligaciones, resolver disputas o prevenir fraude. Aplicamos controles de acceso y almacenamiento seguro para reducir riesgos.',
  },
  {
    title: 'Derechos de las personas',
    body: 'Puedes solicitar acceso, rectificacion, eliminacion, bloqueo u oposicion cuando corresponda. Para ejercer derechos o pedir soporte, contacta al equipo de Muvv desde los canales oficiales.',
  },
];
