//Entity is a generational handle: a 32-bit index plus a 32-bit generation.
//The index addresses component storage; the generation invalidates stale handles
//after an index is recycled.
pub const Entity = struct {
    index: u32 = 0,
    generation: u32 = 0,
    pub fn make(index: u32, generation: u32) Entity {
        return .{ .index = index, .generation = generation };
    }
};

// Component bit flags for the per-entity component bitset used by queries.
// Values are proper power-of-two flags so masks combine correctly.
pub const ComponentBits = enum(u64) {
    Mesh = 1 << 0,
    Transform = 1 << 1,
    WorldTransform = 1 << 2,
    Camera = 1 << 3,
    Texture = 1 << 4,
    Scene = 1 << 5,
    SceneActive = 1 << 6,
    ScenePending = 1 << 7,
    SceneOwned = 1 << 8,
    CameraMatrices = 1 << 9,
    TextureData = 1 << 10,
};
