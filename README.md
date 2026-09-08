# Hop Bunny, Hop

A first-person 3D game prototype built in **Godot 4.7** with **Forward Plus** rendering and **Jolt Physics**.

## What's Been Done

### Player Character
- **First-person controller** (`scripts/proto_controller.gd`) based on Brackeys' prototype controller (CC0)
  - WASD movement with configurable speeds
  - Mouse-look with clamped vertical rotation
  - Jump with gravity
  - Sprint (shift)
  - Freefly/noclip mode (F key)
  - Mouse capture/release (left click / escape)
  - Configurable input mappings with validation
- **Ragdoll system** (`scripts/ragdoll.gd`)
  - Toggle ragdoll on/off (R key)
  - Integrates with `PhysicalBoneSimulator3D`
  - Stops animation and zeroes bone/physics velocity before simulation to prevent freezing/sliding
  - Resumes animation on disable
- **Player scene** (`characters/palayable/player.tscn`)
  - Chester the Rabbit model with looping idle animation
  - Animated skeleton with 26 bone skin
  - Convex collision shape for the body
  - Multiple capsule colliders for limbs (ragdoll)

### Dunes Map
- **Main scene** (`Maps/Dunes/dunes.scn`)
- **Custom terrain shaders**
  - `dunes.gdshader` - low-poly terrain shading
  - `dune_gust_fog.gdshader` - localized sand gust fog volume shader
- **Sand gust system** (`scripts/sand_gust.gd`, `scripts/sand_gust_manager.gd`)
  - `SandGust` nodes combine a `FogVolume` with procedural sand-colored fog and `GPUParticles3D` sand grains
  - `SandGustManager` spawns gusts on a timer with randomized position, speed, lifetime, and wind direction
  - Gusts move through the level and are reused after they expire
- **Environment** (`sandstorm_environment.tres`)
  - Global fog disabled in favor of localized gust volumes
  - Warm sand-colored lighting

### Assets
- **Animal model pack** (`asset/model1/`)
  - Chester the Rabbit, Clyde the Frog, Hazel the Deer, Ziggy the Wolf, Una the Cow, Felix the Cow, Barney the Songbird, Juniper the Pig, Maple the Cat, Ollie the Terrier
  - Each with GLB models and sprite previews
- **Dune challenge assets** (`asset/duneChallenge/`)
  - Low-poly cactus/hipo model with full PBR texture set

### Plugins & Tools
- **LowPolyTerrain** (`addons/lowpolyterrain/`) - terrain generation, painting, and mesh building tools with custom shaders
- **Godot AI / MCP** (`addons/godot_ai/`) - MCP dock integration, game helper, vision routing, and telemetry utilities

### Engine Configuration
- **Physics**: Jolt Physics
- **Rendering**: Forward Plus with D3D12 on Windows
- **Input**: Canvas items stretch mode with expand aspect
- **Autoload**: `_mcp_game_helper` for AI integration

## Controls
| Key | Action |
|-----|--------|
| WASD | Move |
| Space | Jump |
| Shift | Sprint |
| F | Toggle freefly |
| R | Toggle ragdoll |
| Left Click | Capture mouse |
| Escape | Release mouse |
