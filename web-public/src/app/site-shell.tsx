import Link from 'next/link';
import { appBaseUrl } from './seo';

export { appBaseUrl };

export function SiteNav() {
  return (
    <nav className="siteNav" aria-label="Principal">
      <Link className="brand" href="/" aria-label="FleteApp inicio">
        <span className="brandIcon" aria-hidden="true">F</span>
        <span>FleteApp</span>
      </Link>
      <div className="navLinks">
        <Link href="/clientes">Clientes</Link>
        <Link href="/conductores">Conductores</Link>
        <Link href="/empresas">Empresas</Link>
        <a
          href={`${appBaseUrl}/#/auth/login`}
          data-analytics-event="public.cta_click"
          data-analytics-entity-id="nav_login"
        >
          Ingresar
        </a>
        <a
          className="navAction"
          href={`${appBaseUrl}/#/auth/register`}
          data-analytics-event="public.cta_click"
          data-analytics-entity-id="nav_register"
        >
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
        <span>Fletes urbanos con respaldo operativo para Chile.</span>
      </div>
      <nav aria-label="Legal">
        <Link href="/clientes">Clientes</Link>
        <Link href="/conductores">Conductores</Link>
        <Link href="/empresas">Empresas</Link>
        <Link href="/terminos">Terminos</Link>
        <Link href="/privacidad">Privacidad</Link>
      </nav>
    </footer>
  );
}
