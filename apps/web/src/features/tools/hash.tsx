import { useEffect, useState } from "react";
import { Copy } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";

async function sha(algorithm: "SHA-1" | "SHA-256", text: string): Promise<string> {
  const data = new TextEncoder().encode(text);
  const buffer = await crypto.subtle.digest(algorithm, data);
  return [...new Uint8Array(buffer)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

/** 精简 MD5（RFC 1321），仅用于校验值展示，不作为安全用途。 */
function md5(bytes: Uint8Array): string {
  const shifts = [
    7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9,
    14, 20, 5, 9, 14, 20, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 6, 10, 15,
    21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
  ];
  const k = Array.from({ length: 64 }, (_, i) =>
    Math.floor(Math.abs(Math.sin(i + 1)) * 2 ** 32),
  );

  const padded = new Uint8Array((((bytes.length + 8) >> 6) + 1) << 6);
  padded.set(bytes);
  padded[bytes.length] = 0x80;
  const view = new DataView(padded.buffer);
  view.setUint32(padded.length - 8, (bytes.length * 8) >>> 0, true);

  let a0 = 0x67452301;
  let b0 = 0xefcdab89;
  let c0 = 0x98badcfe;
  let d0 = 0x10325476;

  for (let offset = 0; offset < padded.length; offset += 64) {
    const words = Array.from({ length: 16 }, (_, i) => view.getUint32(offset + i * 4, true));
    let a = a0;
    let b = b0;
    let c = c0;
    let d = d0;

    for (let i = 0; i < 64; i += 1) {
      let f: number;
      let g: number;
      if (i < 16) {
        f = (b & c) | (~b & d);
        g = i;
      } else if (i < 32) {
        f = (d & b) | (~d & c);
        g = (5 * i + 1) % 16;
      } else if (i < 48) {
        f = b ^ c ^ d;
        g = (3 * i + 5) % 16;
      } else {
        f = c ^ (b | ~d);
        g = (7 * i) % 16;
      }
      const rotated = (a + f + k[i]! + (words[g] ?? 0)) >>> 0;
      const shift = shifts[i]!;
      const next = (b + ((rotated << shift) | (rotated >>> (32 - shift)))) >>> 0;
      a = d;
      d = c;
      c = b;
      b = next;
    }

    a0 = (a0 + a) >>> 0;
    b0 = (b0 + b) >>> 0;
    c0 = (c0 + c) >>> 0;
    d0 = (d0 + d) >>> 0;
  }

  const out = new Uint8Array(16);
  const outView = new DataView(out.buffer);
  outView.setUint32(0, a0, true);
  outView.setUint32(4, b0, true);
  outView.setUint32(8, c0, true);
  outView.setUint32(12, d0, true);
  return [...out].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

export function HashTool() {
  const [text, setText] = useState("ToolBox");
  const [hashes, setHashes] = useState<Record<string, string>>({});

  useEffect(() => {
    let cancelled = false;
    const run = async () => {
      try {
        const [sha1, sha256] = await Promise.all([sha("SHA-1", text), sha("SHA-256", text)]);
        if (cancelled) return;
        setHashes({ MD5: md5(new TextEncoder().encode(text)), "SHA-1": sha1, "SHA-256": sha256 });
      } catch {
        // 某些环境（非安全上下文）没有 crypto.subtle，MD5 仍可用
        if (!cancelled) setHashes({ MD5: md5(new TextEncoder().encode(text)) });
      }
    };
    void run();
    return () => {
      cancelled = true;
    };
  }, [text]);

  return (
    <Card>
      <CardHeader>
        <CardTitle>哈希计算</CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        <textarea
          value={text}
          onChange={(event) => setText(event.target.value)}
          spellCheck={false}
          className="h-28 w-full resize-none rounded-lg border border-border bg-card p-3 font-mono text-sm outline-none focus-visible:ring-2 focus-visible:ring-[var(--ring)]"
        />
        <div className="space-y-2">
          {Object.entries(hashes).map(([algorithm, value]) => (
            <div
              key={algorithm}
              className="flex items-center gap-3 rounded-lg border border-border bg-muted/30 px-3 py-2"
            >
              <span className="w-20 shrink-0 text-xs font-medium text-muted-foreground">
                {algorithm}
              </span>
              <code className="min-w-0 flex-1 truncate font-mono text-xs">{value}</code>
              <Button
                variant="ghost"
                size="icon-sm"
                onClick={async () => {
                  await navigator.clipboard.writeText(value);
                  toast.success("已复制");
                }}
              >
                <Copy className="h-4 w-4" />
              </Button>
            </div>
          ))}
        </div>
      </CardContent>
    </Card>
  );
}
