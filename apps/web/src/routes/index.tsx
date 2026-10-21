import { createFileRoute, redirect } from "@tanstack/react-router";
import { getApi } from "@/lib/api-context";

export const Route = createFileRoute("/")({
  beforeLoad: async () => {
    try {
      await getApi().me();
    } catch {
      throw redirect({ to: "/login" });
    }
    throw redirect({ to: "/dashboard" });
  },
});
