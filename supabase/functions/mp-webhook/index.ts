// Edge Function: Mercado Pago avisa acá cuando cambia un pago.
// No confiamos en el aviso: consultamos el pago a la API de Mercado Pago con el token
// del comercio, así nadie puede "confirmar" un turno falsificando la notificación.
// Desplegar con:  supabase functions deploy mp-webhook --no-verify-jwt
import { createClient } from "npm:@supabase/supabase-js@2";

const ok = (msg = "ok") => new Response(msg, { status: 200 });

Deno.serve(async (req) => {
  try {
    const u = new URL(req.url);
    const negId = u.searchParams.get("neg");
    let body = {};
    try { body = await req.json(); } catch { /* algunos avisos vienen sin cuerpo */ }

    const tipo = body.type || body.topic || u.searchParams.get("type") || u.searchParams.get("topic");
    const pagoId = body?.data?.id || u.searchParams.get("data.id") || u.searchParams.get("id");
    if (tipo !== "payment" || !pagoId || !negId) return ok("ignorado");

    const sb = createClient(Deno.env.get("SUPABASE_URL"), Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"));
    const { data: sec } = await sb.from("negocio_secretos").select("mp_access_token").eq("negocio_id", negId).maybeSingle();
    if (!sec?.mp_access_token) return ok("sin token");

    const r = await fetch(`https://api.mercadopago.com/v1/payments/${encodeURIComponent(pagoId)}`, {
      headers: { Authorization: `Bearer ${sec.mp_access_token}` },
    });
    if (!r.ok) { console.error("No se pudo leer el pago", r.status); return new Response("reintentar", { status: 500 }); }
    const pago = await r.json();
    if (pago.status !== "approved") return ok("no aprobado: " + pago.status);

    const { data: t } = await sb.from("turnos")
      .select("id, estado, cancelado_por, mp_pago_id")
      .eq("id", pago.external_reference).eq("negocio_id", negId).maybeSingle();
    if (!t) return ok("turno inexistente");
    if (t.mp_pago_id === String(pago.id)) return ok("ya procesado");

    const sena = Math.round(Number(pago.transaction_amount) || 0);
    const vencidoOPendiente = t.estado === "pendiente_pago" || (t.estado === "cancelado" && t.cancelado_por === "vencido");

    if (vencidoOPendiente) {
      const { error } = await sb.from("turnos")
        .update({ estado: "reservado", sena, mp_pago_id: String(pago.id), expira: null, cancelado_por: null })
        .eq("id", t.id);
      if (!error) return ok("confirmado");
      // El pago llegó tarde y el horario ya lo tomó otra persona
      await sb.from("turnos").update({
        sena, mp_pago_id: String(pago.id),
        notas: "Seña cobrada después de que venció el turno y el horario ya estaba ocupado: devolver o reprogramar.",
      }).eq("id", t.id);
      return ok("pago tardío");
    }
    // Cualquier otro caso (por ejemplo, el cliente canceló): registramos la seña para que el comercio la vea
    await sb.from("turnos").update({ sena, mp_pago_id: String(pago.id) }).eq("id", t.id);
    return ok("registrado");
  } catch (e) {
    console.error(e);
    return new Response("error", { status: 500 });
  }
});
