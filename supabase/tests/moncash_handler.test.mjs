import assert from "node:assert/strict";
import test from "node:test";
import { createMoncashHandler } from "../functions/verify-moncash/handler.ts";

const actor = "70c04811-2765-4446-b7ed-b067bc4a0235";
const sessionId = "0e226dcb-aba0-4168-90c8-6f7f09241960";
const other = "4594bde3-b8ab-47df-87d7-66eb113285c0";
const phone = "+50937110001";
const confirmedAt = "2026-11-26T19:20:00.123456Z";
const fixtureJwt = (session) => "header." + Buffer.from(JSON.stringify({ sub: actor, session_id: session })).toString("base64url") + ".fixture";
const token = fixtureJwt(sessionId);
const callerAuthorization = "Bearer " + fixtureJwt("de2b0f43-7c63-49a6-bbef-7494d3118787");
const user = { id: actor, phone: phone.slice(1), phone_confirmed_at: confirmedAt };
const verified = { user, access_token: token, refresh_token: "fixture-refresh" };
const config = { url: "https://fixture.invalid", publicKey: "public-fixture", serviceKey: ["sb", "secret", "fixture"].join("_") };

function fixture({ identity = user, verification = verified, verifyStatus = 200, recordStatus = 204 } = {}) {
  const requests = [];
  const handler = createMoncashHandler(config, async (url, options) => {
    const requestUrl = new URL(url);
    const path = requestUrl.pathname;
    requests.push({ path, options, scope: requestUrl.searchParams.get("scope") });
    if (path === "/auth/v1/user") return Response.json(identity, { status: identity ? 200 : 401 });
    if (path === "/auth/v1/verify") return Response.json(verification, { status: verifyStatus });
    if (path === "/rest/v1/rpc/record_moncash_phone") return new Response(null, { status: recordStatus });
    if (path === "/auth/v1/logout") return new Response(null, { status: 204 });
    throw new Error("Unexpected mock path");
  });
  const post = (payload = { phone, code: "123456" }, authorization = callerAuthorization) =>
    handler(new Request(config.url + "/functions/v1/verify-moncash", {
      method: "POST",
      body: JSON.stringify(payload),
      ...(authorization ? { headers: { authorization } } : {}),
    }));
  return { requests, post };
}

test("requires a current session before verification", async () => {
  const noHeader = fixture();
  assert.equal((await noHeader.post(undefined, null)).status, 401);
  assert.equal(noHeader.requests.length, 0);
  const rejectedIdentity = fixture({ identity: null });
  assert.equal((await rejectedIdentity.post()).status, 401);
  assert.equal(rejectedIdentity.requests.length, 1);
});

test("validates the phone, code and request size before calling Auth", async () => {
  const { post, requests } = fixture();
  for (const input of [
    { phone: "37110001", code: "123456" },
    { phone, code: 123456 },
    { phone, code: "123456", padding: "x".repeat(600) },
  ]) {
    assert.equal((await post(input)).status, 400);
  }
  assert.equal(requests.length, 0);
});

test("existing confirmed account phone goes through SMS and a session-bound service call", async () => {
  const { post, requests } = fixture();
  const response = await post();
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("cache-control"), "no-store");
  assert.deepEqual(await response.json(), { verified: true });
  assert.deepEqual(requests.map(({ path }) => path), [
    "/auth/v1/user", "/auth/v1/verify", "/rest/v1/rpc/record_moncash_phone", "/auth/v1/logout",
  ]);
  assert.equal(requests[0].options.headers.authorization, callerAuthorization);
  assert.deepEqual(JSON.parse(requests[1].options.body), { type: "sms", phone, token: "123456" });
  assert.equal(requests[1].options.headers.apikey, config.publicKey);
  assert.equal(requests[2].options.headers.apikey, config.serviceKey);
  assert.equal(requests[2].options.headers.authorization, undefined);
  assert.deepEqual(JSON.parse(requests[2].options.body), {
    p_user_id: actor, p_session_id: sessionId, p_phone: phone, p_phone_confirmation_at: confirmedAt,
  });
  assert.equal(requests[3].scope, "local");
  assert.equal(requests[3].options.headers.authorization, "Bearer " + token);
});

test("leaves the original session active when Auth reuses it", async () => {
  const callerToken = callerAuthorization.slice(7);
  const { post, requests } = fixture({ verification: { ...verified, access_token: callerToken } });
  assert.equal((await post()).status, 200);
  assert.equal(requests.length, 3);
});

test("an account with a matching pending change uses the phone-change confirmation", async () => {
  const { post, requests } = fixture({ identity: { id: actor, phone: "50937110002", new_phone: phone.slice(1) } });
  assert.equal((await post()).status, 200);
  assert.equal(JSON.parse(requests[1].options.body).type, "phone_change");
});

test("unrelated phones are rejected before OTP verification", async () => {
  const { post, requests } = fixture({ identity: { id: actor, phone: "50937110002" } });
  assert.equal((await post()).status, 422);
  assert.equal(requests.length, 1);
});

test("rejects any verification session for another account or number", async () => {
  for (const changedUser of [{ ...user, id: other }, { ...user, phone: "50937110002" }]) {
    const { post, requests } = fixture({ verification: { ...verified, user: changedUser } });
    assert.equal((await post()).status, 422);
    assert.equal(requests.length, 2);
  }
});

test("propagates throttling and rejects expired or invalid OTP without recording proof", async () => {
  for (const [upstream, expected] of [[429, 429], [403, 422], [500, 503]]) {
    const { post, requests } = fixture({ verifyStatus: upstream });
    assert.equal((await post()).status, expected);
    assert.equal(requests.length, 2);
  }
});

test("never returns a session if the Auth claims or the proof insert fail", async () => {
  for (const options of [{ verification: { ...verified, access_token: "incomplete" } }, { recordStatus: 403 }]) {
    const { post } = fixture(options);
    const response = await post();
    assert.equal(response.status, 503);
    assert.deepEqual(await response.json(), { error: "verification_unavailable" });
  }
});

