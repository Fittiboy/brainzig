const std = @import("std");
const config = @import("config");

const cells: usize = 30_000;

const BrainfuckError = error{
    LeftShiftUnderflow,
    RightShiftOverflow,
    UnmatchedOpenBracket,
    UnmatchedClosingBracket,
};

const Command = union(enum) {
    Shift: isize,
    Add: i8,
    Write: usize,
    Read: usize,
    Open: usize,
    Close: usize,
};

const Program = []const Command;

fn parseCode(
    program: *std.ArrayListUnmanaged(Command),
    loop_stack: *std.ArrayListUnmanaged(usize),
    code: anytype,
) !Program {
    @setEvalBranchQuota(4_294_967_295);
    while (code.readByte()) |c| {
        var cmd: Command = switch (c) {
            '>' => .{ .Shift = 1 },
            '<' => .{ .Shift = -1 },
            '+' => .{ .Add = 1 },
            '-' => .{ .Add = -1 },
            '.' => .{ .Write = 1 },
            ',' => .{ .Read = 1 },
            '[' => .{ .Open = undefined },
            ']' => .{ .Close = undefined },
            else => continue,
        };

        if (program.getLastOrNull()) |last| switch (last) {
            inline else => |v| switch (cmd) {
                inline else => |*n| if (std.meta.activeTag(last) == std.meta.activeTag(cmd)) {
                    if (c == '[' or c == ']') continue;
                    n.* +%= @as(@TypeOf(n.*), @intCast(v));
                    program.items[program.items.len - 1] = cmd;
                    continue;
                },
            },
        };
        if (c == ']') {
            const jump_index = loop_stack.pop();
            program.items[jump_index] = .{ .Open = program.items.len };
            program.appendAssumeCapacity(.{ .Close = jump_index });
        }
        if (c == '[') {
            loop_stack.appendAssumeCapacity(program.items.len);
            program.appendAssumeCapacity(cmd);
        } else program.appendAssumeCapacity(cmd);
    } else |_| {}

    return program.items;
}

fn execute(reader: anytype, writer: anytype, program: Program) !void {
    var pc: usize = 0;
    var tape: [cells]u8 = [_]u8{0} ** cells;
    var head: usize = 0;
    while (pc < program.len) : (pc += 1) {
        switch (program[pc]) {
            .Shift => |v| {
                if (v < 0) {
                    if (-v > head) return error.LeftShiftUnderflow;
                    head -= @as(usize, @intCast(-v));
                } else head += @as(usize, @intCast(v));
                if (head >= cells) return error.RightShiftOverflow;
            },
            .Add => |v| {
                if (v < 0) {
                    tape[head] -%= @as(u8, @intCast(-v));
                } else tape[head] +%= @as(u8, @intCast(v));
            },
            .Write => |v| for (0..v) |_| try writer.print("{c}", .{tape[head]}),
            .Read => |v| for (0..v) |_| {
                tape[head] = reader.readByte() catch 0;
            },
            .Open => |c| pc = if (tape[head] == 0) c else pc,
            .Close => |c| pc = if (tape[head] != 0) c else pc,
        }
    }
}

pub fn main() !void {
    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();

    if (config.file) |filename| {
        const program = comptime blk: {
            const code = @embedFile(filename);
            var stream = std.io.fixedBufferStream(code[0..]);

            var prog_buf: [stream.buffer.len]Command = undefined;
            var prog_list = std.ArrayListUnmanaged(Command).initBuffer(&prog_buf);

            var loop_buf: [stream.buffer.len]usize = undefined;
            var loop_stack = std.ArrayListUnmanaged(usize).initBuffer(&loop_buf);

            const prog = parseCode(&prog_list, &loop_stack, stream.reader()) catch |err| {
                @compileError(std.fmt.comptimePrint("{s}", .{err}));
            };
            var program: [prog.len]Command = undefined;
            std.mem.copyForwards(Command, &program, prog);
            break :blk program;
        };

        try execute(stdin, stdout, &program);
        try stdout.print("\n", .{});
    } else {
        var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
        const gpa = general_purpose_allocator.allocator();

        const CodeReader = union(enum) {
            const Self = @This();
            file: struct {
                const File = std.fs.File;
                f: File,
                reader: std.io.Reader(File, std.posix.ReadError, File.read),
            },
            memory: struct {
                const Stream = std.io.FixedBufferStream([]u8);
                slice: []u8,
                stream: Stream,
                reader: std.io.Reader(*Stream, error{}, Stream.read),
            },

            pub fn readByte(self: Self) !u8 {
                switch (self) {
                    inline else => |r| return r.reader.readByte(),
                }
            }

            pub fn len(self: Self) !usize {
                return switch (self) {
                    .file => |f| blk: {
                        const stat = try f.f.stat();
                        break :blk stat.size;
                    },
                    .memory => |m| m.slice.len,
                };
            }

            pub fn seekTo(self: *Self, offset: usize) !void {
                switch (self.*) {
                    .file => |*f| try f.f.seekTo(offset),
                    .memory => |*m| {
                        try m.stream.seekTo(offset);
                        m.reader = m.stream.reader();
                    },
                }
            }

            pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
                switch (self) {
                    .file => |f| f.f.close(),
                    .memory => |m| allocator.free(m.slice),
                }
            }
        };

        const args = try std.process.argsAlloc(gpa);
        defer std.process.argsFree(gpa, args);

        var reader = if (args.len > 1) blk: {
            const file = try std.fs.cwd().openFile(args[1], .{});
            const reader = file.reader();
            break :blk CodeReader{ .file = .{ .f = file, .reader = reader } };
        } else blk: {
            const slice = try stdin.readAllAlloc(gpa, std.math.maxInt(usize));
            var stream = std.io.fixedBufferStream(slice);
            const reader = stream.reader();
            break :blk CodeReader{ .memory = .{ .slice = slice, .stream = stream, .reader = reader } };
        };
        defer reader.deinit(gpa);

        const prog_buf = try gpa.alloc(Command, try reader.len());
        defer gpa.free(prog_buf);
        var prog_list = std.ArrayListUnmanaged(Command).initBuffer(prog_buf);

        const loop_buf = try gpa.alloc(usize, try reader.len());
        defer gpa.free(loop_buf);
        var loop_stack = std.ArrayListUnmanaged(usize).initBuffer(loop_buf);

        const program = try parseCode(&prog_list, &loop_stack, reader);

        try execute(stdin, stdout, program);
        try stdout.print("\n", .{});
    }
}
