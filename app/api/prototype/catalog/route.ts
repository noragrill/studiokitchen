import { NextResponse } from 'next/server'
import { getCatalog, getSlots } from '@/lib/prototype'
export async function GET() { try { const catalog = await getCatalog(); return NextResponse.json({ ...catalog, slots: await getSlots(catalog.brand.id, catalog.location.id) }) } catch (error: any) { return NextResponse.json({ error: error.message }, { status: 500 }) } }
