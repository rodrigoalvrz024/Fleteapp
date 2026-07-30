import type { Metadata } from 'next';
import './globals.css';
import { AnalyticsBeacon } from './analytics-beacon';
import { publicSiteUrl } from './seo';

export const metadata: Metadata = {
  metadataBase: new URL(publicSiteUrl),
  title: {
    default: 'muvv | Fletes urbanos verificados',
    template: '%s',
  },
  description:
    'muvv conecta clientes con conductores verificados para fletes urbanos seguros, trazables y con respaldo operacional.',
  applicationName: 'muvv',
  category: 'transportation',
  robots: {
    index: true,
    follow: true,
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="es">
      <body>
        <AnalyticsBeacon />
        {children}
      </body>
    </html>
  );
}
