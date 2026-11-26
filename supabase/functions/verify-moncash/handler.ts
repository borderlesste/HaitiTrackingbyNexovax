type AuthUser = {
  id: string;
  phone?: string | null;
  new_phone?: string | null;
  phone_confirmed_at?: string | null;
  is_anonymous?: boolean;
};

const haitiPhone = /^\+509[0-9]{8}$/;
const uuid = /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i;

function normalizedPhone(value: string | null | undefined) {
  return value?.startsWith("+") ? value : value ? "+" + value : null;
}

function sessionClaim(token: string, userId: string): string | null {
  try {
    const claim = token.split(".")[1];
    const claims = JSON.parse(atob(claim.replaceAll("-", "+").replaceAll("_", "/")));
    return claims.sub === userId && typeof claims.session_id === "string" && uuid.test(claims.session_id)
      ? claims.session_id
      : null;
  } catch {
    return null;
  }
}

async function readRequest(request: Request): Promise<{ phone?: string; code?: string }> {
  const reader = request.body?.getReader();
  if (!reader) return {};
  const decoder = new TextDecoder();
  let length = 0;
  let body = "";
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    length += value.byteLength;
    if (length > 512) {
      await reader.cancel();
      return {};
    }
    body += decoder.decode(value, { stream: true });
  }
  const payload = JSON.parse(body + decoder.decode());
  return payload && typeof payload === "object" ? payload : {};
}

function json(status: number, value: Record<string, string | boolean>) {
  return Response.json(value, { status, headers: { "cache-control": "no-store" } });
}

export function createMoncashHandler(
  config: { url: string; publicKey: string; serviceKey: string },
  supabaseFetch: typeof fetch = fetch,
) {
  const url = config.url.replace(/\/$/, "");
  const requestSupabase = (path: string, options: RequestInit) =>
    supabaseFetch(url + path, { ...options, redirect: "error", signal: AbortSignal.timeout(8000) });

  return async (request: Request): Promise<Response> => {
    if (request.method !== "POST") return json(405, { error: "method_not_allowed" });
    const authorization = request.headers.get("authorization");
    if (!authorization?.match(/^Bearer [\w.-]+$/i)) return json(401, { error: "session_required" });

    let phone: string | undefined;
    let code: string | undefined;
    try {
      ({ phone, code } = await readRequest(request));
    } catch {
      return json(400, { error: "invalid_input" });
    }
    if (typeof phone !== "string" || !haitiPhone.test(phone) || typeof code !== "string" || !/^[0-9]{6}$/.test(code)) {
      return json(400, { error: "invalid_input" });
    }

    try {
      const headers = { apikey: config.publicKey, authorization, "content-type": "application/json" };
      const identity = await requestSupabase("/auth/v1/user", { headers });
      if (!identity.ok) return json(identity.status >= 500 ? 503 : 401, { error: "session_check_failed" });
      const user = await identity.json() as AuthUser;
      if (!uuid.test(user.id) || user.is_anonymous) return json(401, { error: "session_required" });
      const currentSession = sessionClaim(authorization.slice(7), user.id);
      if (!currentSession) return json(401, { error: "session_required" });

      const existingPhone = normalizedPhone(user.phone) === phone;
      if (!existingPhone && normalizedPhone(user.new_phone) !== phone) {
        return json(422, { error: "phone_verification_failed" });
      }
      // Only GoTrue's phone-specific routes can produce the attestation below.
      const verification = await requestSupabase("/auth/v1/verify", {
        method: "POST",
        headers,
        body: JSON.stringify({ type: existingPhone ? "sms" : "phone_change", phone, token: code }),
      });
      if (verification.status === 429) return json(429, { error: "too_many_attempts" });
      if (!verification.ok) return json(verification.status >= 500 ? 503 : 422, { error: "phone_verification_failed" });

      const verified = await verification.json() as { user?: AuthUser; access_token?: string };
      if (verified.user?.id !== user.id || normalizedPhone(verified.user.phone) !== phone ||
        !verified.user.phone_confirmed_at || !verified.access_token) {
        return json(422, { error: "phone_verification_failed" });
      }
      // The JWT is received directly from GoTrue over the configured project connection.
      const verifiedSession = sessionClaim(verified.access_token, user.id);
      if (!verifiedSession) return json(503, { error: "verification_unavailable" });

      const record = await requestSupabase("/rest/v1/rpc/record_moncash_phone", {
        method: "POST",
        headers: {
          apikey: config.serviceKey,
          ...(config.serviceKey.startsWith("sb_secret_") ? {} : { authorization: "Bearer " + config.serviceKey }),
          "content-type": "application/json",
        },
        body: JSON.stringify({
          p_user_id: user.id,
          p_session_id: verifiedSession,
          p_phone: phone,
          p_phone_confirmation_at: verified.user.phone_confirmed_at,
        }),
      }).finally(async () => {
        if (verifiedSession !== currentSession) {
          await requestSupabase("/auth/v1/logout?scope=local", {
            method: "POST",
            headers: { ...headers, authorization: "Bearer " + verified.access_token },
          }).catch(() => {});
        }
      });
      if (!record.ok) return json(503, { error: "verification_unavailable" });
      return json(200, { verified: true });
    } catch {
      return json(503, { error: "verification_unavailable" });
    }
  };
}

