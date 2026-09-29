import { downloadStores } from './download-links';

export function StoreIcon({ platform }: { platform: string }) {
  return platform === 'android'
    ? <svg width="28" height="30" viewBox="0 0 28 30" aria-hidden="true"><path fill="#34a853" d="M2 2 16 15 2 28Z"/><path fill="#4285f4" d="M2 2 20 12 16 15Z"/><path fill="#fbbc04" d="m20 12 6 3-6 3-4-3Z"/><path fill="#ea4335" d="M2 28 16 15l4 3Z"/></svg>
    : <svg width="30" height="30" viewBox="0 0 30 30" fill="none" stroke="currentColor" strokeWidth="2.8" strokeLinecap="round" aria-hidden="true"><rect x="1" y="1" width="28" height="28" rx="7" fill="#1475ef" stroke="none"/><path d="m12 7 7 12M17 7 9 21M7 19h12m2 0 2 4"/></svg>;
}


export function StoreBadges() {
  return <div className="storeBadgeRow" aria-label="Disponibilidad de la app">
    {downloadStores.map(store => <a className="storeBadge storeBadgeCompact" key={store.id}
      href={store.href || `/descargar?plataforma=${store.id}#aviso-lanzamiento`}>
      <StoreIcon platform={store.id} /><span><small>{store.href ? 'Descargar en' : 'Próximamente · Avísame'}</small>{store.name}</span>
    </a>)}
  </div>;
}
