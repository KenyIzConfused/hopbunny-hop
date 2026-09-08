import type { HandlerResult } from '../mcp.types.js';
import { ok } from './result.js';

/**
 * Wrap a structured payload as a handler success that satisfies the MCP
 * outputSchema contract. The same payload is emitted both as a JSON text
 * content block (for lenient clients) and as `structuredContent` (required
 * by strict clients per MCP spec revision 2025-06-18).
 *
 * `extraContent` is prepended for handlers that also return non-text blocks
 * (e.g. `take_screenshot`'s inline image).
 */
export function createStructuredResponse<T extends Record<string, unknown>>(
  payload: T,
  extraContent: Array<{ type: string; [k: string]: unknown }> = [],
): HandlerResult {
  return ok({
    content: [...extraContent, { type: 'text', text: JSON.stringify(payload) }],
    structuredContent: payload,
  });
}
