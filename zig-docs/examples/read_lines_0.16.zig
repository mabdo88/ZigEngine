// Zig 0.16.0
const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    // Command-line args come from `init.minimal.args` in 0.16.
    var args = std.process.Args.Iterator.init(init.minimal.args);
    _ = args.skip(); // skip program name
    const path = args.next() orelse {
        std.log.err("usage: read_lines <path>", .{});
        return error.MissingPathArgument;
    };

    // Open the file relative to the current working directory.
    const file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);

    // Wrap the file in a buffered reader; `.interface` is the std.Io.Reader.
    var read_buffer: [4096]u8 = undefined;
    var file_reader = file.reader(io, &read_buffer);
    const reader = &file_reader.interface;

    // Buffered writer over stdout; `.interface` is the std.Io.Writer.
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    // takeDelimiter returns the next line excluding '\n', or null at EOF.
    while (try reader.takeDelimiter('\n')) |line| {
        try stdout.print("{s}\n", .{line});
    }
    try stdout.flush();
}
