# SKILL: Zig documentation lookup

**Trigger:** any task that writes, fixes, migrates, or reviews Zig code.

Zig breaks compatibility nearly every release (`std.io` → `std.Io`, `build.zig`,
`CallingConvention`, async, testing APIs all churn). **Code written from memory
is frequently wrong.** This skill forces you to ground every Zig change in live,
version-correct documentation before writing a line.

> Do not write Zig from memory. Fetch the docs for the *target version* first,
> then copy exact signatures from what you fetched.

---

## Decision procedure

### Step 1 — Determine the target Zig version

In priority order:

1. Read `build.zig.zon` → `.minimum_zig_version`. That is the target.
   ```sh
   grep minimum_zig_version build.zig.zon
   ```
2. If there is a local toolchain, confirm it: `zig version`.
3. If the user explicitly names a version (e.g. "test against master / 0.17-dev"),
   that overrides.
4. If still unclear, **ask the user**.
5. **Default: `0.16.0`** (current stable, released April 2026).

Pin the resolved version in a variable for the rest of the task, e.g. `VERSION=0.16.0`.

### Step 2 — Fetch the live documentation BEFORE writing code

Fetch these (substitute `<VERSION>`), do not rely on memory:

| What | URL |
| ---- | --- |
| Language reference | `https://ziglang.org/documentation/<VERSION>/` |
| Standard library | `https://ziglang.org/documentation/<VERSION>/std/` |
| Release notes | `https://ziglang.org/download/<VERSION>/release-notes.html` |
| Nightly / upcoming devlog | `https://ziglang.org/devlog/2026/` and `https://ziglang.org/devlog/2025/` |
| Master (nightly) docs | `https://ziglang.org/documentation/master/` |

**Best ground truth: the installed toolchain's own stdlib source.** When a local
`zig` is present it is *the* authority for that exact version — fetch the web docs
for prose/breaking-change context, but confirm signatures against source:

```sh
ZIG_LIB=$(dirname "$(readlink -f "$(which zig)")")/lib/std   # e.g. ~/zig/lib/std
grep -rnE "pub fn openFile" "$ZIG_LIB/Io/Dir.zig"
```

### Step 3 — Scan release notes for breaking changes

Always do this when migrating, or when an API you touch could have changed.
Search the release notes for the symbols you intend to use. Known hotspots are in
the table below — but scan, don't assume.

### Step 4 — Write code using exact signatures from the docs

- Copy signatures from the fetched docs / stdlib source, never from memory.
- **Annotate every Zig code block with the version**, as a first-line comment:
  ```zig
  // Zig 0.16.0
  ```
- If a local toolchain exists, compile what you wrote before claiming it works
  (`zig ast-check file.zig`, then `zig build-exe`/`zig build test`).

### Step 5 — Reference structural patterns

Use [`references/patterns.md`](references/patterns.md) for idiomatic templates
(allocator + defer deinit, error sets, comptime generics, `build.zig`, C interop,
testing). A verified, compiles-on-0.16.0 example lives in
[`examples/read_lines_0.16.zig`](examples/read_lines_0.16.zig).

---

## Known breaking-change hotspots

| Area | What changed | Notes |
| ---- | ------------ | ----- |
| `std.io.Writer` / `Reader` | Redesigned in **0.15** ("writergate"); in **0.16** I/O is an interface under **`std.Io`** | Files/streams expose a `.interface` field of type `std.Io.Reader`/`std.Io.Writer`. Get an `Io` from `std.process.Init.io` (in `main`) or `std.testing.io` (in tests). See patterns. |
| File system | **All `fs` APIs migrated to `std.Io` in 0.16** | `std.fs.cwd` → `std.Io.Dir.cwd`; `std.fs.File` → `std.Io.File`; `std.fs.Dir` → `std.Io.Dir`. Most calls now take an `io: Io` parameter. |
| `build.zig` API | Changes nearly every release | 0.14+: `b.addExecutable(.{ .name = ..., .root_module = b.createModule(.{...}) })` then `b.installArtifact(exe)`. Modules own target/optimize/imports/C sources. |
| `CallingConvention` | Became a **tagged union** in **0.14** | e.g. `.c`, or `.{ .x86_stdcall = .{} }` — no longer a bare enum. |
| Async / await | Removed in **0.12**; **re-added in 0.16 via the `std.Io` interface** | `io.async(fn, .{args})` → `Future(T)`, plus `io.concurrent`, `Io.Group`. Check the devlog for the latest. |
| `std.testing` | Assertion / Io helpers shift between versions | `std.testing.allocator`, `std.testing.expect`, `expectEqual`, `expectEqualStrings`; `std.testing.io` provides an `Io` in tests. |
| `main` signature | 0.16 offers `pub fn main(init: std.process.Init) !void` | `init.io`, `init.gpa`, `init.arena`, `init.minimal.args`. `pub fn main() !void` still works. |
| `fmt` | `format` → `std.Io.Writer.print`; `Formatter` → `Alt`; `FormatOptions` → `Options` | Formatting now goes through the `std.Io.Writer` interface. |

---

## Quick checklist (run through this every Zig task)

- [ ] Resolved target version (`build.zig.zon` → default `0.16.0`).
- [ ] Fetched language ref + stdlib + release notes for that version.
- [ ] Confirmed signatures against installed stdlib source when available.
- [ ] Scanned release notes for breaking changes touching my APIs.
- [ ] Annotated code blocks with `// Zig <VERSION>`.
- [ ] Compiled / ast-checked locally if a toolchain exists.
