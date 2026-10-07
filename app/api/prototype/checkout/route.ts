import { NextResponse } from 'next/server'
import { getCatalog, hashCode, makeCode } from '@/lib/prototype'
import { supabaseAdmin } from '@/lib/supabase-admin'
import { stripe, stripeConfigured } from '@/lib/stripe'

export async function POST(request: Request) {
  try {
    const body = await request.json() as { items: { id: string; quantity: number; modifierIds?: string[] }[]; collectionAt: string; customer: { name: string; email: string; phone?: string } }
    if (!body.customer?.name || !body.customer?.email || !body.collectionAt || !Array.isArray(body.items) || !body.items.length) return NextResponse.json({ error: 'Complete the customer, cart, and slot details.' }, { status: 400 })
    const { brand, location, items } = await getCatalog()
    const byId = new Map(items.map((item: any) => [item.id, item]))
    const normalized = body.items.map((line) => { const item = byId.get(line.id); if (!item || !Number.isInteger(line.quantity) || line.quantity < 1 || line.quantity > 10) throw new Error('Invalid menu selection') ; return { item, quantity: line.quantity, modifierIds: line.modifierIds ?? [] } })
    const total = normalized.reduce((sum, line) => sum + line.item.price_pence * line.quantity, 0)
    const collectionAt = new Date(body.collectionAt)
    if (Number.isNaN(collectionAt.valueOf()) || collectionAt < new Date(Date.now() + 15 * 60_000)) return NextResponse.json({ error: 'Choose a future collection slot.' }, { status: 400 })
    const { count } = await supabaseAdmin.from('order_slot_holds').select('id', { count: 'exact', head: true }).eq('brand_id', brand.id).eq('location_id', location.id).eq('collection_at', collectionAt.toISOString()).in('status', ['held','converted']).gt('expires_at', new Date().toISOString())
    if ((count ?? 0) >= 8) return NextResponse.json({ error: 'That collection slot has just filled up.' }, { status: 409 })
    const { data: customer, error: customerError } = await supabaseAdmin.from('customers').insert({ name: body.customer.name.trim(), email: body.customer.email.trim().toLowerCase(), phone: body.customer.phone ?? '' }).select('id').single()
    if (customerError) throw customerError
    const orderNumber = `SK-${String(Date.now()).slice(-6)}`
    const code = makeCode()
    const { data: order, error: orderError } = await supabaseAdmin.from('orders').insert({ order_number: orderNumber, brand_id: brand.id, location_id: location.id, customer_id: customer.id, collection_at: collectionAt.toISOString(), total_pence: total, collection_code_hash: hashCode(code), collection_code_expires_at: new Date(collectionAt.getTime() + 12 * 60 * 60 * 1000).toISOString() }).select('id,order_number').single()
    if (orderError) throw orderError
    await supabaseAdmin.from('order_items').insert(normalized.map((line) => ({ order_id: order.id, menu_item_id: line.item.id, name: line.item.name, quantity: line.quantity, unit_price_pence: line.item.price_pence, modifiers: [], line_total_pence: line.item.price_pence * line.quantity })))
    await supabaseAdmin.from('prototype_audit_events').insert({ order_id: order.id, actor_type: 'customer', event_type: 'order_created', payload: { order_number: orderNumber } })
    if (!stripeConfigured) return NextResponse.json({ error: 'Stripe TEST integration is connected but its server key is not available to this runtime.' }, { status: 503 })
    await supabaseAdmin.from('order_slot_holds').insert({ brand_id: brand.id, location_id: location.id, collection_at: collectionAt.toISOString(), status: 'converted', order_id: order.id, expires_at: new Date(collectionAt.getTime() + 12 * 60 * 60 * 1000).toISOString() })
    const session = await stripe.checkout.sessions.create({ mode: 'payment', line_items: normalized.map((line) => ({ price_data: { currency: 'gbp', product_data: { name: line.item.name }, unit_amount: line.item.price_pence }, quantity: line.quantity })), customer_email: body.customer.email, success_url: `${new URL(request.url).origin}/prototype/order/success?order=${order.id}&code=${code}`, cancel_url: `${new URL(request.url).origin}/prototype/order`, metadata: { orderId: order.id, orderNumber } })
    await supabaseAdmin.from('orders').update({ stripe_checkout_session_id: session.id }).eq('id', order.id)
    await supabaseAdmin.from('prototype_payments').insert({ order_id: order.id, stripe_checkout_session_id: session.id, amount_pence: total })
    return NextResponse.json({ url: session.url, orderId: order.id, orderNumber, collectionCode: code })
  } catch (error: any) { return NextResponse.json({ error: error.message ?? 'Checkout could not be started.' }, { status: 500 }) }
}
