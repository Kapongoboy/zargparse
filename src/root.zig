//! The zargparse module attempts to emulate the user-friendly command-line
//! parsing module from python, zarparse. Using the simple to understand primitives
//! you can easily define the arguments your program can accept.
//!
//! The module is still
//! experimental and help, usage and invalid argument error messages are still in
//! the works.

const std = @import("std");
const stdout = std.io.getStdOut().writer();

/// The main primitive of the module, the ParserArg struct is used to add arguments
/// to your programs argument parser
pub const ParserArg = struct {
    pub const ArgType = enum {
        STRING,
        INT,
        FLOAT,
        BOOL,
    };

    name: []const u8,
    help: []const u8,
    default: ?[]const u8 = null,
    action: ?[]const u8 = null,
    metavar: ?[]const u8 = null,
    arg_type: ArgType = ArgType.STRING,
};

pub const ArgumentParser = struct {
    const Self = @This();

    const ParserError = error{
        InvalidArgument,
        MissingArgument,
        ArgumentNotFound,
        ArgumentTooLong,
    };

    const Value = union {
        str: []const u8,
        num: i64,
        flt: f64,
        boolean: bool,
    };

    arg_iter: std.process.ArgIterator,
    arg_table: std.StringHashMap(ParserArg),
    program_store: std.StringHashMap(Value),
    ally: std.mem.Allocator,

    pub fn init(a: std.mem.Allocator) !ArgumentParser {
        return ArgumentParser{
            .arg_iter = try std.process.ArgIterator.initWithAllocator(a),
            .arg_table = std.StringHashMap(ParserArg).init(a),
            .program_store = std.StringHashMap(Value).init(a),
            .ally = a,
        };
    }

    pub fn deinit(self: *Self) void {
        defer {
            self.arg_iter.deinit();
            self.arg_table.deinit();
        }

        var iter = self.arg_table.keyIterator();

        while (iter.next()) |key| {
            self.ally.free(key.*);
        }
    }

    ///  Fixed memory issue, undecided whether returning index is the best type
    fn parseNameToMapKey(buffer: []u8, name: []const u8) !usize {
        var buffer_idx: usize = 0;

        if (name.len == 0) {
            return ParserError.InvalidArgument;
        }

        if (name.len > 512) {
            return ParserError.ArgumentTooLong;
        }

        for (name, 0..) |c, idx| {
            if ((c == '-') and (idx < 2)) {
                continue;
            }

            if (c == '-') {
                buffer[buffer_idx] = '_';
                buffer_idx += 1;
            } else {
                buffer[buffer_idx] = c;
                buffer_idx += 1;
            }
        }

        return buffer_idx;
    }

    /// This probably needs some care
    fn flagToString(str: []const u8) ![]u8 {
        var buf: [512]u8 = undefined;
        const len: usize = try parseNameToMapKey(&buf, str);
        return buf[0..len];
    }

    /// Adds an argument to the parser.
    /// Returns an Allocator.Error from the internal lookup table.
    /// Due to the current state of zig libraries, rather than ergonomic functions to build the ParserArg
    /// Struct, Instead a complete ParserArg struct is passed to the function.
    /// This lines up currently with the philosophy of the zig standard library but may change as some of the apis have.
    pub fn addArgument(self: *Self, options: ParserArg) !void {
        var buf: [512]u8 = undefined;
        const len: usize = try parseNameToMapKey(&buf, options.name);
        try self.arg_table.put(try self.ally.dupe(u8, buf[0..len]), options);
    }

    /// The get for the hashmap might be broken as this is a kind of hack to get the value
    pub fn get(self: *Self, key: []const u8) ParserError!ParserArg {
        if (self.arg_table.get(key)) |arg| {
            return arg;
        } else return ParserError.ArgumentNotFound;
    }

    // fn checkFlag() bool {} // TODO will need when having unqualified values as an option

    /// MAJOR TODO, This function is the heart of the parser
    /// and will abstract away putting everything in the right place
    /// Still deciding on an optimal design for it's functionality;
    pub fn parseArgs(self: *Self) !void {
        while (self.arg_iter.next()) |arg| {
            const arg_internal = self.get(try flagToString(arg)) catch |e| {
                try stdout.print("Argument {s} was not found as valid for the program, use -h to get the valid argument, error {e}\n", .{ arg, e });
                return;
            };

            if (std.mem.eql(u8, arg_internal.action, "store")) {
                if (self.arg_iter.next()) |val| {
                    switch (arg_internal.arg_type) {
                        ParserArg.ArgType.STRING => {
                            self.program_store.put(try self.ally.dupe(u8, try flagToString(arg_internal.name)), .{ .str = val });
                        },
                        ParserArg.ArgType.INT => {
                            const num = try std.fmt.parseInt(i64, val, 10);
                            self.program_store.put(try self.ally.dupe(u8, try flagToString(arg_internal.name)), .{ .num = num });
                        },
                        ParserArg.ArgType.FLOAT => {
                            const flt = try std.fmt.parseFloat(f64, val);
                            self.program_store.put(try self.ally.dupe(u8, try flagToString(arg_internal.name)), .{ .flt = flt });
                        },
                        ParserArg.ArgType.BOOL => {
                            const result: bool = undefined;

                            if (std.mem.eql(u8, val, "true") or std.mem.eql(u8, val, "yes") or std.mem.eql(u8, val, "1")) {
                                result = true;
                            } else if (std.mem.eql(u8, val, "false") or std.mem.eql(u8, val, "no") or std.mem.eql(u8, val, "0")) {
                                result = false;
                            } else {
                                try stdout.print("Argument {s} requires a boolean value\n", .{arg});
                                return;
                            }
                            self.program_store.put(try self.ally.dupe(u8, try flagToString(arg_internal.name)), .{ .boolean = result });
                        },
                    }
                } else {
                    try stdout.print("Argument {s} requires a value\n", .{arg});
                    return;
                }
            }
        }
    }
};

test "ArgumentParser basic test" {
    var parser = try ArgumentParser.init(std.testing.allocator);
    defer parser.deinit();

    try parser.addArgument(ParserArg{
        .name = "test",
        .help = "test help",
    });

    const arg = try parser.get("test");

    try std.testing.expectEqual("test", arg.name);
    try std.testing.expectEqual("test help", arg.help);
}

test "ArgumentParser dash string" {
    var parser = try ArgumentParser.init(std.testing.allocator);
    defer parser.deinit();

    try parser.addArgument(ParserArg{
        .name = "--test-dash",
        .help = "test help",
    });

    const arg = try parser.get("test_dash");

    try std.testing.expectEqual("--test-dash", arg.name);
}
