import Link from 'next/link';
import Image from 'next/image';
import { MobileNav } from './mobile-nav';
import { downloadStores } from './download-links';


export function SiteNav() {
  return (
    <header className="siteHeader">
    <a className="skipLink" href="#contenido">Saltar al contenido</a>
    <nav className="siteNav" aria-label="Principal">
      <Link className="brand" href="/" aria-label="Muvv inicio">
        <Image
          className="brandIcon"
          src="/muvv-logo-oficial.webp"
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
          href="/como-funciona"
          data-analytics-event="public.cta_click"
          data-analytics-entity-id="nav_guide"
        >
          Paso a paso
        </a>
        <a
          className="navAction"
          href="/descargar"
          data-analytics-event="public.cta_click"
          data-analytics-entity-id="nav_download"
        >
          {downloadStores.some(store => store.href) ? 'Descargar Muvv' : 'La app'}
        </a>
      </div>
      <MobileNav />
    </nav>
    </header>
  );
}

export function SiteFooter() {
  return (
    <footer className="footer">
      <div>
        <Link className="brand" href="/" aria-label="Muvv inicio">
          <Image className="brandIcon" src="/muvv-logo-oficial.webp" alt="" width={38} height={38} />
          <strong>Muvv</strong>
        </Link>
        <span>Muvv conecta personas con conductores para fletes urbanos y mudanzas.</span>
      </div>
      <div className="footerLinks">
      <nav aria-label="Información y enlaces legales">
        <Link href="/clientes">Clientes</Link>
        <Link href="/conductores">Conductores</Link>
        <Link href="/empresas">Empresas</Link>
        <Link href="/como-funciona">Paso a paso</Link>
        <Link href="/descargar">{downloadStores.some(store => store.href) ? 'Descargar Muvv' : 'La app'}</Link>
        <Link href="/terminos">Términos</Link>
        <Link href="/privacidad">Privacidad</Link>
      </nav>
      <nav className="footerContact" aria-label="Contacto y redes sociales">
        <a href="mailto:soporte@muvv.cl">soporte@muvv.cl</a>
        <a href="https://www.instagram.com/muvv.cl/" target="_blank" rel="noopener noreferrer">Instagram<span className="srOnly"> (se abre en otra pestaña)</span></a>
        <a href="https://www.facebook.com/muvv.cl/" target="_blank" rel="noopener noreferrer">Facebook<span className="srOnly"> (se abre en otra pestaña)</span></a>
        <a href="https://www.linkedin.com/company/muvv-cl/" target="_blank" rel="noopener noreferrer">LinkedIn<span className="srOnly"> (se abre en otra pestaña)</span></a>
      </nav>
      </div>
    </footer>
  );
}
