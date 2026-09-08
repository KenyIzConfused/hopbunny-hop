/**
 * .tscn / project.godot parsing helpers shared by the run-script security
 * pipeline. Parallel in style to `autoload-ini.ts` — line-oriented INI/TSCN
 * parsing, no Godot process required.
 *
 * Responsibilities:
 *  - Resolve the scene a `run_project` call will actually launch (explicit
 *    `scene` arg > `run/main_scene` in [application] > null).
 *  - Extract the list of `[ext_resource type="Script" path="res://..."]`
 *    references from a .tscn file, mapped to absolute project-relative paths.
 *  - Recurse transitively into `[ext_resource type="PackedScene"]` references
 *    so a script attached to a subscene the launched scene instances is
 *    caught too (`collectSceneScriptsRecursive`).
 *
 * Not chased (documented limitation, not a TODO — see `docs/security.md`):
 * inline `[sub_resource type="GDScript"]` scripts embedded directly in the
 * .tscn, and `[instance]` property overrides. Both would need a separate
 * parsing pipeline beyond ext_resource line-scanning.
 */

import { readFileSync } from 'fs';
import { join, resolve } from 'path';
import { projectGodotPath, stripResPrefix } from './path-validation.js';
import { walkIniSection } from './autoload-ini.js';

function isFileNotFound(err: unknown): boolean {
  return (err as NodeJS.ErrnoException | null)?.code === 'ENOENT';
}

/**
 * Read a scene file's content, returning null (not throwing) when the file
 * is missing — a stale ext_resource reference must not crash the pre-flight.
 */
function readSceneFileSafe(scenePath: string): string | null {
  try {
    return readFileSync(scenePath, 'utf8');
  } catch (err) {
    if (isFileNotFound(err)) return null;
    throw err;
  }
}

/**
 * Shared ext_resource line-scanner underlying both `extractSceneScripts` and
 * `collectSceneScriptsRecursive`. Returns `res://`-stripped paths (not yet
 * joined to a project root) for every top-level
 * `[ext_resource type="<typeValue>" path="res://..."]` entry, optionally
 * filtered to paths ending in `requiredExt`.
 */
function extractExtResourcePaths(
  content: string,
  typeValue: string,
  requiredExt?: string,
): string[] {
  const result: string[] = [];
  const lineRe = /^\[ext_resource\b([^\]]*)\]/;
  const typeRe = new RegExp(`type\\s*=\\s*"${typeValue}"`);
  for (const rawLine of content.split('\n')) {
    const match = rawLine.match(lineRe);
    if (!match) continue;
    const attrs = match[1] ?? '';
    if (!typeRe.test(attrs)) continue;
    const pathMatch = attrs.match(/path\s*=\s*"([^"]+)"/);
    if (!pathMatch || !pathMatch[1]) continue;
    const stripped = stripResPrefix(pathMatch[1]);
    if (requiredExt && !stripped.endsWith(requiredExt)) continue;
    result.push(stripped);
  }
  return result;
}

/**
 * Read `run/main_scene` from `[application]` in project.godot. Returns the
 * `res://...` string if present, else null. Does NOT verify the file exists.
 */
export function readMainSceneFromProject(projectDir: string): string | null {
  const projectFile = projectGodotPath(projectDir);
  let content: string;
  try {
    content = readFileSync(projectFile, 'utf8');
  } catch (err) {
    if (isFileNotFound(err)) return null;
    throw err;
  }
  let mainScene: string | null = null;
  walkIniSection(content, 'application', (trimmed) => {
    // Match: run/main_scene="res://main.tscn"  (quotes are always present
    // when Godot writes; tolerate omitted quotes for hand-edited files).
    const match = trimmed.match(/^run\/main_scene\s*=\s*"?([^"]+?)"?$/);
    if (match && match[1]) {
      mainScene = match[1];
      return true;
    }
  });
  return mainScene;
}

/**
 * Pick the scene that `run_project` will actually launch.
 *
 * Resolution order:
 *  1. Explicit `sceneArg` (caller's `scene` parameter) — already validated by
 *     `validateSubPath` before being passed here. Returned as an absolute path.
 *  2. `run/main_scene` from project.godot, with `res://` stripped and joined
 *     to the project root.
 *  3. null — no scene to scan. Caller logs a warning and skips the scene-script
 *     scan; autoload scan still runs.
 *
 * Returns an absolute filesystem path. Does NOT verify the file exists; the
 * caller's `existsSync` check produces the warning if the resolved path is
 * stale.
 */
export function resolveLaunchScene(projectDir: string, sceneArg?: string | null): string | null {
  if (sceneArg) {
    return join(projectDir, stripResPrefix(sceneArg));
  }
  const main = readMainSceneFromProject(projectDir);
  if (!main) return null;
  return join(projectDir, stripResPrefix(main));
}

/**
 * Extract top-level `[ext_resource type="Script" path="res://..."]` references
 * from a .tscn file. Returns absolute filesystem paths relative to the project
 * root.
 *
 * Limitations (intentional — see `docs/security.md`):
 *  - Does NOT chase `[sub_resource type="GDScript"]` inline scripts — those
 *    embed GDScript source inside the .tscn and would need a separate scan
 *    pipeline.
 *  - Does NOT account for `[instance]` property overrides.
 *  - Returns paths even if the file does not exist on disk; caller is
 *    responsible for the existence check (and recording a warning).
 *
 * Does NOT recurse into `[ext_resource type="PackedScene"]` references — use
 * `collectSceneScriptsRecursive` for the transitive walk across subscenes.
 */
export function extractSceneScripts(scenePath: string, projectDir: string): string[] {
  const content = readSceneFileSafe(scenePath);
  if (content === null) return [];
  // ext_resource lines look like:
  //   [ext_resource type="Script" path="res://scripts/foo.gd" id="1_xxx"]
  // or with uid="...":
  //   [ext_resource type="Script" uid="..." path="res://..." id="..."]
  // We do a permissive match: `type="Script"` somewhere in the line + a
  // `path="res://..."` clause.
  return extractExtResourcePaths(content, 'Script', '.gd').map((stripped) =>
    join(projectDir, stripped),
  );
}

/**
 * Transitively walk `[ext_resource type="PackedScene"]` references starting
 * at `scenePath`, unioning every reachable scene's `type="Script"`
 * ext_resources. Closes the subscene-recursion gap in `extractSceneScripts`:
 * a hostile script attached to a PackedScene the launched scene instances is
 * invisible to a single-scene scan.
 *
 * Cycle-safe: scene graphs can reference each other in a cycle, so visited
 * scenes (by resolved absolute path) are never re-walked. Missing scene
 * files are skipped silently, same as `extractSceneScripts` — a stale
 * reference must not crash the run_project pre-flight.
 *
 * Returns the de-duplicated union of script paths (absolute).
 */
export function collectSceneScriptsRecursive(scenePath: string, projectDir: string): string[] {
  const visited = new Set<string>();
  const scripts = new Set<string>();

  function walk(currentScenePath: string): void {
    const absScenePath = resolve(currentScenePath);
    if (visited.has(absScenePath)) return;
    visited.add(absScenePath);

    const content = readSceneFileSafe(currentScenePath);
    if (content === null) return;

    for (const stripped of extractExtResourcePaths(content, 'Script', '.gd')) {
      scripts.add(join(projectDir, stripped));
    }
    for (const stripped of extractExtResourcePaths(content, 'PackedScene')) {
      walk(join(projectDir, stripped));
    }
  }

  walk(scenePath);
  return Array.from(scripts);
}
