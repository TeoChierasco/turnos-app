// Edge Function: crea el link de pago de Mercado Pago para la seña de un turno.
// La llama la página de reservas justo después de reservar.
// Desplegar con:  supabase functions deploy crear-pago
import { createClient } from "npm:@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  try {
    const { turno_id, volver_a } = await req.json();
    if (!turno_id) return json({ error: "falta_turno" }, 400);

    const url = Deno.env.get("SUPABASE_URL");
    const sb = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"));

    const { data: t } = await sb.from("turnos")
      .select("id, estado, expira, negocio_id, servicio_id")
      .eq("id", turno_id).maybeSingle();
    if (!t || t.estado !== "pendiente_pago") return json({ error: "no_pendiente" }, 400);
    if (new Date(t.expira) < new Date()) return json({ error: "vencido" }, 400);

    const { data: neg } = await sb.from("negocios").select("id, nombre, sena_monto").eq("id", t.negocio_id).single();
    const { data: sec } = await sb.from("negocio_secretos").select("mp_access_token").eq("negocio_id", t.negocio_id).maybeSingle();
    const { data: srv } = await sb.from("servicios").select("nombre").eq("id", t.servicio_id).maybeSingle();
    if (!sec?.mp_access_token || !(neg.sena_monto > 0)) return json({ error: "sin_mp" }, 400);

    // A dónde vuelve el cliente después de pagar: su página del turno
    const vuelta = typeof volver_a === "string" && /^https?:\/\//.test(volver_a) ? volver_a : null;

    const pref = {
      items: [{
        id: t.id,
        title: `Seña · ${srv?.nombre ?? "Turno"} · ${neg.nombre}`.slice(0, 250),
        quantity: 1,
        unit_price: Number(neg.sena_monto),
        currency_id: "ARS",
      }],
      external_reference: t.id,
      notification_url: `${url}/functions/v1/mp-webhook?neg=${neg.id}`,
      expires: true,
      expiration_date_to: new Date(t.expira).toISOString(),
      date_of_expiration: new Date(t.expira).toISOString(),
      ...(vuelta ? { back_urls: { success: vuelta, pending: vuelta, failure: vuelta }, auto_return: "approved" } : {}),
    };

    const r = await fetch("https://api.mercadopago.com/checkout/preferences", {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${sec.mp_access_token}` },
      body: JSON.stringify(pref),
    });
    const data = await r.json();
    if (!r.ok || !data.init_point) {
      console.error("MP error", r.status, data);
      return json({ error: "mp_error" }, 502);
    }
    return json({ url: data.init_point });
  } catch (e) {
    console.error(e);
    return json({ error: "interno" }, 500);
  }
});
