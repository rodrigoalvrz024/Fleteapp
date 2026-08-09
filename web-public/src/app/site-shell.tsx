import Link from 'next/link';
import Image from 'next/image';
import { appBaseUrl } from './seo';

export { appBaseUrl };

export function SiteNav() {
  return (
    <nav className="siteNav" aria-label="Principal">
      <Link className="brand" href="/" aria-label="Muvv inicio">
        <Image
          className="brandIcon"
          src="/muvv-mark.png"
          alt=""
          width={38}
          height={38}
          priority
        />
        <span>Muvv</span>
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
        <strong>Muvv</strong>
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
