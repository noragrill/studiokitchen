import type { Metadata } from 'next'
import './globals.css'

export const metadata: Metadata = { title: 'Studio Kitchen Prototype', description: 'Internal development ordering prototype' }

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="en" className="bg-stone-100"><body>{children}</body></html>
}
