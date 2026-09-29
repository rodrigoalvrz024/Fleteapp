import Image from 'next/image';

export function HomeVisual() {
  return <figure className="heroVisual">
    <Image src="/muvv-moving.webp" alt="Imagen de campaña Muvv: traslado de cajas y muebles en un furgón." fill priority sizes="(max-width: 760px) 100vw, 50vw" />
    <figcaption><span>De tu puerta a tu próximo destino.</span><strong>Pide un flete. Que sea Muvv.</strong></figcaption>
  </figure>;

}
