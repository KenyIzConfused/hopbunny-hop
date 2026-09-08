/**
 * Unit test for `normalizeProjectKey`, the pure helper that collapses
 * case-differing Windows paths into the same `runProjectConfirmed` session
 * key. Tested directly (rather than through handleRunProject) to avoid
 * platform-gated flakiness in the handler-level session-gate tests.
 *
 * The function branches on `process.platform`, which vitest cannot safely
 * override mid-run — so the assertion only runs on win32 and is a no-op
 * (via `it.runIf`) everywhere else.
 */

import { describe, it, expect } from 'vitest';
import { normalizeProjectKey } from '../../src/utils/mcp-context.js';

describe('normalizeProjectKey', () => {
  it.runIf(process.platform === 'win32')(
    'lowercases the path on win32 so case-differing paths collapse to the same key',
    () => {
      expect(normalizeProjectKey('D:\\proj')).toBe(normalizeProjectKey('d:\\proj'));
    },
  );
});
