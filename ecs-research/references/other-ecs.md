# Secondary ECS references (EnTT + other engines)

Consult **after** Flecs (Step 3/4 in [`../SKILL.md`](../SKILL.md)). Use these to
understand *why* a tradeoff exists, not as drop-in solutions — Strife runs on
Flecs (C API from Zig).

---

## EnTT — the sparse-set reference model

Source of truth: `https://raw.githubusercontent.com/skypjack/entt/master/docs/md/entity.md`
(Crash Course: entity-component system).

**Design decisions (verbatim themes):**
- **Type-less / bitset-free:** sparse-set model; no need to declare the component
  set at compile- or run-time. `entt::registry registry;` and just use types.
- **Build your own:** "a set of containers used as needed… does not attempt to
  take over the user codebase, nor to control its main loop or process
  scheduling." → **No built-in scheduler.** You own the loop. (`organizer` only
  helps order tasks.)
- **Pay per use:** features (e.g. signals via static mixins) are opt-in and
  disableable; you pay memory/perf only for what you use.
- **All or nothing:** a `T**` to all instances of a component is always
  available — the cornerstone of the sparse-set design.

**Core API:**
```cpp
auto e = registry.create();              // make entity
registry.emplace<Position>(e, 0.f, 0.f); // add+construct component (aggregate init detected)
registry.destroy(e);                     // remove all components + release
registry.release(e);                     // release an orphaned id (no pool query)
bool ok = registry.valid(e);
// bulk: registry.insert<Position>(first, last, instances); create(first, last)
```

**Observe changes (the hook/observer analog):** sinks you connect listeners to —
```cpp
registry.on_construct<Position>().connect<&listener>();  // added
registry.on_update<Position>().connect<&listener>();     // patched/replaced (needs patch/replace)
registry.on_destroy<Position>().connect<&listener>();    // removed
```
Contrast with Flecs: EnTT has **no ctor/dtor "hook" vs "observer" split** and no
query-matched observers — just per-pool signals. Many listeners allowed; you
manage connection/disconnection.

**Iteration: views vs groups**
- **Views** = on-the-fly intersection of pools (cheap to create, no setup). Good
  default. Structural changes during iteration are restricted (see *What is
  allowed and what is not*).
- **Groups** = reorder/own pools so matched components are **contiguous (SoA)**
  for maximum iteration speed — the cost is the group "owns" the layout, adding
  constraints. This is EnTT's answer to what Flecs gets for free from archetypes.
- **Pointer stability / in-place delete:** opt-in per component when you need
  stable references (default swap-and-pop invalidates the moved element).

**Key contrast vs Flecs (the tradeoff):**
- Add/remove a component → EnTT touches **one pool** (cheap). Flecs **moves the
  entity to another table** (copies all components — expensive at horde scale).
- Flecs gives **relationships, prefabs, observers, pipeline** out of the box;
  EnTT gives **containers** and leaves architecture to you.
- Iterating one big archetype: Flecs is linear SoA. Iterating one pool: EnTT is
  linear too. Multi-component without grouping: EnTT pays sparse lookups; Flecs
  pays only the per-table match.

---

## Bevy ECS (Rust) — change detection & system params

Reference: `https://bevyengine.org/learn/` / `https://docs.rs/bevy_ecs/`.
- **Change detection** is first-class: `Added<T>` / `Changed<T>` query filters
  and `Ref<T>` track per-component change ticks — react to mutations **without**
  adding/removing components (avoids the structural-change cost). Useful idea for
  "MeshComponent changed → re-upload" without churning archetypes.
- **System params** (`Query`, `Res`, `Commands`, `EventReader`) make
  dependencies explicit; the scheduler infers parallelism from data access. Bevy
  is **archetype-ish** (table + sparse-set storage selectable per component via
  `#[component(storage = "SparseSet")]`) — a useful middle ground to cite.
- **Commands** are deferred structural ops applied at sync points — same mental
  model as Flecs deferral.

## Unity DOTS / ECS (C#) — chunks, baking, hybrid renderer

Reference: `https://docs.unity3d.com/Packages/com.unity.entities@latest`.
- **Chunk layout:** archetypes split into fixed 16 KiB **chunks** of SoA
  component arrays; queries iterate chunks. Same archetype-move cost as Flecs —
  structural changes move entities between chunks/archetypes.
- **Baking pipeline:** authoring GameObjects are **baked** into runtime entity
  data offline — analogous to compiling prefabs/scenes into a fast runtime form;
  worth mirroring for Strife scene/prefab loading.
- **Hybrid renderer / `IComponentData` vs `ISharedComponentData`:** shared
  components group entities by shared value (e.g. material) into the same chunk —
  similar in spirit to Flecs relationships/tags for batching draw calls.

## Unreal Mass Entity (C++) — significance & LOD for hordes

Reference: `https://dev.epicgames.com/documentation/en-us/unreal-engine/mass-entity-in-unreal-engine`.
- Built specifically for **large crowds** — **directly relevant to Knave
  hordes.** Core idea: a **significance/LOD manager** assigns each entity a LOD
  based on distance/importance, and **processors run different logic (or skip)
  per LOD tier**. Distant Knaves get cheap/low-frequency updates; near ones get
  full simulation.
- Takeaway for Strife: model Knave updates as LOD-tiered systems (use a
  `LodTier` tag/component or `CanToggle`) rather than running full per-entity
  logic on thousands of horde entities every frame.

---

## Storage model decision tree (archetype vs sparse-set)

```
Is the component set per entity mostly STABLE over its lifetime?
├─ YES → archetype (Flecs) wins: SoA linear iteration, cheap once settled.
│        (heroes/Emenders with fixed component sets, render data)
└─ NO  → components added/removed frequently (per-frame, at scale)?
         ├─ YES → sparse-set semantics win (cheap add/remove, no entity move).
         │        On Flecs, AVOID churn: use tags + CanToggle + deferred batches,
         │        or change-detection-style flags, instead of add/remove.
         └─ NO  → either works; pick for ergonomics.

Need relationships / hierarchy / prefabs / a scheduler out of the box?
└─ YES → archetype engine with first-class features (Flecs). Sparse-set libs
         (EnTT) make you build these yourself.

Iterating ONE component type in tight loops?
└─ Both are linear/SoA. Multi-component hot loops favor archetype (Flecs) or an
   EnTT owning group (which reintroduces archetype-like layout constraints).

Horde scale (thousands, Knaves)?
└─ Minimize structural churn regardless of engine; add an LOD/significance tier
   (see Unreal Mass Entity) so most entities run cheap, low-frequency logic.
```

**For Strife:** we're on Flecs (archetype). Lean into stable archetypes + SoA
iteration for Emenders and rendering; defend against archetype-move cost for
Knave hordes via tags/toggles/deferral and LOD tiers.
