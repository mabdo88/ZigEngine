const components = @import("../components/components.zig");

pub const Entity = struct {
    index: u32 = 0,
    generation: u32 = 0,
    pub fn make(index: u32, generation: u32) Entity {
        return .{ .index = index, .generation = generation };
    }
};

pub fn ComponentBit(comptime T: type) u64 {
    inline for (components.AllComponents, 0..) |C, i| {
        if (C == T) return @as(u64, 1) << @intCast(i);
    }
    @compileError("Unregistered component type: " ++ @typeName(T));
}

pub fn ComponentIndex(comptime T: type) comptime_int {
    inline for (components.AllComponents, 0..) |C, i| {
        if (C == T) return i;
    }
    @compileError("Unregistered component type: " ++ @typeName(T));
}
