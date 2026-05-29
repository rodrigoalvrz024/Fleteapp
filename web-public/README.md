# FleteApp Public Web

Sitio publico separado de la app Flutter.

## Objetivo

- Landing comercial y SEO.
- Entrada clara para clientes, conductores y administracion.
- Terminos, privacidad y contenido publico futuro.

## Comandos

Si Node.js esta instalado globalmente:

```powershell
npm install
npm run dev
npm run build
```

En esta maquina tambien existe Node.js portable en `.local-tools/`.
Desde la raiz del repo:

```powershell
$env:Path = "$PWD\.local-tools\node-v24.16.0-win-x64;$env:Path"
npm install --prefix web-public
npm run dev --prefix web-public
npm run build --prefix web-public
```

Tambien puedes usar los scripts del repo desde cualquier carpeta:

```powershell
C:\Users\casa\Documents\Fleteapp\scripts\web-public-dev.ps1
C:\Users\casa\Documents\Fleteapp\scripts\web-public-build.ps1
```

El build queda en `out/` porque `next.config.mjs` usa `output: 'export'`.

## Deploy recomendado

Mantener por ahora Flutter en el hosting actual. Cuando esta web este lista:

- Opcion A: crear un segundo sitio de Firebase Hosting para `web-public`.
- Opcion B: mover el dominio principal a `web-public` y dejar Flutter en subdominio o ruta de app.
