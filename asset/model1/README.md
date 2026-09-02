# Plumberry Plains Vol. 1

Cozy chibi animal character(s) with baked-in animation clips. Game-ready and mobile-ready: optimized triangle/texture budgets, one material per part, no skin weights, all clips embedded and in-place.

Animations per character: 26 (26 everyday clips). Exact per-character clip lists below; the full file listing is in CONTENTS.md.

- Formats: glTF 2.0 binary (.glb) plus engine-portable exports per critter under exports/<critter>/:
  - <critter>.fbx (mesh + rig) and <critter>@<clip>.fbx per animation (Unity's model@clip convention; Unreal imports them as animation files; textures embedded)
  - <critter>.obj / .mtl with copied textures (static rest pose)
- Units: meters, glTF Y-up
- Rig: GTB cozy critter skeleton (transform-node animation, rigid part attachment — import as Generic rig in Unity)
- Bone names: root, hips, spine, chest, upper_chest, neck, head, shoulder_l/r, arm_l/r, leg_l/r, tail_01, tail_02. Mesh nodes use a _geo suffix (head_geo, body_geo, arm_l_geo, ...), one material per part (critter_head, critter_body, ...).
- UVs: each part mesh carries exactly one UV set (glTF TEXCOORD_0; named "UVMap" in the FBX/OBJ exports) with its own baked base-color texture. FBX animation takes are named after their clips.
- Godot: import the .glb directly (native glTF, all clips included)
- Textures: baked base-color albedo per part (engine lighting/toon shading friendly)
- Prop sockets: empty transform nodes for attaching items — socket_hand_l / socket_hand_r (inside each mitten paw, for held props like tools, food, or lanterns), socket_head (on the crown, for hats), socket_back (rear torso surface, for backpacks, wings, or capes), and socket_chest (front torso surface, for medallions, bibs, or badges). Parent your prop to the socket node and it follows every animation. In Unity find them in the imported hierarchy; in Godot use BoneAttachment3D or the node path; in Unreal attach to the imported socket node or convert it to a skeletal socket.

## barney-the-songbird

- Height: ~0.95 m
- Triangles: 13198
- Parts: head, body, arm_l, arm_r, leg_l, leg_r, tail
- Everyday clips: walk (loop), run (loop), sit (loop), sit_talk (loop), interact, idle (loop), talk (loop), dance (loop), pickup, jump, no, yes, pain, fall_over, wave (loop), cheer (loop), crying (loop), celebrate, axe_chop (loop), hammer (loop), fish_cast, fish_reel (loop), stick_swing (loop), paint (loop), uppercut, shadow_box (loop)
- Prop sockets: socket_hand_l (on arm_l), socket_hand_r (on arm_r), socket_head (on head), socket_back (on spine), socket_chest (on spine)

## chester-the-rabbit

- Height: ~0.95 m
- Triangles: 13663
- Parts: head, body, neckwear, arm_l, arm_r, leg_l, leg_r, tail
- Everyday clips: walk (loop), run (loop), sit (loop), sit_talk (loop), interact, idle (loop), talk (loop), dance (loop), pickup, jump, no, yes, pain, fall_over, wave (loop), cheer (loop), crying (loop), celebrate, axe_chop (loop), hammer (loop), fish_cast, fish_reel (loop), stick_swing (loop), paint (loop), uppercut, shadow_box (loop)
- Prop sockets: socket_hand_l (on arm_l), socket_hand_r (on arm_r), socket_head (on head), socket_back (on spine), socket_chest (on spine)

## clyde-the-frog

- Height: ~0.95 m
- Triangles: 13675
- Parts: head, body, neckwear, arm_l, arm_r, leg_l, leg_r, tail
- Everyday clips: walk (loop), run (loop), sit (loop), sit_talk (loop), interact, idle (loop), talk (loop), dance (loop), pickup, jump, no, yes, pain, fall_over, wave (loop), cheer (loop), crying (loop), celebrate, axe_chop (loop), hammer (loop), fish_cast, fish_reel (loop), stick_swing (loop), paint (loop), uppercut, shadow_box (loop)
- Prop sockets: socket_hand_l (on arm_l), socket_hand_r (on arm_r), socket_head (on head), socket_back (on spine), socket_chest (on spine)

## felix-the-cow

- Height: ~0.95 m
- Triangles: 13678
- Parts: head, body, neckwear, arm_l, arm_r, leg_l, leg_r, tail
- Everyday clips: walk (loop), run (loop), sit (loop), sit_talk (loop), interact, idle (loop), talk (loop), dance (loop), pickup, jump, no, yes, pain, fall_over, wave (loop), cheer (loop), crying (loop), celebrate, axe_chop (loop), hammer (loop), fish_cast, fish_reel (loop), stick_swing (loop), paint (loop), uppercut, shadow_box (loop)
- Prop sockets: socket_hand_l (on arm_l), socket_hand_r (on arm_r), socket_head (on head), socket_back (on spine), socket_chest (on spine)

## maple-the-cat

- Height: ~0.95 m
- Triangles: 13195
- Parts: head, body, arm_l, arm_r, leg_l, leg_r, tail
- Everyday clips: walk (loop), run (loop), sit (loop), sit_talk (loop), interact, idle (loop), talk (loop), dance (loop), pickup, jump, no, yes, pain, fall_over, wave (loop), cheer (loop), crying (loop), celebrate, axe_chop (loop), hammer (loop), fish_cast, fish_reel (loop), stick_swing (loop), paint (loop), uppercut, shadow_box (loop)
- Prop sockets: socket_hand_l (on arm_l), socket_hand_r (on arm_r), socket_head (on head), socket_back (on spine), socket_chest (on spine)

## juniper-the-pig

- Height: ~0.95 m
- Triangles: 13679
- Parts: head, body, neckwear, arm_l, arm_r, leg_l, leg_r, tail
- Everyday clips: walk (loop), run (loop), sit (loop), sit_talk (loop), interact, idle (loop), talk (loop), dance (loop), pickup, jump, no, yes, pain, fall_over, wave (loop), cheer (loop), crying (loop), celebrate, axe_chop (loop), hammer (loop), fish_cast, fish_reel (loop), stick_swing (loop), paint (loop), uppercut, shadow_box (loop)
- Prop sockets: socket_hand_l (on arm_l), socket_hand_r (on arm_r), socket_head (on head), socket_back (on spine), socket_chest (on spine)

## hazel-the-deer

- Height: ~0.95 m
- Triangles: 13679
- Parts: head, body, neckwear, arm_l, arm_r, leg_l, leg_r, tail
- Everyday clips: walk (loop), run (loop), sit (loop), sit_talk (loop), interact, idle (loop), talk (loop), dance (loop), pickup, jump, no, yes, pain, fall_over, wave (loop), cheer (loop), crying (loop), celebrate, axe_chop (loop), hammer (loop), fish_cast, fish_reel (loop), stick_swing (loop), paint (loop), uppercut, shadow_box (loop)
- Prop sockets: socket_hand_l (on arm_l), socket_hand_r (on arm_r), socket_head (on head), socket_back (on spine), socket_chest (on spine)

## ollie-the-terrier

- Height: ~0.95 m
- Triangles: 13674
- Parts: head, body, neckwear, arm_l, arm_r, leg_l, leg_r, tail
- Everyday clips: walk (loop), run (loop), sit (loop), sit_talk (loop), interact, idle (loop), talk (loop), dance (loop), pickup, jump, no, yes, pain, fall_over, wave (loop), cheer (loop), crying (loop), celebrate, axe_chop (loop), hammer (loop), fish_cast, fish_reel (loop), stick_swing (loop), paint (loop), uppercut, shadow_box (loop)
- Prop sockets: socket_hand_l (on arm_l), socket_hand_r (on arm_r), socket_head (on head), socket_back (on spine), socket_chest (on spine)

## una-the-cow

- Height: ~0.95 m
- Triangles: 13674
- Parts: head, body, neckwear, arm_l, arm_r, leg_l, leg_r, tail
- Everyday clips: walk (loop), run (loop), sit (loop), sit_talk (loop), interact, idle (loop), talk (loop), dance (loop), pickup, jump, no, yes, pain, fall_over, wave (loop), cheer (loop), crying (loop), celebrate, axe_chop (loop), hammer (loop), fish_cast, fish_reel (loop), stick_swing (loop), paint (loop), uppercut, shadow_box (loop)
- Prop sockets: socket_hand_l (on arm_l), socket_hand_r (on arm_r), socket_head (on head), socket_back (on spine), socket_chest (on spine)

## ziggy-the-wolf

- Height: ~0.95 m
- Triangles: 13195
- Parts: head, body, arm_l, arm_r, leg_l, leg_r, tail
- Everyday clips: walk (loop), run (loop), sit (loop), sit_talk (loop), interact, idle (loop), talk (loop), dance (loop), pickup, jump, no, yes, pain, fall_over, wave (loop), cheer (loop), crying (loop), celebrate, axe_chop (loop), hammer (loop), fish_cast, fish_reel (loop), stick_swing (loop), paint (loop), uppercut, shadow_box (loop)
- Prop sockets: socket_hand_l (on arm_l), socket_hand_r (on arm_r), socket_head (on head), socket_back (on spine), socket_chest (on spine)

## License

Free to use in unlimited personal and commercial projects (games, apps, animations, videos). You may NOT resell, redistribute, or repackage the raw asset files, mint them as NFTs, or use them to train AI models. Full terms in TERMS.md.
