import type { Metadata } from 'next';
import localFont from 'next/font/local';
import './globals.css';
const avenir = localFont({ src: '../../public/fonts/Avenir-Book.ttf', variable: '--font-avenir', display: 'swap', weight: '400' });
const louda = localFont({ src: '../../public/fonts/Louda-RegularSC.ttf', variable: '--font-louda', display: 'swap', weight: '400' });
export const metadata: Metadata = { title: 'La Table d’Arçins · Prospection', description: 'Le carnet de prospection de La Table d’Arçins à Bègles.', robots: { index: false, follow: false }, icons: { icon: '/brand/logo-table-darcins.png' } };
export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="fr"><body className={`${avenir.variable} ${louda.variable}`}>{children}</body></html>;
}
