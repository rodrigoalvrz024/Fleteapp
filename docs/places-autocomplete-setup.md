# Sugerencias de direcciones para Muvv

La app usa el endpoint privado del backend para buscar direcciones. La clave de Google no llega al telefono ni al navegador.

## Configuracion unica

1. Abre Google Cloud y selecciona el proyecto `muvv-dev`.
2. En **APIs y servicios > Biblioteca**, habilita **Places API (New)**.
3. Crea una clave nueva llamada `muvv-render-maps`.
4. En **Restricciones de API**, permite solamente:
   - Places API (New)
   - Geocoding API
   - Distance Matrix API, mientras el backend siga usando esa API para estimar distancia
5. No configures restricciones por app Android, sitio web o IP para esta clave. Render Free no ofrece una IP saliente fija. La proteccion es que la clave se guarda solo como variable privada en Render y el backend exige sesion autenticada y aplica limites por usuario.
6. En Render, abre el servicio `muvv-api` y agrega una variable de entorno:

   ```text
   GOOGLE_MAPS_KEY=tu_clave_nueva
   ```

7. Guarda los cambios y espera el redeploy automatico.

## Comportamiento y costo

- La app consulta despues de tres caracteres y espera 350 ms desde la ultima tecla.
- Se solicitan como maximo cinco resultados y se usa un token de sesion por busqueda.
- Solo se muestran direcciones de Chile y se prioriza el entorno de la ubicacion actual.
- Si la clave no esta configurada, el resto de la app funciona; simplemente no aparecen sugerencias.

No pegues la clave en GitHub, Firebase ni en el chat.
