'use client';

import Link from 'next/link';
import { downloadStores } from './download-links';
import { usePathname } from 'next/navigation';
import { useEffect, useRef, useState } from 'react';

export function MobileNav() {
  const [open, setOpen] = useState(false);
  const trigger = useRef<HTMLButtonElement>(null);
  const menu = useRef<HTMLDivElement>(null);
  const pathname = usePathname();

  useEffect(() => {
    if (!open) return;
    function dismiss(event: PointerEvent) {
      if (event.target instanceof Node && !menu.current?.contains(event.target)) setOpen(false);
    }
    document.addEventListener('pointerdown', dismiss);
    return () => document.removeEventListener('pointerdown', dismiss);
  }, [open]);

  return (
    <div ref={menu} className="mobileNav" onBlur={(event) => {
      if (!event.currentTarget.contains(event.relatedTarget)) setOpen(false);
    }} onKeyDown={(event) => {
      if (event.key === 'Escape') {
        setOpen(false);
        trigger.current?.focus();
      }
    }}>
      <button ref={trigger} className="menuToggle" type="button" aria-expanded={open}
        aria-controls="mobile-menu" onClick={() => setOpen(!open)}>
        {open ? 'Cerrar' : 'Menú'}
        <span className={open ? 'menuGlyph isOpen' : 'menuGlyph'} aria-hidden="true"><i /><i /></span>
      </button>
      <div id="mobile-menu" className="mobileMenu" hidden={!open}>
        {[
          ['/clientes', 'Clientes'], ['/conductores', 'Conductores'], ['/empresas', 'Empresas'], ['/como-funciona', 'Paso a paso'],
        ].map(([href, label]) => <Link key={href} href={href} aria-current={pathname === href ? 'page' : undefined}
          onClick={() => setOpen(false)}>{label}</Link>)}
        <a className="navAction" href="/descargar" onClick={() => setOpen(false)} data-analytics-event="public.cta_click" data-analytics-entity-id="mobile_nav_download">{downloadStores.some(store => store.href) ? 'Descargar Muvv' : 'La app'}</a>
      </div>
    </div>
  );
}
