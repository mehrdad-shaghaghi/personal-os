// قطب‌نما — Edge Function «push»
// GET  → کلید عمومی اعلان را برمی‌گرداند (اولین بار خودش کلیدها را می‌سازد و در جدول push_keys نگه می‌دارد).
// POST → هر دقیقه از طرف pg_cron صدا زده می‌شود؛ اعلان‌های موعدرسیده را به گوشی‌ها می‌فرستد.
// متن یادآورها هیچ‌وقت به این‌جا نمی‌رسد؛ فقط ساعت و یک متن کلی.
import webpush from "npm:web-push@3.6.7";
import { createClient } from "npm:@supabase/supabase-js@2";

const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "*", "Access-Control-Allow-Methods": "GET,POST,OPTIONS" };
const json = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { ...cors, "Content-Type": "application/json" } });

async function getKeys() {
  const { data } = await sb.from("push_keys").select("pub,priv").eq("id", 1).maybeSingle();
  if (data) return data;
  const k = webpush.generateVAPIDKeys();
  await sb.from("push_keys").upsert({ id: 1, pub: k.publicKey, priv: k.privateKey }, { onConflict: "id", ignoreDuplicates: true });
  const { data: again } = await sb.from("push_keys").select("pub,priv").eq("id", 1).single();
  return again!;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const keys = await getKeys();
    if (req.method === "GET") return json({ pub: keys.pub });

    const now = Date.now();
    // claim due rows atomically so two runs never send the same one
    const { data: due, error } = await sb.from("push_queue").update({ sent: true })
      .eq("sent", false).lte("at", new Date(now).toISOString()).gte("at", new Date(now - 3 * 3600e3).toISOString())
      .select("user_id,id,title,body,hash");
    if (error) return json({ error: error.message }, 500);

    let sent = 0;
    const subsCache = new Map<string, any[]>();
    for (const q of due || []) {
      if (!subsCache.has(q.user_id)) {
        const { data: subs } = await sb.from("push_subs").select("endpoint,p256dh,auth,origin").eq("user_id", q.user_id);
        subsCache.set(q.user_id, subs || []);
      }
      for (const s of subsCache.get(q.user_id)!) {
        try {
          await webpush.sendNotification(
            { endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } },
            JSON.stringify({ title: q.title, body: q.body, tag: q.id, hash: q.hash }),
            { TTL: 3 * 3600, urgency: "high", vapidDetails: { subject: s.origin && s.origin.startsWith("https://") ? s.origin : "mailto:push@example.com", publicKey: keys.pub, privateKey: keys.priv } },
          );
          sent++;
        } catch (e: any) {
          if (e && (e.statusCode === 404 || e.statusCode === 410)) await sb.from("push_subs").delete().eq("endpoint", s.endpoint);
        }
      }
    }
    // tidy old rows
    await sb.from("push_queue").delete().lt("at", new Date(now - 2 * 86400e3).toISOString());
    return json({ due: (due || []).length, sent });
  } catch (e: any) {
    return json({ error: String(e && e.message || e) }, 500);
  }
});
