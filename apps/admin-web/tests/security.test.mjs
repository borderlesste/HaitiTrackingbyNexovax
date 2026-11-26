import assert from "node:assert/strict";
import test from "node:test";

process.env.NEXT_PUBLIC_SUPABASE_URL = "https://supabase.example.invalid";
process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY = "test-publishable-key";
const { getPanelAccess, supabase, toCsv } = await import("../src/lib/supabase.ts");

test("access requires verified assurance and a server-confirmed staff role", async (t) => {
  const assurance = t.mock.method(supabase.auth.mfa, "getAuthenticatorAssuranceLevel");
  const rpc = t.mock.method(supabase, "rpc");
  const setHeader = t.mock.fn(async () => ({ data: true }));
  assurance.mock.mockImplementation(async () => ({ data: { currentLevel: "aal1", nextLevel: "aal1" } }));
  rpc.mock.mockImplementation(() => ({ setHeader }));

  assert.deepEqual(await getPanelAccess("first-session"), { status: "enroll" });
  assert.deepEqual(rpc.mock.calls.map((call) => call.arguments), [["is_panel_staff"]]);
  assert.deepEqual(assurance.mock.calls[0].arguments, ["first-session"]);
  assert.deepEqual(setHeader.mock.calls[0].arguments, ["Authorization", "Bearer first-session"]);

  assurance.mock.mockImplementation(async () => ({ data: { currentLevel: "aal1", nextLevel: "aal2" } }));
  assert.deepEqual(await getPanelAccess("first-session"), { status: "verify" });
  setHeader.mock.mockImplementation(async () => ({ data: false }));
  assert.deepEqual(await getPanelAccess("ordinary-account"), { status: "denied" });

  assurance.mock.mockImplementation(async () => ({ data: { currentLevel: "aal2", nextLevel: "aal2" } }));
  assert.deepEqual(await getPanelAccess("ordinary-account"), { status: "denied" });
  rpc.mock.mockImplementation((name, args) => ({ setHeader: async () => ({ data: name === "has_role" && args.r === "admin" }) }));
  assert.deepEqual(await getPanelAccess("verified-session"), { status: "allowed", roles: ["admin"] });
});

test("assurance and role lookup failures leave the panel closed", async (t) => {
  const assurance = t.mock.method(supabase.auth.mfa, "getAuthenticatorAssuranceLevel", async () => ({ error: new Error("unavailable") }));
  const rpc = t.mock.method(supabase, "rpc", () => ({ setHeader: async () => ({ error: new Error("unavailable") }) }));
  assert.deepEqual(await getPanelAccess("test-session"), { status: "error" });
  assert.equal(rpc.mock.callCount(), 0);

  assurance.mock.mockImplementation(async () => ({ data: { currentLevel: "aal2", nextLevel: "aal2" } }));
  assert.deepEqual(await getPanelAccess("test-session"), { status: "error" });
});

test("CSV protects text cells and preserves numeric values, quotes and line breaks", () => {
  assert.equal(toCsv([]), "");
  assert.equal(toCsv([{ nombre: "=literal", telefono: "+5091234", moneda: -12, coma: 'a,"b"', salto: "a\rb" }]),
    "nombre,telefono,moneda,coma,salto\n'=literal,'+5091234,-12,\"a,\"\"b\"\"\",\"a\rb\"");
  assert.equal(toCsv([{ texto: "  ＝literal", otro: "\tliteral" }]), "texto,otro\n'  ＝literal,'\tliteral");
});
