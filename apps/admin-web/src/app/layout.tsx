import type { Metadata } from "next";
import AuthGate from "@/components/AuthGate";
import "./globals.css";

// Todo el panel se renderiza en el cliente detrás del login; no hay contenido estático que validar.
export const instant = false;

export const metadata: Metadata = {
  title: "Haiti Tracking · Admin",
  description: "Panel administrativo privado de Haiti Tracking by Nexovax",
  robots: { index: false, follow: false },
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="es">
      <body>
        <AuthGate>{children}</AuthGate>
      </body>
    </html>
  );
}
