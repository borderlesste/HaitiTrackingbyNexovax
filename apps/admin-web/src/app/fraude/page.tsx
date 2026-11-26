import FraudView from "@/components/FraudView";

// El contenido depende de la sesión del navegador; no se valida como navegación instantánea.
export const instant = false;

export default function Page() {
  return <FraudView />;
}
