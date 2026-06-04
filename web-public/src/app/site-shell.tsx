import Link from 'next/link';

export const appBaseUrl = 'https://fleteapp-8d8f7.web.app';

export function SiteNav() {
  return (
    <nav className="siteNav" aria-label="Principal">
      <Link className="brand" href="/" aria-label="FleteApp inicio">
        <span className="brandIcon">F</span>
        <span>FleteApp</span>
      </Link>
      <div className="navLinks">
        <Link href="/clientes">Clientes</Link>
        <Link href="/conductores">Conductores</Link>
        <Link href="/empresas">Negocios</Link>
        <a href={`${appBaseUrl}/#/auth/login`}>Ingresar</a>
        <a className="navAction" href={`${appBaseUrl}/#/auth/register`}>
          Registrarse
        </a>
      </div>
    </nav>
  );
}

export function SiteFooter() {
  return (
    <footer className="footer">
      <div>
        <strong>FleteApp</strong>
        <span>Fletes urbanos verificados para Chile.</span>
      </div>
      <nav aria-label="Legal">
        <Link href="/clientes">Clientes</Link>
        <Link href="/conductores">Conductores</Link>
        <Link href="/empresas">Negocios</Link>
        <Link href="/terminos">Terminos</Link>
        <Link href="/privacidad">Privacidad</Link>
      </nav>
    </footer>
  );
}
