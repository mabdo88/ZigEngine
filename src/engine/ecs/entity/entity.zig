pub const Entity = struct {
    index: u32 = 0,
    generation: u32 = 0,
    pub fn make(index: u32, generation: u32) Entity {
        return .{ .index = index, .generation = generation };
    }
};
