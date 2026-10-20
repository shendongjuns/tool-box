import { useEffect, useState } from "react";
import { Copy } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";

async function digest(algorithm: "MD5" | "SHA-1" | "SHA-256", text: string): Promise<string> {
  const data = new TextEncoder().encode(text);

  if (algorithm === "MD5") {
    // Web Crypto 不提供 MD5；这里用一个精简实现（仅用于非安全场景的校验值计算）
    return md5(data);
  }
  const buffer = await crypto.subtle.digest(algorithm, data);
  return [...new Uint8Array(buffer)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

/** 精简 MD5 实现（RFC 1321），仅用于工具页的校验值展示。 */
function md5(bytes: Uint8Array): string {
  const s = [7, 12, 17, 22, 5, 9, 14, 20, 4, 11, 16, 23, 6, 10, 15, 21];
  const k = Array.from({ length: 64 }, (_, i) => Math.floor(Math.abs(Math.sin(i + 1)) * 2 ** 32));
  const padded = new Uint8Array((((bytes.length + 8) >> 6) + 1) << 6);
  padded.set(bytes);
  padded[bytes.length] = 0x80;
  const view = new DataView(padded.buffer);
  view.setUint32(padded.length - 8, bytes.length * 8, true);

  let a0 = 0x67452301;
  let b0 = 0xefcdab89;
  let c0 = 0x98badcfe;
  let d0 = 0x10325476;

  for (let offset = 0; offset < padded.length; offset += 64) {
    const words = Array.from({ length: 16 }, (_, i) => view.getUint32(offset + i * 4, true));
    let [a, b, c, d] = [a0, b0, c0, d0];
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
      const tmp = d;
      d = c;
      c = b;
      const sum = (a + f + (k[i] ?? 0) + (words[g] ?? 0)) >>> 0;
      b = (b + ((sum << s[(i >> 4) * 4 + (i % 4)]!) | (sum >>> (32 - s[(i >> 4) * 4 + (i % 4)]!)))) >>> 0;
      a = tmp;
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
    void Promise.all([
      digest("MD5", text),
      digest("SHA-1", text),
      digest("SHA-256", text),
    ]).then(([md5Value, sha1, sha256]) => {
      if (cancelled) return;
      setHashes({ MD5: md5Value, "SHA-1": sha1, "SHA-256": sha256 });
    });
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
              <Button variant="ghost" size="icon-sm" onClick={() => void navigator.clipboard.writeText(value)}>
                <Copy className="h-4 w-4" />
              </Button>
            </div>
          ))}
        </div>
      </CardContent>
    </Card>
  );
}
