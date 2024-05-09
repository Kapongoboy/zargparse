//! The zargparse module attempts to emulate the user-friendly command-line
//! parsing module from python, zarparse. Using the simple to understand primitives
//! you can easily define the arguments your program can accept.
//!
//! The module is still
//! experimental and help, usage and invalid argument error messages are still in
//! the works.

const std = @import("std");

/// The main primitive of the module, the ParserArg struct is used to add arguments
/// to your programs argument parser
const ParserArg = struct {
    const ArgType = enum {
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

const ArgumentParser = struct {
    const Self = @This();

    const ParserError = error{
        InvalidArgument,
        MissingArgument,
        ArgumentNotFound,
        ArgumentTooLong,
    };

    arg_iter: std.process.ArgIterator,
    arg_table: std.StringHashMap(ParserArg),
    ally: std.mem.Allocator,

    pub fn init(a: std.mem.Allocator) !ArgumentParser {
        return ArgumentParser{
            .arg_iter = try std.process.ArgIterator.initWithAllocator(a),
            .arg_table = std.StringHashMap(ParserArg).init(a),
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

    ///  TODO have to figure how to mutate the name without corrupting the argument
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

    /// Adds an argument to the parser.
    /// Returns an Allocator.Error from the internal lookup table.
    /// Due to the current state of zig libraries, rather than ergonomic functions to build the ParserArg
    /// Struct, Instead a complete ParserArg struct is passed to the function.
    /// This lines up currently with the philosophy of the zig standard library but may change as some of the apis have.
    pub fn add_argument(self: *Self, options: ParserArg) !void {
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
};

test "ArgumentParser basic test" {
    var parser = try ArgumentParser.init(std.testing.allocator);
    defer parser.deinit();

    try parser.add_argument(ParserArg{
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

    try parser.add_argument(ParserArg{
        .name = "--test-dash",
        .help = "test help",
    });

    const arg = try parser.get("test_dash");

    try std.testing.expectEqual("--test-dash", arg.name);
}
