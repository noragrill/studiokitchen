import { NextResponse } from 'next/server'
import { stripe } from '@/lib/stripe'
import { supabaseAdmin } from '@/lib/supabase-admin'

type CheckoutSession = {
  metadata?: { orderId?: string }
  payment_intent?: string | null
  payment_status?: string
}

export async function POST(request: Request) {
  const signature = request.headers.get('stripe-signature')
  const secret = process.env.STRIPE_WEBHOOK_SECRET

  if (!signature || !secret) {
    return NextResponse.json({ error: 'Webhook is not configured.' }, { status: 400 })
  }

  const body = await request.text()
  let event

  try {
    event = stripe.webhooks.constructEvent(body, signature, secret)
  } catch {
    return NextResponse.json({ error: 'Invalid signature.' }, { status: 400 })
  }

  if (event.type !== 'checkout.session.completed' && event.type !== 'checkout.session.async_payment_succeeded') {
    return NextResponse.json({ received: true })
  }

  const session = event.data.object as unknown as CheckoutSession
  const orderId = session.metadata?.orderId

  if (!orderId || session.payment_status !== 'paid') {
    return NextResponse.json({ received: true })
  }

  const { data: existing, error: existingError } = await supabaseAdmin
    .from('prototype_payments')
    .select('id,raw_event_id')
    .eq('raw_event_id', event.id)
    .maybeSingle()

  if (existingError) {
    return NextResponse.json({ error: 'Payment state could not be checked.' }, { status: 500 })
  }

  if (existing) {
    return NextResponse.json({ received: true, duplicate: true })
  }

  const paidAt = new Date().toISOString()
  const { data: payment, error: paymentError } = await supabaseAdmin
    .from('prototype_payments')
    .update({
      status: 'succeeded',
      stripe_payment_intent_id: session.payment_intent,
      raw_event_id: event.id,
      paid_at: paidAt,
    })
    .eq('order_id', orderId)
    .is('raw_event_id', null)
    .select('id')
    .maybeSingle()

  if (paymentError) {
    return NextResponse.json({ error: 'Payment could not be reconciled.' }, { status: 500 })
  }

  if (!payment) {
    const { data: replayed } = await supabaseAdmin
      .from('prototype_payments')
      .select('id')
      .eq('raw_event_id', event.id)
      .maybeSingle()

    return NextResponse.json({ received: true, duplicate: Boolean(replayed) })
  }

  const { error: orderError } = await supabaseAdmin
    .from('orders')
    .update({ status: 'paid', payment_status: 'paid', paid_at: paidAt })
    .eq('id', orderId)
    .neq('status', 'paid')

  if (orderError) {
    return NextResponse.json({ error: 'Order could not be reconciled.' }, { status: 500 })
  }

  const { error: auditError } = await supabaseAdmin.from('prototype_audit_events').insert({
    order_id: orderId,
    actor_type: 'stripe',
    event_type: 'payment_succeeded',
    payload: { event_id: event.id, payment_intent: session.payment_intent },
  })

  if (auditError) {
    return NextResponse.json({ error: 'Payment audit could not be recorded.' }, { status: 500 })
  }

  return NextResponse.json({ received: true })
}
