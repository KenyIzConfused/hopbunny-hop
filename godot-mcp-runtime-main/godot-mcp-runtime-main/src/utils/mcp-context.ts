/**
 * Request-scoped context threaded through tool dispatch.
 *
 * Carries the elicitor (used by `run_script` / `run_project` to pause for
 * user confirmation on Tier 2 findings), the global strict-mode flag, the
 * disable-elicitation flag, and per-session state (currently the
 * once-per-project gate for `run_project`).
 *
 * The strict-mode and no-elicit flags are captured when the context is built
 * (see `createContextFromServer` in `src/index.ts`). Toggling `GODOT_MCP_STRICT`
 * or `GODOT_MCP_DISABLE_ELICITATION` after the server starts has no effect.
 */

/**
 * Result of an elicitation prompt. Mirrors the SDK's `ElicitResult` shape
 * without importing it, so the utils layer stays decoupled from the MCP SDK.
 */
export interface ElicitorResult {
  action: 'accept' | 'decline' | 'cancel';
  content?: Record<string, unknown>;
}

export interface ElicitorRequest {
  message: string;
  requestedSchema: {
    type: 'object';
    properties: Record<string, unknown>;
    required?: readonly string[];
  };
}

/**
 * Async function that prompts the user via the MCP elicitation channel.
 * Throws when the client does not support elicitation; callers should treat
 * a thrown error as a denial.
 */
export type Elicitor = (request: ElicitorRequest) => Promise<ElicitorResult>;

export interface SessionState {
  /**
   * Set of absolute project paths for which the user has already approved
   * `run_project` in this server session. First call against each path
   * elicits; later calls skip.
   */
  runProjectConfirmed: Set<string>;
}

export interface McpContext {
  elicitor: Elicitor;
  strictMode: boolean;
  /**
   * When true, the interactive confirmation prompts are skipped and treated as
   * accepted (fail-open): `run_project` launches without its blanket gate, and
   * Tier 2 `run_script` findings proceed with a warning instead of eliciting.
   * Set from `GODOT_MCP_DISABLE_ELICITATION=true` for clients that cannot surface
   * elicitation prompts (e.g. Claude Desktop, which auto-cancels them). This is
   * resolved to `false` when strict mode is on (see `createContextFromServer`):
   * strict mandates explicit confirmation, so it takes precedence. Tier 1
   * hard-block primitives are unaffected — they never elicit and always block.
   */
  disableElicitation: boolean;
  sessionState: SessionState;
}

/**
 * Normalize an absolute project path for use as a key in `runProjectConfirmed`.
 * Windows paths are case-insensitive at the filesystem level, so two calls with
 * `D:\proj` and `d:\proj` would otherwise be treated as distinct projects and
 * each trigger their own elicitation. Lowercasing on win32 collapses them.
 */
export function normalizeProjectKey(absPath: string): string {
  return process.platform === 'win32' ? absPath.toLowerCase() : absPath;
}

/**
 * Build a no-op context for test call sites. The elicitor always declines —
 * tests that need an accept path should construct their own context with a
 * scripted elicitor instead.
 */
export function createNullContext(overrides?: Partial<McpContext>): McpContext {
  return {
    elicitor: async () => ({ action: 'decline' }),
    strictMode: false,
    disableElicitation: false,
    sessionState: {
      runProjectConfirmed: new Set<string>(),
    },
    ...overrides,
  };
}
