import { NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabase-admin'
export async function GET() { const { data, error } = await supabaseAdmin.from('orders').select('id,order_number,collection_at,status,total_pence,created_at,order_items(name,quantity)').in('status',['paid','accepted','preparing','ready']).order('collection_at',{ascending:true}); if(error)return NextResponse.json({error:error.message},{status:500}); return NextResponse.json({ orders:data ?? [] }) }
