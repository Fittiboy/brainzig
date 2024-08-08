const std = @import("std");
const config = @import("config");

const cells: usize = 30_000;

const BrainfuckError = error{
    LeftShiftUnderflow,
    RightShiftOverflow,
    UnmatchedOpenBracket,
    UnmatchedClosingBracket,
};

const Command = union(enum) { Right, Left, Inc, Dec, Write, Read, Open: usize, Close: usize };
const Program = []const Command;

fn tokenCounts(code: anytype) ![2]usize {
    @setEvalBranchQuota(20000);
    var count: usize = 0;
    var loops: usize = 0;
    var closes: usize = 0;
    while (code.readByte()) |c| {
        switch (c) {
            '>', '<', '+', '-', '.', ',' => count += 1,
            '[' => {
                count += 1;
                loops += 1;
            },
            ']' => {
                count += 1;
                closes += 1;
            },
            else => {},
        }
    } else |_| {}
    if (loops > closes) {
        return error.UnmatchedOpenBracket;
    } else if (loops < closes) return error.UnmatchedClosingBracket;

    return .{ count, loops };
}

fn parseCode(program: *std.ArrayListUnmanaged(Command), loop_stack: *std.ArrayListUnmanaged(usize), code: anytype) !Program {
    while (code.readByte()) |c| {
        switch (c) {
            '>' => program.appendAssumeCapacity(.Right),
            '<' => program.appendAssumeCapacity(.Left),
            '+' => program.appendAssumeCapacity(.Inc),
            '-' => program.appendAssumeCapacity(.Dec),
            '.' => program.appendAssumeCapacity(.Write),
            ',' => program.appendAssumeCapacity(.Read),
            '[' => {
                loop_stack.appendAssumeCapacity(program.items.len);
                program.appendAssumeCapacity(.{ .Open = undefined });
            },
            ']' => {
                const jump_index = loop_stack.pop();
                program.items[jump_index] = .{ .Open = program.items.len };
                program.appendAssumeCapacity(.{ .Close = jump_index });
            },
            else => {},
        }
    } else |_| {}
    return program.items;
}

fn execute(reader: anytype, writer: anytype, program: Program) !void {
    var pc: usize = 0;
    var tape: [cells]u8 = [_]u8{0} ** cells;
    var head: usize = 0;
    while (pc < program.len) : (pc += 1) {
        switch (program[pc]) {
            .Right => {
                head += 1;
                if (head >= cells) return error.RightShiftOverflow;
            },
            .Left => {
                head, const overflow = @subWithOverflow(head, 1);
                if (overflow == 1) return error.LeftShiftUnderflow;
            },
            .Inc => tape[head] +%= 1,
            .Dec => tape[head] -%= 1,
            .Write => try writer.print("{c}", .{tape[head]}),
            .Read => tape[head] = try reader.readByte(),
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
            file: struct {
                const File = std.fs.File;
                file: File,
                reader: std.io.Reader(File, std.posix.ReadError, File.read),
            },
            stream: struct {
                const FBS = std.io.FixedBufferStream([]u8);
                code: []u8,
                stream: FBS,
                reader: std.io.Reader(*FBS, error{}, FBS.read),
            },

            pub fn seekTo(self: *@This(), i: usize) !void {
                switch (self.*) {
                    .file => |f| try f.file.seekTo(i),
                    .stream => |*s| {
                        try s.stream.seekTo(i);
                        s.reader = s.stream.reader();
                    },
                }
            }

            pub fn readByte(self: @This()) !u8 {
                switch (self) {
                    inline else => |r| return r.reader.readByte(),
                }
            }

            pub fn free(self: @This(), allocator: std.mem.Allocator) void {
                switch (self) {
                    .file => |file| file.file.close(),
                    .stream => |r| allocator.free(r.code),
                }
            }
        };

        const args = try std.process.argsAlloc(gpa);
        defer std.process.argsFree(gpa, args);
        var reader = if (args.len > 1) blk: {
            const filename = args[1];
            const file = try std.fs.cwd().openFile(filename, .{});
            const reader = file.reader();
            break :blk CodeReader{ .file = .{ .file = file, .reader = reader } };
        } else blk: {
            const code = try stdin.readAllAlloc(gpa, std.math.maxInt(usize));
            var stream = std.io.fixedBufferStream(code);
            const reader = stream.reader();
            break :blk CodeReader{ .stream = .{ .code = code, .stream = stream, .reader = reader } };
        };
        defer reader.free(gpa);

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
