# Cactus Knockback Obstacle Plan

## Goal

Add one playable cactus obstacle to the dunes map. Contact knocks the player away, triggers a short ragdoll, and then automatically restores normal movement. The obstacle must be tunable, repeat-safe, and safe to test without a health system.

## Scope

### Included

- Reuse `Maps/Dunes/dune_obstacle_1.tscn` and its existing cactus mesh, capsule collision, and `pushZone` Area3D.
- Add cactus hit behavior and feedback.
- Add a controller-owned hit API that coordinates knockback and ragdoll safely.
- Place one visible, dodgeable cactus on a side route in the dunes map.
- Validate normal movement, hit cooldown, ragdoll recovery, and freefly bypass.

### Explicitly out of scope

- Rolling sand boulder.
- Quicksand.
- Health, damage, death, or UI.
- Cactus clusters or multiple placements.
- Camera shake or screen flash.
- Changes to terrain generation, input mappings, or the core ragdoll feature beyond recovery safety.

## Existing Context

- `Maps/Dunes/dune_obstacle_1.tscn` already contains:
  - `duneObstacle1` root.
  - `cacto_hipopo_LP/texture_pbr_v1` visual mesh.
  - `pushZone` Area3D with a capsule shape.
  - No behavior script on `pushZone`.
- `scripts/proto_controller.gd` owns player movement, sprint/freefly state, and the `Ragdoll` reference.
- `scripts/ragdoll.gd` already exposes `enable_ragdoll()`, `disable_ragdoll()`, and `toggle_ragdoll()`.
- The project uses Godot 4.7 and Jolt Physics.
- Player collision layer is 2. The cactus trigger should use a separate obstacle layer and mask player layer 2.

## Resolved Decisions

1. **First milestone:** cactus only. Boulder and quicksand remain future plans.
2. **Hit response:** directional knockback plus temporary ragdoll.
3. **Recovery:** automatic after a configurable duration; resume where the ragdoll ends rather than teleporting to the pre-hit position.
4. **Trigger:** `body_entered`, with a per-player cooldown to prevent signal flicker or repeated hits.
5. **Freefly:** cactus has no effect while freefly/noclip is active.
6. **Tuning:** export force, upward pop, cooldown, and ragdoll duration in the Inspector.
7. **Feedback:** small sand/dust burst plus an optional sound hook.
8. **Placement:** one visible cactus on a side route with enough clearance to dodge.

## Implementation Tasks

### 1. Add a controller-owned cactus hit API

In `scripts/proto_controller.gd`:

- Add a non-reentrant method such as:

  ```gdscript
  func apply_cactus_hit(knockback: Vector3, ragdoll_duration: float = 1.2) -> void
  ```

- Guard the method against:
  - Freefly mode.
  - An already-active cactus hit or ragdoll state.
  - A null or unavailable `Ragdoll` reference.
- Coordinate the sequence through the controller:
  1. Stop normal input movement through the existing ragdoll enable path.
  2. Await `ragdoll.enable_ragdoll()` so physical bones are active before applying the impulse.
  3. Apply the knockback velocity, including the configured upward component.
  4. Wait for `ragdoll_duration`.
  5. Call `ragdoll.disable_ragdoll()`.
  6. Damp or clear residual velocity and restore controller state.
- Add a small public state query if needed, such as `is_freeflying()` or `can_accept_cactus_hit()`, so the cactus script does not inspect private controller fields.
- Keep the cactus script from directly toggling ragdoll or rewriting controller flags.

### 2. Make ragdoll recovery preserve the final position

Review `scripts/ragdoll.gd` as part of this task:

- Do not move the player root to the physical head bone during `disable_ragdoll()`.
- Preserve `player.global_transform` at recovery so the player resumes where the ragdoll ended.
- Restore the head/animation state without reintroducing the previous teleport behavior.
- Restore movement and jump flags to their pre-ragdoll values where practical.
- Add lifecycle guards around delayed recovery so a freed node cannot resume a timer callback.

This is required because the current recovery code stores a head-bone transform and assigns it to the player root, which is not the desired recovery contract.

### 3. Implement the cactus trigger

Create `scripts/cactus_knockback.gd` and attach it to `pushZone` in `Maps/Dunes/dune_obstacle_1.tscn`.

Suggested exported defaults:

```gdscript
@export var knockback_force: float = 14.0
@export var upward_force: float = 4.0
@export var cooldown: float = 1.0
@export var ragdoll_duration: float = 1.2
```

Behavior:

- On `body_entered`, accept only `CharacterBody3D` bodies that expose the controller hit API.
- Track cooldown per player instance ID, not as one global timestamp.
- Calculate horizontal direction away from the cactus:

  ```gdscript
  var direction := (body.global_position - global_position)
  direction.y = 0.0
  direction = direction.normalized()
  ```

- Fall back to the cactus forward direction if the player is exactly at the cactus origin.
- Call the controller method with `direction * knockback_force + Vector3.UP * upward_force`.
- Ignore freefly through the controller API.
- Set `pushZone` to an obstacle collision layer separate from the player and terrain, with a mask that includes player layer 2. Verify the final layer against existing physical-bone layers.

### 4. Add dust and optional audio feedback

In `dune_obstacle_1.tscn`:

- Add a small reusable `GPUParticles3D` dust burst under the cactus root or trigger node.
- Use sand-colored particles with a short lifetime and modest spread.
- Trigger the burst only on a successful hit.
- Add an optional `AudioStreamPlayer3D` and exported sound resource if a suitable impact asset is available; absence of audio must not block the obstacle.

### 5. Place one cactus in the dunes map

In `Maps/Dunes/dunes.scn`:

- Instance `res://Maps/Dunes/dune_obstacle_1.tscn` once.
- Place it beside, not directly across, the main route.
- Keep the visual mesh and trigger capsule aligned with the terrain.
- Leave a clear bypass so the first test cannot soft-lock the player.
- Rotate the cactus so its hazard direction is readable from the approach path.

### 6. Tune and validate

Use the Inspector defaults above as the starting point, then playtest:

- Walking or sprinting into the cactus produces one knockback and one ragdoll.
- The player recovers automatically after the configured duration.
- Recovery keeps the player at the ragdoll’s final position.
- Re-entering immediately does not retrigger before the cooldown expires.
- Freefly passes through without knockback or ragdoll.
- The cactus does not trap the player against terrain or repeatedly trigger while sliding along the capsule.
- Dust feedback appears without persistent particles or runtime errors.
- No input, animation, physics, or scene-tree errors appear in the Godot debugger.

## Data Flow

```text
pushZone.body_entered
  -> CactusKnockback validates body and per-player cooldown
  -> ProtoController.apply_cactus_hit()
  -> Ragdoll.enable_ragdoll()
  -> apply knockback velocity after physics simulation starts
  -> wait ragdoll_duration
  -> Ragdoll.disable_ragdoll()
  -> restore controller state at final physical position
```

## Risks and Mitigations

- **Ragdoll recovery teleport:** remove the head-bone-to-player-root assignment and preserve the root transform.
- **Knockback lost during ragdoll startup:** await ragdoll activation before assigning velocity.
- **Repeated Area3D signals:** use per-player cooldown tracking.
- **Player soft-lock:** use temporary recovery, a dodgeable placement, and a terrain clearance check.
- **Visual/collision mismatch:** verify the imported mesh scale and capsule bounds in the editor.
- **Jolt-specific behavior:** test impulse and recovery in the actual project physics engine rather than assuming Godot’s default physics behavior.
- **Future obstacles:** keep the controller hit API generic enough to reuse for a boulder, but do not implement boulder or quicksand in this milestone.

## Future Handoff

After this cactus milestone is validated, the next plans can reuse:

- The controller-owned hit API for boulder impacts.
- The Area3D enter/exit pattern for quicksand.
- The dust feedback scene for sand-based effects.
