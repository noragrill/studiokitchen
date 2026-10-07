import crypto from 'node:crypto'
import { supabaseAdmin } from './supabase-admin'

export function hashCode(code: string) { return crypto.createHash('sha256').update(code).digest('hex') }
export function makeCode() { return String(crypto.randomInt(100000, 1000000)) }
export function pounds(pence: number) { return `£${(pence / 100).toFixed(2)}` }
export async function getCatalog() {
  const { data: brand } = await supabaseAdmin.from('brands').select('id,name,slug').eq('slug', 'nora-prototype').single()
  if (!brand) throw new Error('Demo brand is not seeded')
  const { data: items, error } = await supabaseAdmin.from('menu_items').select('id,name,description,price_pence,category_id,menu_categories(name)').eq('brand_id', brand.id).eq('is_available', true).order('name')
  if (error) throw error
  const { data: location } = await supabaseAdmin.from('locations').select('id,name,timezone').eq('name', 'Development Kitchen').single()
  if (!location) throw new Error('Demo location is not seeded')
  return { brand, location, items: (items ?? []).map((item: any) => ({ ...item, category: item.menu_categories?.name ?? 'Menu' })) }
}
export async function getSlots(brandId: string, locationId: string) {
  const { data: settings } = await supabaseAdmin.from('brand_collection_settings').select('slot_interval_minutes,slot_capacity,preparation_lead_minutes,kitchen_paused').eq('brand_id', brandId).eq('location_id', locationId).single()
  const interval = settings?.slot_interval_minutes ?? 30
  const capacity = settings?.slot_capacity ?? 8
  const lead = settings?.preparation_lead_minutes ?? 25
  const start = new Date(Date.now() + lead * 60_000)
  start.setMinutes(Math.ceil(start.getMinutes() / interval) * interval, 0, 0)
  const slots = []
  for (let i = 0; i < 8; i++) { const at = new Date(start.getTime() + i * interval * 60_000); const { count } = await supabaseAdmin.from('order_slot_holds').select('id', { count: 'exact', head: true }).eq('brand_id', brandId).eq('location_id', locationId).eq('collection_at', at.toISOString()).in('status', ['held', 'converted']).gt('expires_at', new Date().toISOString()); slots.push({ at: at.toISOString(), available: !settings?.kitchen_paused && (count ?? 0) < capacity }) }
  return slots
}
