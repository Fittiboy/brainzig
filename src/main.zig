const std = @import("std");
const config = @import("config");

const cells: usize = 30_000;

const BrainfuckError = error{
    LeftShiftUnderflow,
    RightShiftOverflow,
    UnmatchedOpenBracket,
    UnmatchedClosingBracket,
    InputError,
    OutputError,
};

const Command = union(enum) {
    Right: usize,
    Left: usize,
    Inc: u8,
    Dec: u8,
    Write: usize,
    Read,
    Open: usize,
    Close: usize,
};
const Program = []const Command;

fn tokenCounts(code: anytype) ![2]usize {
    @setEvalBranchQuota(20000);
    var count: usize = 0;
    var loops: usize = 0;
    var closes: usize = 0;
    var last_char: ?u8 = null;
    while (code.readByte()) |c| {
        switch (c) {
            '>', '<', '+', '-', '.', ',', '[', ']' => {
                defer last_char = c;
                switch (c) {
                    '>', '<', '+', '-' => if (last_char) |l| if (l == c) continue,
                    '[' => loops += 1,
                    ']' => closes += 1,
                    else => {},
                }
                count += 1;
            },
            else => {},
        }
    } else |_| {}
    if (loops > closes) {
        return error.UnmatchedOpenBracket;
    } else if (loops < closes) return error.UnmatchedClosingBracket;

    return .{ count, loops };
}

fn parseCode(
    program: *std.ArrayListUnmanaged(Command),
    loop_stack: *std.ArrayListUnmanaged(usize),
    code: anytype,
) !Program {
    var repeats: usize = 0;
    var last_command: ?Command = null;

    while (code.readByte()) |c| {
        const current_command: ?Command = switch (c) {
            '>' => .{ .Right = 1 },
            '<' => .{ .Left = 1 },
            '+' => .{ .Inc = 1 },
            '-' => .{ .Dec = 1 },
            '.' => .{ .Write = 1 },
            ',' => .Read,
            '[' => .{ .Open = undefined },
            ']' => .{ .Close = undefined },
            else => null,
        };

        if (current_command) |cmd| {
            if (last_command) |last| {
                if (std.meta.activeTag(cmd) == std.meta.activeTag(last)) {
                    repeats += 1;
                } else {
                    switch (last) {
                        .Right => |v| program.appendAssumeCapacity(.{ .Right = v + repeats }),
                        .Left => |v| program.appendAssumeCapacity(.{ .Left = v + repeats }),
                        .Inc => |v| program.appendAssumeCapacity(.{ .Inc = v + @as(u8, @intCast(repeats)) }),
                        .Dec => |v| program.appendAssumeCapacity(.{ .Dec = v + @as(u8, @intCast(repeats)) }),
                        .Write => |v| program.appendAssumeCapacity(.{ .Write = v + repeats }),
                        .Read => program.appendAssumeCapacity(.Read),
                        .Open => {
                            loop_stack.appendAssumeCapacity(program.items.len);
                            program.appendAssumeCapacity(.{ .Open = undefined });
                        },
                        .Close => {
                            const jump_index = loop_stack.pop();
                            program.items[jump_index] = .{ .Open = program.items.len };
                            program.appendAssumeCapacity(.{ .Close = jump_index });
                        },
                    }
                    repeats = 0;
                }
            }
            last_command = cmd;
        }
    } else |_| {}

    if (last_command) |last| program.appendAssumeCapacity(last);

    return program.items;
}

fn execute(reader: anytype, writer: anytype, program: Program) !void {
    var pc: usize = 0;
    var tape: [cells]u8 = [_]u8{0} ** cells;
    var head: usize = 0;
    while (pc < program.len) : (pc += 1) {
        switch (program[pc]) {
            .Right => |v| {
                head += v;
                if (head >= cells) return error.RightShiftOverflow;
            },
            .Left => |v| {
                if (v > head) return error.LeftShiftUnderflow;
                head -= v;
            },
            .Inc => |v| tape[head] +%= v,
            .Dec => |v| tape[head] -%= v,
            .Write => |v| for (0..v) |_| try writer.print("{c}", .{tape[head]}),
            .Read => tape[head] = reader.readByte() catch 0,
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

            const size, const loops = try tokenCounts(stream.reader());
            try stream.seekTo(0);

            var prog_buf: [size]Command = undefined;
            var prog_list = std.ArrayListUnmanaged(Command).initBuffer(&prog_buf);

            var loop_buf: [loops]usize = undefined;
            var loop_stack = std.ArrayListUnmanaged(usize).initBuffer(&loop_buf);

            const prog = parseCode(&prog_list, &loop_stack, stream.reader()) catch |err| {
                @compileError(std.fmt.comptimePrint("{s}", .{err}));
            };
            var program: [size]Command = undefined;
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

        const size, const loops = try tokenCounts(reader);
        try reader.seekTo(0);

        const prog_buf = try gpa.alloc(Command, size);
        defer gpa.free(prog_buf);
        var prog_list = std.ArrayListUnmanaged(Command).initBuffer(prog_buf);

        const loop_buf = try gpa.alloc(usize, loops);
        defer gpa.free(loop_buf);
        var loop_stack = std.ArrayListUnmanaged(usize).initBuffer(loop_buf);

        const program = try parseCode(&prog_list, &loop_stack, reader);

        try execute(stdin, stdout, program);
        try stdout.print("\n", .{});
    }
}
