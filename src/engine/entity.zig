//Entity is 32-bit unsigned integer.
//the value itself can be used as an index to access the entity's components in a component array.
//we will reserve 8bits for the generation count and 24bits for the index. this means we can have up to 2^24 entities in the world,
// which is more than enough for most games.
pub const Entity = struct {
    index: u32 = 0,
    generation: u32 = 0,
    pub fn make(index: u32, generation: u32) Entity {
        return .{ .index = index, .generation = generation };
    }
};
