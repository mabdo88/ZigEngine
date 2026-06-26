# ECS storage strategy

This is a hand-rolled sparse-set ECS — not Flecs, not an archetype/table
storage. See [CLAUDE.md](../../../CLAUDE.md) for the project-wide rationale;
this file is just the storage-layer detail.

## Entities

`Entity{ index: u32, generation: u32 }` ([entity/entity.zig](entity/entity.zig)).
`Registry` keeps a `generations: []u32` array indexed by `entity.index` and a
`freeList` of recycled indices. Destroying an entity bumps its generation and
pushes the index onto the free list; a stale handle fails `isAlive()` because
its `generation` no longer matches. A generation that hits `maxInt(u32)` is
retired permanently (removed from the free list for good) instead of
wrapping back to 0, so a 4-billion-reuse index can never collide with a
still-held stale handle.

## Component storage

Each component type `T` gets its own `ComponentStorage(T)`
([entity/componentStorage.zig](entity/componentStorage.zig)) — three parallel
arrays:

- `dense: []T` — the actual component data, packed with no holes
- `entities: []u32` — `entities[i]` is the entity index that owns `dense[i]`
- `sparse: []u32` — indexed by entity index, `sparse[entity.index]` is that
  entity's position in `dense`/`entities`, or `EMPTY` (`maxInt(u32)`)

Removing an entity's component swap-removes: the last element of `dense`
moves into the freed slot, `sparse` is patched for whichever entity just
moved, and the arrays shrink by one. This keeps `dense` contiguous (good for
iteration) at the cost of not preserving insertion order on removal — nothing
in this codebase depends on component iteration order.

`Registry.storage` is a comptime tuple of `ComponentStorage(T)` for every `T`
in `components.AllComponents` — `StorageType()` builds it, and
`ComponentIndex(T)`/`ComponentBit(T)` (in
[components/components.zig](components/components.zig)) resolve a type to
its tuple slot and its bit in the `u64` per-entity component mask at
comptime. Adding a new component type means adding it to `AllComponents` —
the registry picks it up automatically.

## Queries

`Registry.Query(.{ComponentA, ComponentB, ...})` ORs the requested types'
bits into a mask, then iterates whichever requested storage currently has the
fewest entries (cheapest to drive the scan) and mask-checks each candidate
entity against the full `component_masks` array. No per-frame allocation, no
archetype/table migration — masks are recomputed at comptime per query shape,
checked at runtime per entity.

## Why not Flecs / archetypes

CLAUDE.md covers this in full, but briefly: this gets you the same
swap-remove-on-delete, packed-iteration properties that archetype storage
gives you, without needing entities to migrate between tables when their
component set changes, and without a C dependency. If relationship features
(prefabs, `EcsIsA`, hierarchy queries) are ever genuinely needed, that's the
trigger to reconsider Flecs — not before.

## Measured performance

`registry.zig`'s `"10k entity create+attach+query+destroy benchmark"` test
creates 10,000 entities with a `TransformComponent` each, queries all of
them, then destroys them all, logging real timings. Representative numbers
from an unoptimized **Debug** build (`zig build test`):

| Operation | 10k entities |
|---|---|
| create + attach | ~2.2ms |
| query (full scan) | ~0.13ms |
| destroy | ~0.9ms |

The original roadmap target was "<1ms" for 10k entities — that's a
release-build number; this test asserts generous Debug-build bounds (50ms /
10ms / 50ms) instead, since the point of running it under `zig build test`
is catching an accidental O(n²) regression, not chasing a ReleaseFast
benchmark inside a debug test run. Re-run with
`zig build test -Doptimize=ReleaseFast` if you want the optimized numbers.
