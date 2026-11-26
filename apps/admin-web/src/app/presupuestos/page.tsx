import BudgetsView from "@/components/BudgetsView";

// El contenido depende de la sesión del navegador; no se valida como navegación instantánea.
export const instant = false;

export default function Page() {
  return <BudgetsView />;
}
