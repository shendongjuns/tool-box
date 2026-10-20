import { JsonFormatterTool } from "@/features/tools/json-formatter";
import { Base64Tool } from "@/features/tools/base64";
import { UrlCodecTool } from "@/features/tools/url-codec";
import { TimestampTool } from "@/features/tools/timestamp";
import { HashTool } from "@/features/tools/hash";
import { UuidTool } from "@/features/tools/uuid";
import { Card, CardContent } from "@/components/ui/card";

const registry: Record<string, React.ComponentType> = {
  "json-formatter": JsonFormatterTool,
  base64: Base64Tool,
  "url-codec": UrlCodecTool,
  timestamp: TimestampTool,
  hash: HashTool,
  uuid: UuidTool,
};

export function ToolRunner({ toolId }: { toolId: string }) {
  const Component = registry[toolId];

  if (!Component) {
    return (
      <Card>
        <CardContent className="py-16 text-center text-sm text-muted-foreground">
          该工具尚未实现。
        </CardContent>
      </Card>
    );
  }

  return <Component />;
}
