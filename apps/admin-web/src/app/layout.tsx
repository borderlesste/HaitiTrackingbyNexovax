import type { Metadata } from "next";
import { connection } from "next/server";
import AuthGate from "@/components/AuthGate";
import "./globals.css";

export const metadata: Metadata = {
  title: "Haiti Tracking · Admin",
  description: "Panel administrativo privado de Haiti Tracking by Nexovax",
  robots: { index: false, follow: false },
};

export default async function RootLayout({ children }: LayoutProps<"/">) {
  // Next aplica el nonce de CSP a los scripts durante cada solicitud.
  await connection();
  return (
    <html lang="es">
      <body>
        <AuthGate>{children}</AuthGate>
      </body>
    </html>
  );
}
