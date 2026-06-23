# Flecs C API patterns (pre-digested)

Templates only — **confirm exact signatures against the live Flecs docs for your
version** (see [`../SKILL.md`](../SKILL.md) Step 2). Facts below were verified
against the Flecs v4.x docs (`flecs.dev/flecs/`) and the C component API
(`group__components.html`). For Strife, **always use the C API from Zig**
(`@cImport "flecs.h"`); the C++ API is not callable from Zig.

---

## 1. Component lifecycle hooks (ctor/dtor/copy/move/on_add/on_set/on_remove)

Hooks are the **"interface" of a component** — the ECS counterpart to OOP
ctor/dtor. **One hook per event per component.** They are invoked by mutations on
the component data and are **much more efficient than observers**. Hooks can only
be set for **components, not tags**, and only **before the component is in use**
(added to any entity).

Set hooks with `ecs_set_hooks_id` (macro: `ecs_set_hooks(world, T, {...})`). The
struct (`ecs_type_hooks_t`, from `group__components.html`):

```c
typedef struct ecs_type_hooks_t {
    ecs_xtor_t ctor;            // void(*)(void *ptr, int32_t count, const ecs_type_info_t*)
    ecs_xtor_t dtor;
    ecs_copy_t copy;            // void(*)(void *dst, const void *src, int32_t, const ecs_type_info_t*)
    ecs_move_t move;            // void(*)(void *dst, void *src, int32_t, const ecs_type_info_t*)
    ecs_copy_t copy_ctor;
    ecs_move_t move_ctor;
    ecs_move_t ctor_move_dtor;
    ecs_move_t move_dtor;
    ecs_iter_action_t on_add;       // void(*)(ecs_iter_t*)
    ecs_iter_action_t on_set;       // void(*)(ecs_iter_t*)
    ecs_iter_action_t on_remove;    // void(*)(ecs_iter_t*)
    void *ctx;
    void *binding_ctx;
    ecs_ctx_free_t ctx_free;
    ecs_ctx_free_t binding_ctx_free;
    /* + flags */
} ecs_type_hooks_t;
```

**Invocation order (verified):**
- `on_add` fires **before** observers (`OnAdd`); the constructor + `on_add` hook
  run *before* an `OnAdd` observer sees the entity.
- `on_remove` fires **after** observers, and **before** the destructor.
- Hooks always get priority over observers.

```c
// on_add hook: runs synchronously when MeshComponent is first added.
static void MeshComponent_on_add(ecs_iter_t *it) {
    MeshComponent *m = ecs_field(it, MeshComponent, 0);
    for (int i = 0; i < it->count; i++) {
        /* react to m[i] — e.g. flag for GPU upload */
    }
}

ecs_set_hooks(world, MeshComponent, {
    .on_add = MeshComponent_on_add
});
```

## 2. Observers vs. hooks (when to use which)

| | Hook | Observer |
| --- | --- | --- |
| Count per event/component | **exactly one** | **many** |
| Matches | a single component | a **query** (multiple terms, filters) |
| Works on tags? | no (components only) | yes |
| Efficiency | **higher** | lower |
| May mutate the component? | **yes** | should **not** |
| Changeable after use? | no (fixed once in use) | yes (add/remove dynamically) |
| Mental model | the component's built-in behavior | other systems reacting to events |

Rules of thumb (from the Observers manual):
- If you find yourself **adding/removing components just to trigger an
  observer**, that's a bad use — it's expensive and unreliable under command
  batching.
- **If a system can solve it, prefer a system** — systems are more efficient and
  have predictable per-frame performance.
- Observer for an `OnAdd` event runs **after** the ctor + `on_add` hook. If the
  add came from a `set`, the set value is **not** visible to the `OnAdd`
  observer (only to `OnSet`).

```c
// Observer: many subscribers can react to OnAdd of MeshComponent.
ecs_observer(world, {
    .query.terms = {{ ecs_id(MeshComponent) }},
    .events = { EcsOnAdd },
    .callback = SomeSubsystem_on_mesh_added
});
```

## 3. Relationships and the `ChildOf` hierarchy

Flecs has **native relationships** as pairs `(Relationship, Target)`. Builtin
`ChildOf` and `IsA` are marked `Acyclic`.

```c
ecs_entity_t parent = ecs_new(world);
ecs_entity_t child  = ecs_new(world);
ecs_add_pair(world, child, EcsChildOf, parent);   // child of parent
// shorthand exists: ecs_new_w_pair(world, EcsChildOf, parent)
```

Query a hierarchy by traversing the relationship (e.g. `.src.id = EcsThis,
.trav = EcsChildOf, .flags = EcsUp` in query terms). Wildcards: `ecs_pair(rel,
EcsWildcard)`. This is exactly what an isometric scene graph wants — no
hand-rolled parent pointers needed when on Flecs.

## 4. Automatic deferred operations inside systems

Inside a **system callback**, structural operations (add/remove/set/delete) are
**automatically deferred** and replayed at a sync point — so a component you add
mid-system is not visible until the merge. Outside systems, defer explicitly:

```c
ecs_defer_begin(world);
/* batched add/remove/set — replayed on end */
ecs_defer_end(world);
```

Why it matters for Strife/Vulkan: do not assume mid-frame visibility of deferred
changes, and don't drive **unsynchronized GPU mutations** from a callback that
may run during command recording. Stage GPU uploads to a safe frame boundary.

## 5. Singletons

A singleton is just a **component added to its own component id** — ideal for the
global **Contiguity** scale.

```c
ecs_singleton_set(world, Contiguity, { .value = 1.0f });
const Contiguity *c = ecs_singleton_get(world, Contiguity);
// In a query, match it with term .src.id = ecs_id(Contiguity)
```

## 6. Prefabs and `IsA` instantiation

Prefabs are entities with the `EcsPrefab` tag; instantiate with `IsA`.
Components are **inherited** (shared) until overridden on the instance — good for
Emender/Knave archetypes.

```c
ecs_entity_t KnavePrefab = ecs_new_w_id(world, EcsPrefab);
ecs_set(world, KnavePrefab, Health, { .max = 30 });

ecs_entity_t knave = ecs_new_w_pair(world, EcsIsA, KnavePrefab); // inherits Health
ecs_set(world, knave, Position, { 0, 0 });   // override/add per-instance
```

## 7. Pipeline phases and `DependsOn` ordering

Systems are **queries + a function** scheduled into a pipeline by phase. Builtin
phases run in order: `EcsOnLoad` → `EcsPostLoad` → `EcsPreUpdate` →
`EcsOnUpdate` → `EcsOnValidate` → `EcsPostUpdate` → `EcsPreStore` → `EcsOnStore`.
`ecs_progress(world, dt)` runs the whole pipeline; `ecs_run(world, sys, dt,
param)` runs one system manually; phase `0` keeps a system out of the pipeline.

```c
void Move(ecs_iter_t *it) {
    Position *p = ecs_field(it, Position, 0);
    const Velocity *v = ecs_field(it, Velocity, 1);
    for (int i = 0; i < it->count; i++) { p[i].x += v[i].x; p[i].y += v[i].y; }
}

// macro form — phase = EcsOnUpdate, [in] marks Velocity read-only
ECS_SYSTEM(world, Move, EcsOnUpdate, Position, [in] Velocity);

// desc form — explicit DependsOn ordering
ecs_entity_t s = ecs_system(world, {
    .entity = ecs_entity(world, { .name = "Move",
        .add = ecs_ids(ecs_dependson(EcsOnUpdate)) }),
    .query.terms = { { ecs_id(Position) }, { ecs_id(Velocity), .inout = EcsIn } },
    .callback = Move
});
```

Map Strife's existing priority chain (input → scene → movement → camera →
render) onto phases + `DependsOn` rather than hand-tuned integer priorities.

## 8. Cached vs uncached queries

- **Cached queries** store the matched set of tables and update incrementally —
  cheap to iterate repeatedly (systems use cached queries by default). Best for
  per-frame queries.
- **Uncached queries** re-evaluate matching on iteration — cheaper to create, no
  per-query memory, best for one-shot / rarely-run queries.
- Archetype matching is **per table**, so adding a query term that causes
  frequent table moves (component churn) hurts more than the query itself.

## 9. Zig / C API usage example (`@cImport`)

```zig
// Zig 0.16.0 — Flecs via the C API. Confirm signatures against the linked headers.
const c = @cImport({
    @cInclude("flecs.h");
});

const MeshComponent = extern struct { mesh_id: u32, uploaded: bool };

fn meshOnAdd(it: ?*c.ecs_iter_t) callconv(.c) void {
    const iter = it.?;
    // ecs_field is a macro in C; in Zig call the underlying function with the id+size+index.
    const ptr = c.ecs_field_w_size(iter, @sizeOf(MeshComponent), 0);
    const meshes: [*]MeshComponent = @ptrCast(@alignCast(ptr));
    var i: usize = 0;
    while (i < @as(usize, @intCast(iter.count))) : (i += 1) {
        meshes[i].uploaded = false; // flag for GPU upload at a safe boundary
    }
}

pub fn registerMesh(world: *c.ecs_world_t, mesh_id: c.ecs_entity_t) void {
    var hooks = std.mem.zeroes(c.ecs_type_hooks_t);
    hooks.on_add = meshOnAdd;
    c.ecs_set_hooks_id(world, mesh_id, &hooks);
}
```

Notes:
- `ecs_field` / `ecs_set_hooks` / `ecs_singleton_set` are **macros** — from Zig
  use the underlying functions (`ecs_field_w_size`, `ecs_set_hooks_id`, …) or
  wrap the macros in a tiny C shim.
- Callbacks must be `callconv(.c)`; cast `void*` payloads with
  `@ptrCast`/`@alignCast` at the boundary and keep C types out of the rest of the
  engine.
- Zero-init the hooks struct (`std.mem.zeroes`) so unused function pointers are
  null.
