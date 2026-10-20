import { createFileRoute, redirect } from "@tanstack/react-router";
import { getApi } from "@/lib/api-context";

export const Route = createFileRoute("/")({
  beforeLoad: async () => {
    try {
      await getApi().me();
      throw redirect({ to: "/dashboard" });
    } catch (error) {
      if (error && typeof error === "object" && "to" in error) throw error;
      throw redirect({ to: "/login" });
    }
  },
});
