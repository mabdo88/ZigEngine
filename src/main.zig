const Engine = @import("engine/engine.zig").Engine;
const VulkanECSWorld = @import("engine/vulkan_ecs_world.zig").VulkanECSWorld;

pub fn main() !void {
    var engine = Engine{};
    engine.init();
    defer engine.deinit();

    engine.addWorld(VulkanECSWorld.factory());

    try engine.run(0);
}
