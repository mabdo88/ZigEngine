# Zig idiomatic structural patterns

Structural templates only — **always confirm exact signatures against the live
docs / installed stdlib for your target version** (see [`../SKILL.md`](../SKILL.md)).
Examples are annotated `// Zig 0.16.0` and were checked against a local 0.16.0
toolchain. Older toolchains differ; re-fetch before using.

---

## 1. Allocator pattern (GPA + `defer deinit`)

```zig
// Zig 0.16.0
const std = @import("std");

pub fn main() !void {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit(); // reports leaks in Debug
    const allocator = gpa.allocator();

    const buf = try allocator.alloc(u8, 64);
    defer allocator.free(buf);
    // ... use buf ...
}
```

- Acquire a resource, then immediately `defer` its release — keeps cleanup local
  and exception-safe.
- `DebugAllocator` (formerly `GeneralPurposeAllocator`) catches leaks/UAF in Debug.
- For release builds prefer `std.heap.smp_allocator` (multi-threaded) or
  `std.heap.page_allocator`. In `main(init: std.process.Init)` you also get a
  ready-made `init.gpa`.

## 2. Error handling (`try` / `catch` / error sets)

```zig
// Zig 0.16.0
const ParseError = error{ Empty, TooLong };

fn parse(name: []const u8) ParseError![]const u8 {
    if (name.len == 0) return error.Empty;
    if (name.len > 255) return error.TooLong;
    return name;
}

fn use(name: []const u8) !void {
    // propagate:
    const a = try parse(name);
    // handle with a default:
    const b = parse(name) catch "anonymous";
    // switch on specific errors:
    const c = parse(name) catch |err| switch (err) {
        error.Empty => "anonymous",
        error.TooLong => return err,
    };
    _ = .{ a, b, c };
}
```

- Define explicit error sets for libraries; let inferred `!T` work for leaf code.
- `errdefer` runs cleanup only on the error path:
  ```zig
  const list = try allocator.create(Node);
  errdefer allocator.destroy(list);
  ```

## 3. Comptime generics

```zig
// Zig 0.16.0
const std = @import("std");

fn Stack(comptime T: type) type {
    return struct {
        items: std.ArrayList(T),

        const Self = @This();

        fn init() Self {
            return .{ .items = .empty };
        }
        fn deinit(self: *Self, gpa: std.mem.Allocator) void {
            self.items.deinit(gpa);
        }
        fn push(self: *Self, gpa: std.mem.Allocator, v: T) !void {
            try self.items.append(gpa, v);
        }
        fn pop(self: *Self) ?T {
            return self.items.pop();
        }
    };
}

test "generic stack" {
    var s = Stack(u32).init();
    defer s.deinit(std.testing.allocator);
    try s.push(std.testing.allocator, 7);
    try std.testing.expectEqual(@as(?u32, 7), s.pop());
}
```

- Types are values at comptime: a generic container is a `fn (comptime T: type) type`.
- `@This()` names the enclosing (anonymous) struct.

## 4. `build.zig` (0.14+ module style)

```zig
// Zig 0.16.0
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "myapp",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(exe); // installs to zig-out/bin

    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Tests: a test build over the same module.
    const tests = b.addTest(.{ .root_module = exe.root_module });
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_tests.step);
}
```

- The `*Module` (from `createModule` / `addModule`) owns `target`, `optimize`,
  `imports`, include paths and C sources — call `exe.root_module.addImport(...)`,
  `exe.root_module.addCSourceFile(...)`, etc.
- `addExecutable` takes `.root_module`, not loose `.root_source_file`/`.target`.

## 5. C interop (`@cImport`)

```zig
// Zig 0.16.0
const c = @cImport({
    @cDefine("STBI_NO_STDIO", "1"); // defines before include
    @cInclude("stb_image.h");
});

pub fn loadPixels(bytes: []const u8) ?[*]u8 {
    var w: c_int = 0;
    var h: c_int = 0;
    var channels: c_int = 0;
    return c.stbi_load_from_memory(
        bytes.ptr,
        @intCast(bytes.len),
        &w,
        &h,
        &channels,
        4,
    );
}
```

- One `@cImport` per logical C API; reuse the resulting namespace.
- Wire headers/libs in `build.zig`: `mod.addIncludePath(b.path("deps/stb/"))`,
  `mod.addCSourceFile(.{ .file = b.path("src/native/stb_impl.c") })`,
  `mod.linkSystemLibrary("glfw3", .{})`.
- Use `@intCast`/`@ptrCast` at the boundary; keep C types (`c_int`, `[*c]`) out of
  the rest of the codebase.

## 6. Testing (`testing.allocator`)

```zig
// Zig 0.16.0
const std = @import("std");
const testing = std.testing;

test "list append + leak check" {
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(testing.allocator); // testing.allocator fails on leak
    try list.append(testing.allocator, 'z');

    try testing.expect(list.items.len == 1);
    try testing.expectEqual(@as(u8, 'z'), list.items[0]);
    try testing.expectEqualStrings("z", list.items);
}
```

- `std.testing.allocator` turns leaks into test failures — use it everywhere.
- Common assertions: `expect`, `expectEqual`, `expectEqualStrings`,
  `expectError`, `expectEqualSlices`.
- Need an `Io` in a test (0.16)? Use `std.testing.io`.
- Run with `zig build test` (or `zig test file.zig`).

---

## 7. I/O in 0.16: `std.Io` interface (the "writergate" / fs migration)

In 0.16 there is no global stdout/file reader; you thread an `Io` instance and
use the `.interface` field of file readers/writers. Read a file line by line:

```zig
// Zig 0.16.0
const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    const file = try std.Io.Dir.cwd().openFile(io, "input.txt", .{});
    defer file.close(io);

    var read_buffer: [4096]u8 = undefined;
    var file_reader = file.reader(io, &read_buffer);
    const reader = &file_reader.interface; // *std.Io.Reader

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buffer);
    const stdout = &stdout_writer.interface; // *std.Io.Writer

    // takeDelimiter returns the next line excluding '\n', or null at EOF.
    while (try reader.takeDelimiter('\n')) |line| {
        try stdout.print("{s}\n", .{line});
    }
    try stdout.flush(); // buffered — must flush
}
```

Key 0.16 facts (do **not** reach for the old `std.io.Reader`):

- Get an `Io`: `init.io` in `main(init: std.process.Init)`, or `std.testing.io`
  in tests, or build one with `var t: std.Io.Threaded = .init(gpa, .{}); const io = t.io();`
  (call `t.deinit()`).
- `std.fs.cwd` → `std.Io.Dir.cwd`; `std.fs.File` → `std.Io.File`. File ops take `io`.
- A `File.Reader`/`File.Writer` is a concrete buffered wrapper; its `.interface`
  field is the generic `std.Io.Reader`/`std.Io.Writer` you call methods on.
- Line reading: `takeDelimiter(d)` → `?[]u8` (null at EOF, excludes delimiter);
  `takeDelimiterExclusive(d)`/`takeDelimiterInclusive(d)` / `takeSentinel(s)` for
  variants; `streamDelimiter` to copy into a writer.
- Writers are buffered: call `flush()` before exit.
