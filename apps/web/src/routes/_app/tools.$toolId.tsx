import { createFileRoute, Link, notFound } from "@tanstack/react-router";
import { ArrowLeft } from "lucide-react";
import { findTool } from "@toolbox/contracts";
import { ToolRunner } from "@/components/tools/tool-runner";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";

export const Route = createFileRoute("/_app/tools/$toolId")({
  loader: ({ params }) => {
    const tool = findTool(params.toolId);
    if (!tool) throw notFound();
    return { tool };
  },
  component: ToolPage,
});

function ToolPage() {
  const { tool } = Route.useLoaderData();

  return (
    <div className="space-y-6">
      <div className="flex items-start justify-between gap-4">
        <div className="min-w-0">
          <Button variant="ghost" size="sm" asChild className="-ml-2 mb-1">
            <Link to="/dashboard">
              <ArrowLeft className="h-4 w-4" />
              返回仪表盘
            </Link>
          </Button>
          <h1 className="text-2xl font-semibold tracking-tight">{tool.name}</h1>
          <p className="mt-1 text-sm text-muted-foreground">{tool.description}</p>
        </div>
        <Badge variant="outline">{tool.id}</Badge>
      </div>

      <ToolRunner toolId={tool.id} />
    </div>
  );
}
