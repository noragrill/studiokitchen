import { createClient } from '@supabase/supabase-js'

const url = process.env.NEXT_PUBLIC_std_kitchen_SUPABASE_URL ?? process.env.std_kitchen_SUPABASE_URL
const key = process.env.std_kitchen_SUPABASE_SERVICE_ROLE_KEY ?? process.env.std_kitchen_SUPABASE_SECRET_KEY
export const supabaseAdmin = createClient(url ?? 'https://placeholder.supabase.co', key ?? 'prototype-runtime-key', { auth: { autoRefreshToken: false, persistSession: false } })
export const supabaseConfigured = Boolean(url && key)
