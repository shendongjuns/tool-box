import type { FastifyRequest } from "fastify";

/** 从 Bearer 或 Cookie 中取令牌：桌面端用 Bearer，网页端用 Cookie。 */
export function extractToken(request: FastifyRequest, cookieName: string): string | null {
  const header = request.headers.authorization;
  if (header?.startsWith("Bearer ")) {
    const token = header.slice("Bearer ".length).trim();
    if (token.length > 0) return token;
  }
  const cookie = request.cookies?.[cookieName];
  return cookie && cookie.length > 0 ? cookie : null;
}

