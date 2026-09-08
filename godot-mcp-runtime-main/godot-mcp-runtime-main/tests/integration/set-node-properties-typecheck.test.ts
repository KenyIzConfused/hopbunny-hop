/**
 * Regression tests for type-invalid property assignments (silent-success gap).
 *
 * Context: `node.set()` casts the incoming value through the property's
 * typed setter with no validity return -- a type-incompatible value doesn't
 * fail, it silently stores the ZERO value for the declared type (e.g. a
 * String or Dictionary on an int property stores 0, a String on a Vector2
 * property stores (0, 0)) -- but the tool previously reported
 * `success: true`, so agents believed the write landed (observed in
 * Agent-driven scene builds: `properties={"shape": {"size": {...}}}` on
 * CollisionShape2D silently dropping).
 *
 * The fix checks the node's *declared* property type up front (via
 * get_property_list()) rather than inferring failure from post-set()
 * equality, against a declared-type compatibility table
 * (`_PROPERTY_TYPE_COMPAT` in godot_operations.gd) that allows the
 * legitimate widening conversions Godot performs on store -- float->int,
 * String->NodePath/StringName, bool<->int/float, Vector2<->Vector2i,
 * Vector3<->Vector3i, Array->Packed*Array -- while rejecting everything
 * else. A non-Object value assigned to an Object-typed property (Resource
 * or Node) is rejected outright; a `res://` string assigned to an
 * Object-typed property is auto-loaded instead.
 *
 * Requires GODOT_PATH. Skipped in CI without it.
 */

import { describe, beforeAll, beforeEach, afterAll, expect } from 'vitest';
import { cpSync, rmSync, readFileSync, writeFileSync } from 'fs';
import { join } from 'path';
import { tmpdir } from 'os';
import { randomBytes } from 'crypto';
import { itGodot } from '../helpers/godot-skip.js';
import { fixtureProjectPath } from '../helpers/fixture-paths.js';
import { GodotRunner } from '../../src/utils/godot-runner.js';
import { extractJson } from '../../src/utils/output-parsing.js';

function makeTmpProject(): string {
  const id = randomBytes(6).toString('hex');
  const dst = join(tmpdir(), `godot-mcp-test-${id}`);
  cpSync(fixtureProjectPath, dst, { recursive: true });
  return dst;
}

const tmpDirs: string[] = [];

let runner: GodotRunner;

beforeAll(async () => {
  runner = new GodotRunner({ godotPath: process.env.GODOT_PATH });
  await runner.detectGodotPath();
});

beforeEach(() => {
  tmpDirs.push(makeTmpProject());
});

afterAll(() => {
  for (const dir of tmpDirs) {
    try {
      rmSync(dir, { recursive: true, force: true });
    } catch {
      // best-effort cleanup
    }
  }
});

describe('set_node_properties type validation (silent-success gap)', () => {
  itGodot(
    'errors when a dict value is assigned to a Resource-typed property (was silent success)',
    async () => {
      const tmpProject = tmpDirs[tmpDirs.length - 1];
      const scenePath = join(tmpProject, 'main.tscn');

      // Create a CollisionShape2D node to mutate.
      await runner.executeOperation(
        'add_node',
        {
          scenePath: 'main.tscn',
          nodeType: 'CollisionShape2D',
          nodeName: 'ShapeHolder',
          parentNodePath: '.',
        },
        tmpProject,
        30000,
      );

      // Attempt to set the `shape` property (Shape2D, a Resource) to a bare
      // dictionary — the classic silent-drop case from agent-driven builds.
      const { stdout } = await runner.executeOperation(
        'set_node_properties',
        {
          scenePath: 'main.tscn',
          updates: [{ nodePath: 'ShapeHolder', property: 'shape', value: { x: 100, y: 50 } }],
        },
        tmpProject,
        30000,
      );

      const parsed = JSON.parse(extractJson(stdout));
      expect(parsed.results[0].error).toMatch(/cannot|fail|invalid|mismatch|type/i);
      expect(parsed.results[0].success).toBeUndefined();
      // And nothing was persisted for this property.
      const sceneText = readFileSync(scenePath, 'utf-8');
      expect(sceneText).not.toMatch(/shape\s*=/);
    },
    60000,
  );

  itGodot(
    'still succeeds for valid Vector dict values (no regression)',
    async () => {
      const tmpProject = tmpDirs[tmpDirs.length - 1];
      const scenePath = join(tmpProject, 'main.tscn');

      const { stdout } = await runner.executeOperation(
        'set_node_properties',
        {
          scenePath: 'main.tscn',
          updates: [{ nodePath: '.', property: 'position', value: { x: 10, y: 20 } }],
        },
        tmpProject,
        30000,
      );

      const parsed = JSON.parse(extractJson(stdout));
      expect(parsed.results[0].success).toBe(true);
      const sceneText = readFileSync(scenePath, 'utf-8');
      expect(sceneText).toContain('position = Vector2(10, 20)');
    },
    60000,
  );

  itGodot(
    'still succeeds for an int property (z_index) and persists the int value',
    async () => {
      const tmpProject = tmpDirs[tmpDirs.length - 1];
      const scenePath = join(tmpProject, 'main.tscn');

      const { stdout } = await runner.executeOperation(
        'set_node_properties',
        {
          scenePath: 'main.tscn',
          updates: [{ nodePath: '.', property: 'z_index', value: 3 }],
        },
        tmpProject,
        30000,
      );

      const parsed = JSON.parse(extractJson(stdout));
      expect(parsed.results[0].success).toBe(true);
      const sceneText = readFileSync(scenePath, 'utf-8');
      expect(sceneText).toContain('z_index = 3');
    },
    60000,
  );

  itGodot(
    'still succeeds for a NodePath property (remote_path) from a plain string',
    async () => {
      const tmpProject = tmpDirs[tmpDirs.length - 1];
      const scenePath = join(tmpProject, 'main.tscn');

      await runner.executeOperation(
        'add_node',
        {
          scenePath: 'main.tscn',
          nodeType: 'RemoteTransform2D',
          nodeName: 'Remote',
          parentNodePath: '.',
        },
        tmpProject,
        30000,
      );

      const { stdout } = await runner.executeOperation(
        'set_node_properties',
        {
          scenePath: 'main.tscn',
          updates: [{ nodePath: 'Remote', property: 'remote_path', value: '../Label' }],
        },
        tmpProject,
        30000,
      );

      const parsed = JSON.parse(extractJson(stdout));
      expect(parsed.results[0].success).toBe(true);
      const sceneText = readFileSync(scenePath, 'utf-8');
      expect(sceneText).toContain('remote_path = NodePath("../Label")');
    },
    60000,
  );

  itGodot(
    'still succeeds for a StringName property (theme_type_variation) from a plain string',
    async () => {
      const tmpProject = tmpDirs[tmpDirs.length - 1];
      const scenePath = join(tmpProject, 'main.tscn');

      const { stdout } = await runner.executeOperation(
        'set_node_properties',
        {
          scenePath: 'main.tscn',
          updates: [{ nodePath: 'Label', property: 'theme_type_variation', value: 'HeaderLarge' }],
        },
        tmpProject,
        30000,
      );

      const parsed = JSON.parse(extractJson(stdout));
      expect(parsed.results[0].success).toBe(true);
      const sceneText = readFileSync(scenePath, 'utf-8');
      expect(sceneText).toContain('theme_type_variation = &"HeaderLarge"');
    },
    60000,
  );

  itGodot(
    'allows null to clear an Object-typed property',
    async () => {
      const tmpProject = tmpDirs[tmpDirs.length - 1];

      await runner.executeOperation(
        'add_node',
        {
          scenePath: 'main.tscn',
          nodeType: 'CollisionShape2D',
          nodeName: 'ClearShape',
          parentNodePath: '.',
        },
        tmpProject,
        30000,
      );

      const { stdout } = await runner.executeOperation(
        'set_node_properties',
        {
          scenePath: 'main.tscn',
          updates: [{ nodePath: 'ClearShape', property: 'shape', value: null }],
        },
        tmpProject,
        30000,
      );

      const parsed = JSON.parse(extractJson(stdout));
      expect(parsed.results[0].success).toBe(true);
    },
    60000,
  );

  itGodot(
    'auto-loads a res:// path assigned to an Object-typed property and persists it as an ExtResource',
    async () => {
      const tmpProject = tmpDirs[tmpDirs.length - 1];
      const scenePath = join(tmpProject, 'main.tscn');

      writeFileSync(
        join(tmpProject, 'shape.tres'),
        '[gd_resource type="RectangleShape2D" format=3]\n\n[resource]\nsize = Vector2(4, 4)\n',
        'utf-8',
      );

      await runner.executeOperation(
        'add_node',
        {
          scenePath: 'main.tscn',
          nodeType: 'CollisionShape2D',
          nodeName: 'LoadedShape',
          parentNodePath: '.',
        },
        tmpProject,
        30000,
      );

      const { stdout } = await runner.executeOperation(
        'set_node_properties',
        {
          scenePath: 'main.tscn',
          updates: [{ nodePath: 'LoadedShape', property: 'shape', value: 'res://shape.tres' }],
        },
        tmpProject,
        30000,
      );

      const parsed = JSON.parse(extractJson(stdout));
      expect(parsed.results[0].success).toBe(true);
      const sceneText = readFileSync(scenePath, 'utf-8');
      expect(sceneText).toMatch(/ext_resource type="Shape2D" path="res:\/\/shape\.tres"/);
      expect(sceneText).toMatch(/shape = ExtResource\(/);
    },
    60000,
  );

  itGodot(
    'errors when a res:// path does not exist',
    async () => {
      const tmpProject = tmpDirs[tmpDirs.length - 1];

      await runner.executeOperation(
        'add_node',
        {
          scenePath: 'main.tscn',
          nodeType: 'CollisionShape2D',
          nodeName: 'MissingShape',
          parentNodePath: '.',
        },
        tmpProject,
        30000,
      );

      const { stdout } = await runner.executeOperation(
        'set_node_properties',
        {
          scenePath: 'main.tscn',
          updates: [
            { nodePath: 'MissingShape', property: 'shape', value: 'res://does-not-exist.tres' },
          ],
        },
        tmpProject,
        30000,
      );

      const parsed = JSON.parse(extractJson(stdout));
      expect(parsed.results[0].success).toBeUndefined();
      expect(parsed.results[0].error).toMatch(/failed to load resource/i);
    },
    60000,
  );

  itGodot(
    'errors when a String is assigned to an int property (z_index) and does not persist',
    async () => {
      const tmpProject = tmpDirs[tmpDirs.length - 1];
      const scenePath = join(tmpProject, 'main.tscn');
      const originalTscn = readFileSync(scenePath, 'utf-8');

      const { stdout } = await runner.executeOperation(
        'set_node_properties',
        {
          scenePath: 'main.tscn',
          updates: [{ nodePath: '.', property: 'z_index', value: 'abc' }],
        },
        tmpProject,
        30000,
      );

      const parsed = JSON.parse(extractJson(stdout));
      expect(parsed.results[0].success).toBeUndefined();
      expect(parsed.results[0].error).toMatch(/int/i);
      expect(parsed.results[0].error).toMatch(/String/);
      const sceneText = readFileSync(scenePath, 'utf-8');
      expect(sceneText).toBe(originalTscn);
    },
    60000,
  );

  itGodot(
    'errors when a String is assigned to a Vector2 property (position) and does not persist',
    async () => {
      const tmpProject = tmpDirs[tmpDirs.length - 1];
      const scenePath = join(tmpProject, 'main.tscn');
      const originalTscn = readFileSync(scenePath, 'utf-8');

      const { stdout } = await runner.executeOperation(
        'set_node_properties',
        {
          scenePath: 'main.tscn',
          updates: [{ nodePath: '.', property: 'position', value: 'abc' }],
        },
        tmpProject,
        30000,
      );

      const parsed = JSON.parse(extractJson(stdout));
      expect(parsed.results[0].success).toBeUndefined();
      expect(parsed.results[0].error).toMatch(/cannot|expected|type/i);
      const sceneText = readFileSync(scenePath, 'utf-8');
      expect(sceneText).toBe(originalTscn);
    },
    60000,
  );

  itGodot(
    'still succeeds assigning a bool to an int property (z_index)',
    async () => {
      const tmpProject = tmpDirs[tmpDirs.length - 1];
      const scenePath = join(tmpProject, 'main.tscn');

      const { stdout } = await runner.executeOperation(
        'set_node_properties',
        {
          scenePath: 'main.tscn',
          updates: [{ nodePath: '.', property: 'z_index', value: true }],
        },
        tmpProject,
        30000,
      );

      const parsed = JSON.parse(extractJson(stdout));
      expect(parsed.results[0].success).toBe(true);
      const sceneText = readFileSync(scenePath, 'utf-8');
      expect(sceneText).toContain('z_index = 1');
    },
    60000,
  );

  itGodot(
    'errors when a res:// resource is the wrong type for the property',
    async () => {
      const tmpProject = tmpDirs[tmpDirs.length - 1];

      writeFileSync(
        join(tmpProject, 'shape.tres'),
        '[gd_resource type="RectangleShape2D" format=3]\n\n[resource]\nsize = Vector2(4, 4)\n',
        'utf-8',
      );

      await runner.executeOperation(
        'add_node',
        {
          scenePath: 'main.tscn',
          nodeType: 'Sprite2D',
          nodeName: 'MismatchedSprite',
          parentNodePath: '.',
        },
        tmpProject,
        30000,
      );

      const { stdout } = await runner.executeOperation(
        'set_node_properties',
        {
          scenePath: 'main.tscn',
          updates: [
            { nodePath: 'MismatchedSprite', property: 'texture', value: 'res://shape.tres' },
          ],
        },
        tmpProject,
        30000,
      );

      const parsed = JSON.parse(extractJson(stdout));
      expect(parsed.results[0].success).toBeUndefined();
      expect(parsed.results[0].error).toMatch(/RectangleShape2D/);
      expect(parsed.results[0].error).toMatch(/texture/);
    },
    60000,
  );
});

describe('add_node type validation (silent-success gap)', () => {
  itGodot(
    'errors and does not add the node when a plain value is given for an Object-typed property',
    async () => {
      const tmpProject = tmpDirs[tmpDirs.length - 1];
      const scenePath = join(tmpProject, 'main.tscn');
      const originalTscn = readFileSync(scenePath, 'utf-8');

      let stdoutSeen = '';
      let stderrSeen = '';
      try {
        const { stdout, stderr } = await runner.executeOperation(
          'add_node',
          {
            scenePath: 'main.tscn',
            nodeType: 'CollisionShape2D',
            nodeName: 'BadShape',
            properties: { shape: { x: 1, y: 2 } },
          },
          tmpProject,
          30000,
        );
        stdoutSeen = stdout || '';
        stderrSeen = stderr || '';
      } catch (err) {
        stderrSeen = err instanceof Error ? err.message : String(err);
      }

      expect(stdoutSeen).not.toContain('added successfully');
      expect(stderrSeen.toLowerCase()).toMatch(/object-typed|resource/);
      const tscnAfter = readFileSync(scenePath, 'utf-8');
      expect(tscnAfter).not.toMatch(/\[node name="BadShape"/);
      expect(tscnAfter).toBe(originalTscn);
    },
    60000,
  );

  itGodot(
    'errors and does not add the node when an unknown property is given',
    async () => {
      const tmpProject = tmpDirs[tmpDirs.length - 1];
      const scenePath = join(tmpProject, 'main.tscn');
      const originalTscn = readFileSync(scenePath, 'utf-8');

      let stdoutSeen = '';
      let stderrSeen = '';
      try {
        const { stdout, stderr } = await runner.executeOperation(
          'add_node',
          {
            scenePath: 'main.tscn',
            nodeType: 'CollisionShape2D',
            nodeName: 'UnknownProp',
            properties: { not_a_real_property: 5 },
          },
          tmpProject,
          30000,
        );
        stdoutSeen = stdout || '';
        stderrSeen = stderr || '';
      } catch (err) {
        stderrSeen = err instanceof Error ? err.message : String(err);
      }

      expect(stdoutSeen).not.toContain('added successfully');
      expect(stderrSeen.toLowerCase()).toMatch(/does not exist/);
      const tscnAfter = readFileSync(scenePath, 'utf-8');
      expect(tscnAfter).not.toMatch(/\[node name="UnknownProp"/);
      expect(tscnAfter).toBe(originalTscn);
    },
    60000,
  );

  itGodot(
    'errors and does not add the node when a String is given for an int property (z_index)',
    async () => {
      const tmpProject = tmpDirs[tmpDirs.length - 1];
      const scenePath = join(tmpProject, 'main.tscn');
      const originalTscn = readFileSync(scenePath, 'utf-8');

      let stdoutSeen = '';
      let stderrSeen = '';
      try {
        const { stdout, stderr } = await runner.executeOperation(
          'add_node',
          {
            scenePath: 'main.tscn',
            nodeType: 'Node2D',
            nodeName: 'BadZIndex',
            properties: { z_index: 'abc' },
          },
          tmpProject,
          30000,
        );
        stdoutSeen = stdout || '';
        stderrSeen = stderr || '';
      } catch (err) {
        stderrSeen = err instanceof Error ? err.message : String(err);
      }

      expect(stdoutSeen).not.toContain('added successfully');
      expect(stderrSeen.toLowerCase()).toMatch(/int/);
      const tscnAfter = readFileSync(scenePath, 'utf-8');
      expect(tscnAfter).not.toMatch(/\[node name="BadZIndex"/);
      expect(tscnAfter).toBe(originalTscn);
    },
    60000,
  );
});

describe('set_node_properties type validation against a scripted node', () => {
  itGodot(
    'errors when a String is assigned to a script-declared int property, succeeds for an untyped one',
    async () => {
      const tmpProject = tmpDirs[tmpDirs.length - 1];

      writeFileSync(
        join(tmpProject, 'typed.gd'),
        'extends Node2D\n@export var speed: int = 1\nvar anything\n',
        'utf-8',
      );

      const attachResult = await runner.executeOperation(
        'attach_script',
        { scenePath: 'main.tscn', nodePath: '.', scriptPath: 'typed.gd' },
        tmpProject,
        30000,
      );
      expect(JSON.parse(extractJson(attachResult.stdout)).success).toBe(true);

      const { stdout: speedStdout } = await runner.executeOperation(
        'set_node_properties',
        {
          scenePath: 'main.tscn',
          updates: [{ nodePath: '.', property: 'speed', value: 'fast' }],
        },
        tmpProject,
        30000,
      );
      const speedResult = JSON.parse(extractJson(speedStdout));
      expect(speedResult.results[0].success).toBeUndefined();
      expect(speedResult.results[0].error).toMatch(/int/i);

      const { stdout: anythingStdout } = await runner.executeOperation(
        'set_node_properties',
        {
          scenePath: 'main.tscn',
          updates: [{ nodePath: '.', property: 'anything', value: { a: 1 } }],
        },
        tmpProject,
        30000,
      );
      const anythingResult = JSON.parse(extractJson(anythingStdout));
      expect(anythingResult.results[0].success).toBe(true);
    },
    60000,
  );
});
