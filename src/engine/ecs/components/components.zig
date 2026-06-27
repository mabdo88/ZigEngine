const std = @import("std");
const Entity = @import("../entity/entity.zig").Entity;
const clip_mod = @import("../../../animation/clip.zig");
const Uuid = @import("../../uuid.zig").Uuid;

pub fn ComponentBit(comptime T: type) u64 {
    inline for (AllComponents, 0..) |C, i| {
        if (C == T) return @as(u64, 1) << @intCast(i);
    }
    @compileError("Unregistered component type: " ++ @typeName(T));
}

pub fn ComponentIndex(comptime T: type) comptime_int {
    inline for (AllComponents, 0..) |C, i| {
        if (C == T) return i;
    }
    @compileError("Unregistered component type: " ++ @typeName(T));
}

pub const AllComponents = .{
    MeshComponent,
    TransformComponent,
    BakedTransformComponent,
    CameraComponent,
    MaterialComponent,
    SceneComponent,
    SceneActiveTag,
    ScenePendingTag,
    SceneLoadingTag,
    SceneOwnedComponent,
    CameraMatricesComponent,
    TextureDataComponent,
    FinalTransformComponent,
    ParentComponent,
    SkeletonComponent,
    AnimPlayerComponent,
    PoseBufferComponent,
    JointWorldComponent,
    SkinPaletteComponent,
    PhysicsBodyComponent,
    CharacterControllerComponent,
    TriggerWatcherComponent,
    UuidComponent,
    PrefabInstanceComponent,
    SpawnPointComponent,
    SpawnedByComponent,
    AudioSourceComponent,
    HealthComponent,
    PlayerMovementComponent,
    MeleeAttackComponent,
    AbilitySlotsComponent,
    InventoryComponent,
    PickupComponent,
    AIComponent,
    ProjectileComponent,
};

pub const MeshComponent = struct {
    mesh_id: u32,

    pub fn isValid(_: MeshComponent) bool {
        return true;
    }
};

pub const Vertex = struct {
    pos: @Vector(3, f32),
    normal: @Vector(3, f32),
    uv: @Vector(2, f32),
    /// Defaults route every unskinned vertex through skin matrix slot 0,
    /// which the renderer always keeps as identity (see
    /// zVulkanContext.SKIN_IDENTITY_SLOT) — full weight on a joint that does
    /// nothing leaves the vertex exactly where it already was, so unskinned
    /// meshes don't need a separate shader/pipeline path.
    joints: @Vector(4, u32) = .{ 0, 0, 0, 0 },
    weights: @Vector(4, f32) = .{ 1, 0, 0, 0 },
};

pub const TransformComponent = struct {
    position: @Vector(3, f32),
    rotation: @Vector(3, f32),
    scale: @Vector(3, f32),
};

pub const BakedTransformComponent = struct {
    matrix: [4][4]f32,
};

/// world = BakedTransformComponent.matrix * transformToMatrix(TransformComponent),
/// recomputed every frame by TransformSystem. Renderers (and any future
/// system) read this instead of redoing the matMul themselves.
pub const FinalTransformComponent = struct {
    matrix: [4][4]f32,
};

/// Presence means this entity's FinalTransformComponent should be
/// concatenated under `parent`'s, by HierarchySystem. Absence means the
/// entity is a root — its FinalTransformComponent is already a world matrix.
pub const ParentComponent = struct {
    parent: Entity,
};

pub const CameraComponent = struct {
    position: @Vector(3, f32) = .{ 0.0, 0.0, 5.0 },
    target: @Vector(3, f32) = .{ 0.0, 0.0, 0.0 },
    up: @Vector(3, f32) = .{ 0.0, 1.0, 0.0 },
    fov: f32 = std.math.degreesToRadians(45.0),
    near: f32 = 0.1,
    far: f32 = 10000.0,
};

pub const MaterialComponent = struct {
    material_index: u32,
};

pub const SceneComponent = struct {
    name: []const u8,
    path: [:0]const u8,
    index: u32 = 0,
    camera_position: @Vector(3, f32) = .{ 0.0, 0.5, 3.0 },
    camera_target: @Vector(3, f32) = .{ 0.0, 0.5, 0.0 },
    offset: @Vector(3, f32) = .{ 0.0, 0.0, 0.0 },
    rotates: bool = false,
};

pub const SceneActiveTag = struct {};

pub const ScenePendingTag = struct {};

pub const SceneLoadingTag = struct {};

pub const SceneOwnedComponent = struct {
    owner: Entity,
};

pub const CameraMatricesComponent = struct {
    view: [4][4]f32,
    proj: [4][4]f32,
};

pub const TextureDataComponent = struct {
    material_id: u32,
    pixels: []u8 = &.{},
    width: u32 = 0,
    height: u32 = 0,

    pub fn deinit(self: TextureDataComponent, allocator: std.mem.Allocator) void {
        if (self.pixels.len > 0) allocator.free(self.pixels);
    }
};

/// Index into Registry.skeleton_cache — the skeleton itself is asset data
/// shared across instances, not owned per-entity.
pub const SkeletonComponent = struct {
    skeleton_id: u32,
};

/// Index into Registry.clip_cache, plus per-entity playback state.
pub const AnimPlayerComponent = struct {
    clip_id: u32,
    time: f32 = 0,
    speed: f32 = 1.0,
    loop: bool = true,
};

/// Per-entity local joint pose, sampled from the clip each frame by
/// AnimPlayerSystem. Sized to the skeleton's joint_count at spawn time.
pub const PoseBufferComponent = struct {
    poses: []clip_mod.JointPose,

    pub fn deinit(self: PoseBufferComponent, allocator: std.mem.Allocator) void {
        allocator.free(self.poses);
    }
};

/// Per-entity world-space joint transforms, recomputed each frame by
/// AnimPlayerSystem from PoseBufferComponent. Joint i's world position is
/// matrices[i]'s translation column — used for debug-drawing the skeleton
/// (render_system.zig's drawSkeletons), *not* for GPU skinning (see
/// SkinPaletteComponent for that — a world transform alone doesn't account
/// for each joint's inverse bind matrix, so it would deform the mesh wrong).
pub const JointWorldComponent = struct {
    matrices: [][4][4]f32,

    pub fn deinit(self: JointWorldComponent, allocator: std.mem.Allocator) void {
        allocator.free(self.matrices);
    }
};

/// Per-entity GPU skin matrices (skin[i] = world[i] * inverse_bind[i]),
/// recomputed each frame by AnimPlayerSystem alongside JointWorldComponent.
/// renderSystem.zig (the GPU-facing one, not this ECS one) uploads these
/// into the current frame's region of the skin matrix buffer each draw.
pub const SkinPaletteComponent = struct {
    matrices: [][4][4]f32,

    pub fn deinit(self: SkinPaletteComponent, allocator: std.mem.Allocator) void {
        allocator.free(self.matrices);
    }
};

/// A live Jolt rigid body. body_id is the BodyID Jolt handed back from
/// jolt_add_box (an index+sequence pair packed into one u32, see BodyID in
/// jolt_wrapper.cpp) — opaque to Zig beyond round-tripping it through the
/// wrapper. is_static bodies are skipped by PhysicsSyncSystem's writeback
/// (they never move, and Static motion type can't be activated anyway).
/// Same caveat as CharacterControllerComponent: freeing the Jolt body needs
/// the JoltCtx, which the generic component-deinit hook doesn't have access
/// to — call physics_world.despawnBody() before destroying the entity.
pub const PhysicsBodyComponent = struct {
    body_id: u32,
    is_static: bool,
};

/// A live Jolt CharacterVirtual, addressed by an opaque handle (not a
/// BodyID — CharacterVirtual is a kinematic controller, not a rigid body,
/// see character_controller.zig). Registry's generic component-deinit hook
/// only gets an allocator, not the JoltCtx this handle needs to be freed
/// through — so cleanup can't be automatic here. Callers must explicitly
/// call character_controller.despawnCharacter() before destroying the
/// entity, or the underlying CharacterVirtual leaks.
pub const CharacterControllerComponent = struct {
    handle: *anyopaque,
};

/// Marks an entity as a sensor (trigger) volume so TriggerSystem polls Jolt's
/// trigger-event queue and re-emits it as TriggerEvent through the EventBus,
/// resolving Jolt body IDs back to entities via PhysicsBodyComponent.
pub const TriggerWatcherComponent = struct {};

/// Stable cross-session identity. Attached to any entity that scene save/load
/// needs to reference by identity rather than by transient {index, generation}
/// (which gets reassigned every run) — prefab instances and spawn points.
/// Entities spawned purely by the static glTF/OBJ scene pipeline don't need
/// one: SceneSystem reconstructs them deterministically from the scene file
/// on every load, so there's nothing to look up by id.
pub const UuidComponent = struct {
    id: Uuid,
};

/// Marks the root entity of a prefab instance and records which prefab
/// spawned it, by index into prefab.PrefabRegistry.defs (not by name — POD
/// components don't own strings, see CLAUDE.md's "Component data is POD"
/// rule). scene_save.zig resolves this back to a name via
/// PrefabRegistry.nameById() for the save file; scene_load.zig/spawner.zig
/// resolve a saved name back to an id via PrefabRegistry.idByName() before
/// re-instantiating.
pub const PrefabInstanceComponent = struct {
    prefab_id: u32,
};

/// A point in the world that periodically instantiates a prefab, up to
/// max_active concurrently-alive instances. timer accumulates dt in
/// spawner.zig's SpawnerSystem; active_count is decremented by that same
/// system's entity_destroyed handler when a SpawnedByComponent-tagged
/// instance dies, so it never needs to scan the registry to recount.
pub const SpawnPointComponent = struct {
    prefab_id: u32,
    cooldown: f32,
    max_active: u32,
    active_count: u32 = 0,
    timer: f32 = 0,
};

/// Marks a prefab instance as having been spawned by `spawner`, so
/// SpawnerSystem's death observer knows which SpawnPointComponent.active_count
/// to decrement when this entity is destroyed.
pub const SpawnedByComponent = struct {
    spawner: Entity,
};

/// POD only — clip_id indexes into audio/audio_shared.zig's AudioClipCache,
/// never a direct ma_sound pointer (component data can't own a C resource
/// directly, see PhysicsBodyComponent's body_id for the same pattern).
/// AudioSystem flips auto_play sounds to playing=true the first time it sees
/// them; toggling auto_play back off and on again does NOT replay the clip
/// (playing latches), since this is a "play once on spawn" flag, not a loop
/// control — repeat playback is audio_device.clipPlay called explicitly.
///
/// `spatialized` and rolloff/min_distance/max_distance are read by
/// Audio3DSystem (engine/ecs/systems/audio_3d_system.zig), not AudioSystem —
/// non-spatialized sources (the common case for UI/2D sound effects) are
/// explicitly told to ignore the listener position rather than just leaving
/// position at the origin, since ma_sound_init_from_file enables
/// spatialization by default.
pub const AudioSourceComponent = struct {
    clip_id: u32 = 0,
    volume: f32 = 1.0,
    auto_play: bool = false,
    playing: bool = false,
    spatialized: bool = false,
    rolloff: f32 = 1.0,
    min_distance: f32 = 1.0,
    max_distance: f32 = std.math.floatMax(f32),
};

/// current/max are f32 (not integers) so regen_per_sec*dt accumulates
/// fractionally instead of getting truncated away every frame.
/// `invincible` is a permanent flag (boss phases, debug); `invincible_timer`
/// is a temporary one (i-frames after a hit) — both gate damage in
/// gameplay/health.zig's onDamage, checked independently so neither
/// overwrites the other's intent. `iframe_duration` is how long a *surviving*
/// hit grants free i-frames for (0 = no auto i-frames on hit, the prior
/// default behavior) — onDamage sets invincible_timer = iframe_duration after
/// damage lands, so this is the configuration knob, invincible_timer is the
/// runtime countdown.
pub const HealthComponent = struct {
    current: f32,
    max: f32,
    regen_per_sec: f32 = 0,
    invincible: bool = false,
    invincible_timer: f32 = 0,
    iframe_duration: f32 = 0,
};

/// Drives a one-shot melee hitbox via jolt_overlap_sphere, attached to
/// whatever entity is doing the attacking (player or enemy — generic, not
/// player-specific). Gameplay code sets `trigger = true` to request an
/// attack on the next eligible frame; gameplay/combat.zig's MeleeAttackSystem
/// clears it back to false the instant it actually fires (whether or not
/// anything was hit) and resets cooldown_timer, so holding `trigger` true
/// doesn't spam attacks every frame. Hitbox center is the attacker's
/// TransformComponent position plus `range` along its facing (derived from
/// rotation.y, matching transformToMatrix's yaw convention) — not
/// camera-relative like PlayerMovementComponent, since enemies have no
/// camera to read from.
pub const MeleeAttackComponent = struct {
    range: f32 = 1.5,
    radius: f32 = 0.6,
    damage: f32 = 10.0,
    impulse: f32 = 5.0,
    cooldown: f32 = 0.6,
    cooldown_timer: f32 = 0,
    trigger: bool = false,
};

/// One ability bound to a slot — ability_id indexes gameplay/ability.zig's
/// AbilityRegistry (POD, same id-not-pointer pattern as PrefabInstanceComponent's
/// prefab_id), invalid_ability_id means the slot is empty. cooldown_timer is
/// per-slot runtime state, separate from AbilitySlotsComponent's single
/// shared cast_timer (one cast at a time, but each slot cools down
/// independently).
pub const invalid_ability_id: u32 = std.math.maxInt(u32);

pub const AbilitySlot = struct {
    ability_id: u32 = invalid_ability_id,
    cooldown_timer: f32 = 0,
};

/// One stack of an item — item_id indexes gameplay/item.zig's ItemRegistry
/// (same id-not-pointer pattern as AbilitySlot.ability_id), invalid_item_id
/// means the slot is empty. count is capped at the def's max_stack by
/// gameplay/item.zig's addItem, never by the component itself (POD, no
/// access to the registry to check against).
pub const invalid_item_id: u32 = std.math.maxInt(u32);

pub const ItemStack = struct {
    item_id: u32 = invalid_item_id,
    count: u32 = 0,
};

const empty_item_stacks: [20]ItemStack = blk: {
    var arr: [20]ItemStack = undefined;
    for (&arr) |*s| s.* = .{};
    break :blk arr;
};

/// `items[20]` are stackable consumables/materials; `relics[3]` are unique
/// passive items addressed directly by item_id (no count — relics aren't
/// stacked or consumed). `request_use_slot` is a one-shot request gameplay
/// code sets to ask for items[slot] to be used — gameplay/item.zig's
/// PickupSystem/ItemSystem consumes and clears it immediately, same pattern
/// MeleeAttackComponent.trigger and AbilitySlotsComponent.request_cast
/// already use. Not yet wired into scene_save.zig/scene_load.zig (M9's
/// Save/Load task is what will do that) — deliberately POD/id-based exactly
/// so that wiring is a small addition later, not a redesign.
pub const InventoryComponent = struct {
    items: [20]ItemStack = empty_item_stacks,
    relics: [3]u32 = .{ invalid_item_id, invalid_item_id, invalid_item_id },
    request_use_slot: ?u8 = null,
};

/// Marks a TriggerWatcherComponent entity as a world item pickup —
/// gameplay/item.zig's PickupSystem grants item_id/count to whichever
/// entity's InventoryComponent enters the trigger, then destroys this
/// entity (despawning its physics body first, same caveat
/// PhysicsBodyComponent's doc comment already notes).
pub const PickupComponent = struct {
    item_id: u32,
    count: u32 = 1,
};

/// patrol -> chase -> attack -> retreat, plus a terminal `dead` set by
/// gameplay/ai.zig's AISystem subscribing to `.death_event` (never entered by
/// the per-frame state logic itself). Basis for Knave boss behavior trees —
/// deliberately a flat per-state switch rather than a generic transition
/// table (unlike animation/state_machine.zig, which blends poses — a
/// different domain with different needs), so a boss can later override
/// individual states or add new ones without fighting a framework.
pub const AIState = enum {
    patrol,
    chase,
    attack,
    retreat,
    dead,
};

/// `patrol_points`/`patrol_count` are a fixed-size POD waypoint loop (no
/// allocator — same "no heap allocations inside component data" rule as
/// everything else). `target` is acquired by AISystem's sight scan (currently
/// "nearest PlayerMovementComponent entity in range with clear line of
/// sight" — there's no faction/threat-table system yet, so this is the one
/// stand-in target type until one exists). `retreat_health_fraction` is
/// checked every frame regardless of current state — health takes priority
/// over whatever combat state the AI was in.
pub const AIComponent = struct {
    state: AIState = .patrol,
    patrol_points: [4]@Vector(3, f32) = .{ .{ 0, 0, 0 }, .{ 0, 0, 0 }, .{ 0, 0, 0 }, .{ 0, 0, 0 } },
    patrol_count: u8 = 0,
    patrol_index: u8 = 0,
    patrol_speed: f32 = 2.0,
    chase_speed: f32 = 4.0,
    sight_range: f32 = 10.0,
    attack_range: f32 = 1.5,
    retreat_health_fraction: f32 = 0.2,
    target: ?Entity = null,
};

/// `owner` is excluded from its own first-hit check (gameplay/projectile.zig's
/// ProjectileSystem sweeps a per-frame raycast along `velocity*dt`, starting
/// right where the firing entity's own collider already is) — without this,
/// every projectile would immediately self-destruct against its shooter.
/// `impact_prefab_id` is optional (no sentinel needed, unlike ability_id/
/// item_id — this is the only POD id field in the project that's genuinely
/// absent rather than "0 means the first registered thing") and indexes
/// scene/prefab.zig's PrefabRegistry for a VFX prefab to spawn at the hit
/// point.
pub const ProjectileComponent = struct {
    velocity: @Vector(3, f32) = .{ 0, 0, 0 },
    damage: f32 = 10.0,
    owner: ?Entity = null,
    lifetime: f32 = 5.0,
    impulse: f32 = 0,
    impact_prefab_id: ?u32 = null,
};

/// `request_cast`/`request_target` are one-shot requests gameplay code sets
/// to ask for a cast — gameplay/ability.zig's AbilitySystem consumes and
/// clears both the instant it reads them, same one-shot-flag pattern
/// MeleeAttackComponent.trigger already uses. `casting_slot`/`casting_target`
/// are the system's own runtime state once a cast with cast_time > 0 is in
/// flight — captured at cast-start rather than re-reading request_target,
/// since request_target could be overwritten by gameplay before the cast
/// actually resolves.
pub const AbilitySlotsComponent = struct {
    slots: [6]AbilitySlot = .{ .{}, .{}, .{}, .{}, .{}, .{} },
    resource: f32 = 100,
    casting_slot: ?u8 = null,
    casting_target: ?Entity = null,
    cast_timer: f32 = 0,
    request_cast: ?u8 = null,
    request_target: ?Entity = null,
};

/// Drives a CharacterControllerComponent on the same entity — see
/// gameplay/movement.zig's PlayerMovementSystem. `velocity` is runtime state
/// (current horizontal world-space velocity, y always 0 — vertical speed
/// lives in the Jolt character itself, see character_controller.zig), kept
/// here rather than recomputed from scratch each frame so accel/friction can
/// lerp toward a target instead of snapping to it. `footstep_distance` is the
/// matching runtime accumulator for footstep_interval.
pub const PlayerMovementComponent = struct {
    walk_speed: f32 = 4.0,
    sprint_multiplier: f32 = 1.8,
    acceleration: f32 = 20.0,
    friction: f32 = 25.0,
    jump_speed: f32 = 5.0,
    footstep_interval: f32 = 1.8,
    velocity: @Vector(3, f32) = .{ 0, 0, 0 },
    footstep_distance: f32 = 0,
};
