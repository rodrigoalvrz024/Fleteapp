import type { Metadata } from 'next';
import './globals.css';

export const metadata: Metadata = {
  title: 'FleteApp | Fletes urbanos verificados',
  description:
    'FleteApp conecta clientes con conductores verificados para fletes urbanos seguros y trazables.',
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="es">
      <body>{children}</body>
    </html>
  );
}
