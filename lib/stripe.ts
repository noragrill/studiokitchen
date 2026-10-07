import Stripe from 'stripe'

export const stripe = new Stripe(process.env.STRIPE_SECRET_KEY ?? 'sk_test_prototype_placeholder', { apiVersion: '2026-09-30.endive' })
export const stripeConfigured = Boolean(process.env.STRIPE_SECRET_KEY)
