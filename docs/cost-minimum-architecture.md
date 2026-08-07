# Muvv: arquitectura de costo minimo

Objetivo: mantener costo mensual en `0 USD` o lo mas cercano posible mientras no haya ingresos.

## Modo recomendado

| Parte | Servicio | Costo esperado | Comentario |
| --- | --- | --- | --- |
| Base de datos | Supabase Free | 0 USD | Suficiente para desarrollo/piloto chico. |
| Backend | Render Free | 0 USD | Se duerme con inactividad; aceptable en demo. |
| Fotos y documentos privados | Supabase Storage | 0 USD | Bucket privado; el backend Render controla el acceso. |
| Web publica | Vercel Hobby o Firebase Spark | 0 USD | Evita Cloud Build/Artifact Registry. |
| App web Flutter | Firebase Hosting Spark | 0 USD | Solo hosting estatico. |
| Push | Firebase Cloud Messaging | 0 USD | No requiere Cloud Run. |
| Emails | Resend Free | 0 USD | Mantener volumen bajo. |
| Mapas | Google Maps con cuotas bajas o desactivado en dev | Variable | Principal riesgo de gasto si queda abierto. |

## Evitar por ahora

- Google Secret Manager.
- Cloud Run para desarrollo diario.
- Cloud Functions.
- Cloud Tasks.
- Artifact Registry acumulando imagenes.
- Deploy por cada cambio pequeno en GCP.
- Google Maps sin restricciones y cuotas.

## Flujo diario barato

1. Backend local para desarrollo.
2. Supabase Free para datos.
3. Web publica en local o Vercel/Firebase Hosting.
4. Deploy solo cuando haya una version estable.
5. Revisar costos semanalmente si hay billing activo.

## Cuando volver a GCP

Volver a GCP cuando exista al menos uno de estos hitos:

- Piloto con usuarios reales.
- Necesidad de uptime estable.
- Primeros ingresos.
- Necesidad de jobs/colas/observabilidad administrada.

Al volver:

- `min-instances=0`.
- `max-instances` bajo.
- limpieza de Artifact Registry activa.
- presupuestos y alertas.
- cuotas de Maps.
- Secret Manager solo para secretos necesarios y pocas versiones activas.
