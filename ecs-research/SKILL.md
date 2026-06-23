# SKILL: ECS research (Flecs / EnTT) before engine work

**Trigger:** any task that implements an ECS feature, makes an ECS architectural
decision, or adds a new engine system in **ZigEngine** (entities, components,
queries, systems, observers, relationships, prefabs, lifecycle, scheduling,
storage layout, deferred mutations, singletons, hierarchy).

ECS design is full of non-obvious tradeoffs — archetype move costs, deferred
operation semantics, query caching, structural-change rules, hook vs observer
ordering. **Implementing from memory leads to subtle bugs and performance
cliffs.** This skill forces you to ground every ECS decision in the live Flecs
and EnTT documentation *before* writing engine code.

> Do not design or write ECS code from memory. Name the problem, fetch the Flecs
> docs first (we use Flecs), cross-reference EnTT for the sparse-set view, then
> adapt to ZigEngine — copying exact signatures from what you fetched.

---

## Flecs (archetype) vs EnTT (sparse-set) — at a glance

| Dimension | **Flecs** (we use this) | **EnTT** |
| --------- | ----------------------- | -------- |
| Storage model | Archetype / table: entities with the same component set share a table, stored **SoA** | Sparse-set: each component type has its own pool (sparse + dense arrays) |
| Query style | Match by **table** (archetype). Cached and uncached queries; iterate columns per matched table | **Views** (intersection of pools) and **groups** (reorder pools for SoA-fast iteration) |
| Add/remove cost | **Moves the entity to a different table** — copies all its components. Expensive in hot loops | Touches only that one pool (push/swap-remove). Cheap; no whole-entity move |
| Iteration cost | Excellent for fixed archetypes (linear SoA scans per table) | Excellent for single pool; multi-component views pay sparse lookups unless grouped |
| Relationships | **Native first-class** — pairs `(Relationship, Target)`, `ChildOf`, `IsA`, wildcards, traversal | None built in — model hierarchies yourself (e.g. parent entity field + your own traversal) |
| Reactivity | **Hooks** (one per component: ctor/dtor/copy/move/on_add/on_set/on_remove) **and Observers** (many, query-matched, event-driven) | **Signals**: `on_construct<T>()` / `on_update<T>()` / `on_destroy<T>()` sinks you connect listeners to |
| System scheduling | **First-class pipeline**: phases (`EcsOnUpdate`, …), `DependsOn` ordering, optional multithreading, `ecs_progress()` | **No built-in scheduler** — "just containers". You own the loop; optional `organizer` helps order |
| Deferred ops | **Automatic inside system callbacks**; explicit `ecs_defer_begin/end` outside. Commands replay at sync points | No global defer concept; structural changes during view iteration are restricted (use in-place / deferred-by-hand patterns) |
| C / Zig compatibility | **Use the C API** (`ecs_*`, `flecs.h`) via Zig `@cImport`. The C++ API is unusable from Zig | C++17 template/header-only library — **not callable from Zig**; only useful as a reference model |

Bottom line for ZigEngine: we get Flecs's relationships, observers, and pipeline
for free, but must respect **archetype move cost** (batch structural changes, use
tags/toggles instead of churning components in hot loops) and **deferred
semantics at frame boundaries** (GPU work). EnTT is the reference lens that
exposes *why* an archetype tradeoff exists — never a drop-in alternative here.

---

## The 5-step research workflow

### Step 1 — Name the problem precisely (one sentence)

Before searching, write a single sentence: *"I need to \<do X\> when \<condition\>,
running \<where / how often\>, touching \<which resources\>."* A vague problem
fetches the wrong docs. Example: *"Fire a callback synchronously whenever
`MeshComponent` is added so I can upload the mesh to the GPU."*

### Step 2 — Fetch Flecs documentation FIRST (primary — we use Flecs)

Do not rely on memory. Fetch the page(s) for your topic. All under
`https://www.flecs.dev/flecs/`:

| Topic | URL |
| ----- | --- |
| Manual (entry / overview) | `https://www.flecs.dev/flecs/md_docs_2Manual.html` |
| Quickstart | `https://www.flecs.dev/flecs/md_docs_2Quickstart.html` |
| Entities & Components | `https://www.flecs.dev/flecs/md_docs_2EntitiesComponents.html` |
| Queries | `https://www.flecs.dev/flecs/md_docs_2Queries.html` |
| Systems | `https://www.flecs.dev/flecs/md_docs_2Systems.html` |
| Observers | `https://www.flecs.dev/flecs/md_docs_2ObserversManual.html` |
| Relationships | `https://www.flecs.dev/flecs/md_docs_2Relationships.html` |
| Prefabs | `https://www.flecs.dev/flecs/md_docs_2Prefabs.html` |
| Component Traits (hooks, cleanup, toggle, sparse, …) | `https://www.flecs.dev/flecs/md_docs_2ComponentTraits.html` |
| Design (Designing with Flecs) | `https://www.flecs.dev/flecs/md_docs_2DesignWithFlecs.html` |
| FAQ | `https://www.flecs.dev/flecs/md_docs_2FAQ.html` |
| C component/hooks API reference | `https://www.flecs.dev/flecs/group__components.html` |

Pre-digested Flecs **C API** patterns (grounded in these pages) live in
[`references/flecs-patterns.md`](references/flecs-patterns.md). Use it as a
starting template, but confirm signatures against the fetched page.

### Step 3 — Cross-reference EnTT (the sparse-set model reveals the tradeoff)

EnTT's pure sparse-set design makes the cost model explicit (cheap add/remove,
no relationships, no scheduler). Fetch:

| Topic | URL |
| ----- | --- |
| Crash Course: ECS (the canonical EnTT doc) | `https://github.com/skypjack/entt/blob/master/docs/md/entity.md` (raw: `https://raw.githubusercontent.com/skypjack/entt/master/docs/md/entity.md`) |
| Wiki Crash Course index | `https://github.com/skypjack/entt/wiki/` |

Pre-digested EnTT/other-engine notes: [`references/other-ecs.md`](references/other-ecs.md).

### Step 4 — Check secondary sources only if Flecs+EnTT don't settle it

For ideas Flecs/EnTT don't cover well (change detection, chunk baking, horde
LOD), consult the secondary engines documented in
[`references/other-ecs.md`](references/other-ecs.md): **Bevy ECS** (change
detection, system params), **Unity DOTS** (chunk layout, baking, hybrid
renderer), **Unreal Mass Entity** (significance/LOD for hordes — directly
relevant to Knaves).

### Step 5 — Produce a structured answer

Always answer in this shape:

1. **What Flecs does** (with the exact API from the fetched page).
2. **What EnTT does** (the sparse-set contrast).
3. **Key tradeoff** (cost / correctness / frame-safety).
4. **Recommendation for ZigEngine** (concrete: which API, where it runs, the
   archetype-move and frame-boundary caveats, a Zig C-API sketch).

---

## Feature → doc-page lookup table

Jump straight to the right page for common engine features. Always fetch Flecs
first; the EnTT column is the contrast lens.

| Engine feature | Flecs page | EnTT reference |
| -------------- | ---------- | -------------- |
| Component lifecycle hooks (ctor/dtor/on_add/on_set/on_remove) | `md_docs_2ComponentTraits.html` (Component Hooks) + `group__components.html` | entity.md → *Observe changes* (`on_construct`/`on_update`/`on_destroy`) |
| Reacting to events from many places | `md_docs_2ObserversManual.html` | entity.md → *Observe changes* (sinks) |
| Scene hierarchy / parent-child | `md_docs_2Relationships.html` (`ChildOf`) | entity.md → *Hierarchies and the like* (no native support) |
| Prefabs / instantiation | `md_docs_2Prefabs.html` (`IsA`) | (no native prefabs; build your own) |
| Deferred / structural mutations | `md_docs_2Systems.html` + `md_docs_2Manual.html` (defer) | entity.md → *What is allowed and what is not* (iteration restrictions) |
| Singletons / global state | `md_docs_2Manual.html` (singletons = component on its own id) | entity.md → *Context variables* |
| Bulk entity creation | `md_docs_2EntitiesComponents.html` / Manual (bulk) | entity.md → `insert` / `create(first, last)` |
| Query filters (with/without/optional) | `md_docs_2Queries.html` | entity.md → *Views* / *Exclude-only* |
| SoA grouping / cache-friendly iteration | archetype is SoA by default (`md_docs_2Queries.html`) | entity.md → *Groups* (owning groups) |
| System ordering / phases | `md_docs_2Systems.html` (phases, `DependsOn`) | entity.md → *Organizer* (no real scheduler) |
| Toggling components cheaply | `md_docs_2ComponentTraits.html` (`CanToggle`) | (disable via tag/your own flag) |

---

## ZigEngine-specific context (read every time)

- **Engine:** ZigEngine, written in **Zig**. ECS target binding is **Flecs via Zig
  C bindings**. **Always use the Flecs C API** (`ecs_*`, `ecs_set_hooks`,
  `ecs_observer`, `ecs_query`) through `@cImport` — the C++ API is not callable
  from Zig. (Note: the current `src/engine/ecs/` registry is a custom sparse-set
  implementation; treat this module as the decision procedure for adopting/
  adapting Flecs patterns — verify what the codebase actually links before
  emitting Flecs calls.)
- **Game:** *Strife* — isometric ARPG built on ZigEngine. **Emenders** (hero-tier, hundreds) and
  **Knaves** (horde enemies, thousands). Horde scale means **add/remove churn is
  a real cost** under archetypes: prefer tags + `CanToggle` + deferred batches
  over per-frame component add/remove that triggers table moves.
- **Renderer:** Vulkan. Systems that touch GPU resources (mesh/texture upload,
  descriptor writes) have **frame-boundary constraints**. Inside Flecs system
  callbacks, structural ops are **deferred** and replayed at a sync point — do
  not assume a component you added inside a system is visible mid-frame, and do
  not perform unsynchronized GPU mutations from a hook/observer that may run
  during command recording.
- **Contiguity scale:** the global Contiguity mechanic is a **singleton
  candidate** — in Flecs a singleton is just a component added to its own
  component id (`ecs_singleton_set` / `ecs_singleton_get`), queried with `.src =
  ecs_id(Contiguity)`. Don't store it as a loose global.

---

## Pre-flight implementation checklist (run before writing any engine code)

- [ ] **Problem named** in one sentence (Step 1).
- [ ] **Flecs docs fetched** for the topic (Step 2) — not recalled from memory.
- [ ] **EnTT cross-referenced** to understand the tradeoff (Step 3).
- [ ] **Secondary sources** checked only if needed (Step 4, `references/other-ecs.md`).
- [ ] Decided **hook vs observer vs system** (one-per-component synchronous
      behavior → hook; many listeners / event reaction → observer; per-frame work
      over a query → system).
- [ ] Considered **archetype move cost** — am I adding/removing components in a
      hot loop or at horde scale? Can I use a tag, `CanToggle`, or batch instead?
- [ ] Considered **deferred semantics & frame boundaries** — is this inside a
      system (auto-deferred)? Does it touch GPU resources during a frame?
- [ ] Decided whether state is a **singleton** (e.g. Contiguity) vs per-entity.
- [ ] Using the **C API** with exact signatures copied from the fetched docs; a
      Zig `@cImport` sketch written.
- [ ] Answer delivered in the **Step 5 structure** (Flecs → EnTT → tradeoff →
      ZigEngine recommendation).
