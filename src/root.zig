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
///
/// The only required fields are `name` and `help`, the rest are optional.
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
    action: []const u8 = "store",
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
        ParserLocked,
    };

    const Value = union {
        str: []const u8,
        num: i64,
        flt: f64,
        boolean: bool,
    };

    arg_table: std.StringHashMap(ParserArg),
    program_store: std.StringHashMap(Value),
    locked: bool = false,
    ally: std.mem.Allocator,

    pub fn init(a: std.mem.Allocator) ArgumentParser {
        return ArgumentParser{
            .arg_table = std.StringHashMap(ParserArg).init(a),
            .program_store = std.StringHashMap(Value).init(a),
            .ally = a,
        };
    }

    pub fn deinit(self: *Self) void {
        defer {
            self.program_store.deinit();
            self.arg_table.deinit();
        }

        var iter = self.arg_table.keyIterator();

        while (iter.next()) |key| {
            self.ally.free(key.*);
        }

        var piter = self.program_store.keyIterator();

        while (piter.next()) |key| {
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
        if (self.locked) {
            return ParserError.ParserLocked;
        }

        var buf: [512]u8 = undefined;
        const len: usize = try parseNameToMapKey(&buf, options.name);
        try self.arg_table.put(try self.ally.dupe(u8, buf[0..len]), options);
    }

    /// The get for the hashmap might be broken as this is a kind of hack to get the value
    pub fn getArg(self: *Self, key: []const u8) ParserError!ParserArg {
        if (self.arg_table.get(key)) |arg| {
            return arg;
        } else return ParserError.ArgumentNotFound;
    }

    pub fn getValue(self: *Self, key: []const u8) ?Value {
        return self.program_store.get(key);
    }

    // fn checkFlag() bool {} // TODO will need when having unqualified values as an option

    /// Still a work in progress, This function is the heart of the parser
    /// and abstractes away putting everything in the right place
    /// Import notes:
    /// - Arguments of the kind "--ice" will be stored as "ice"
    /// - Arguments of the kind "--ice-cream" will be stored as "ice_cream"
    /// It is important to remember that in order to get the right value of an argument
    ///
    /// Arguments are store by default, therefore for args that are store but
    /// have no pair value, the value is set as a boolean with the value true
    pub fn parseArgs(self: *Self, args: [][]const u8) !void {
        if (self.locked) {
            return ParserError.ParserLocked;
        }

        var idx: usize = 0;

        while (idx < args.len) {
            const arg = args[idx];
            var buf: [512]u8 = undefined;
            const len: usize = try parseNameToMapKey(&buf, arg);

            const arg_internal = self.getArg(buf[0..len]) catch |e| {
                std.debug.print("Argument {s} was not found as valid for the program, use -h to get the valid argument, error {}\n", .{ arg, e });
                return;
            };

            if (std.mem.eql(u8, arg_internal.action, "store")) {
                idx += 1;
                if (idx < args.len) {
                    const val = args[idx];

                    switch (arg_internal.arg_type) {
                        ParserArg.ArgType.STRING => {
                            try self.program_store.put(try self.ally.dupe(u8, buf[0..len]), .{ .str = val });
                        },
                        ParserArg.ArgType.INT => {
                            const num = try std.fmt.parseInt(i64, val, 10);
                            try self.program_store.put(try self.ally.dupe(u8, buf[0..len]), .{ .num = num });
                        },
                        ParserArg.ArgType.FLOAT => {
                            const flt = try std.fmt.parseFloat(f64, val);
                            try self.program_store.put(try self.ally.dupe(u8, buf[0..len]), .{ .flt = flt });
                        },
                        ParserArg.ArgType.BOOL => {
                            var result: bool = undefined;

                            if (std.mem.eql(u8, val, "true") or std.mem.eql(u8, val, "yes") or std.mem.eql(u8, val, "1")) {
                                result = true;
                            } else if (std.mem.eql(u8, val, "false") or std.mem.eql(u8, val, "no") or std.mem.eql(u8, val, "0")) {
                                result = false;
                            } else {
                                std.debug.print("Argument {s} requires a boolean value\n", .{arg});
                                return;
                            }
                            try self.program_store.put(try self.ally.dupe(u8, buf[0..len]), .{ .boolean = result });
                        },
                    }
                } else {
                    std.debug.print("Argument {s} requires a value\n", .{arg});
                    return;
                }
            } else {
                try self.program_store.put(try self.ally.dupe(u8, buf[0..len]), .{ .boolean = true });
            }
            idx += 1;
        }

        self.locked = true;
    }
};

test "ArgumentParser basic test" {
    var parser = ArgumentParser.init(std.testing.allocator);
    defer parser.deinit();

    try parser.addArgument(ParserArg{
        .name = "test",
        .help = "test help",
    });

    const arg = try parser.getArg("test");

    try std.testing.expectEqual("test", arg.name);
    try std.testing.expectEqual("test help", arg.help);
}

test "ArgumentParser dash string" {
    var parser = ArgumentParser.init(std.testing.allocator);
    defer parser.deinit();

    try parser.addArgument(ParserArg{
        .name = "--test-dash",
        .help = "test help",
    });

    const arg = try parser.getArg("test_dash");

    try std.testing.expectEqual("--test-dash", arg.name);
}

test "Argument Parser parse arg str" {
    var parser = ArgumentParser.init(std.testing.allocator);
    defer parser.deinit();

    try parser.addArgument(ParserArg{
        .name = "repo",
        .metavar = "REPO",
        .arg_type = .STRING,
        .help = "path to the repository this will observe",
    });

    const first = "repo";
    const second = "/path/to/repo";

    var args_arr = [_][]const u8{ first, second };

    try parser.parseArgs(&args_arr);

    if (parser.getValue("repo")) |val| {
        try std.testing.expect(std.mem.eql(u8, "/path/to/repo", val.str));
    } else {
        std.debug.print("Value not found\n", .{});
        try std.testing.expect(false);
    }
}

test "Argument Parser parse arg int" {
    var parser = ArgumentParser.init(std.testing.allocator);
    defer parser.deinit();

    try parser.addArgument(ParserArg{
        .name = "--num-times",
        .arg_type = .INT,
        .help = "the number of times I want",
    });

    const first = "--num-times";
    const second = "12398";

    var args_arr = [_][]const u8{ first, second };

    try parser.parseArgs(&args_arr);

    if (parser.getValue("num_times")) |val| {
        try std.testing.expectEqual(val.num, 12398);
    } else {
        std.debug.print("Value not found\n", .{});
        try std.testing.expect(false);
    }
}

test "Argument Parser parse arg bool" {
    var parser = ArgumentParser.init(std.testing.allocator);
    defer parser.deinit();

    try parser.addArgument(ParserArg{
        .name = "--do-it-to-me",
        .arg_type = .BOOL,
        .help = "hit me baby one more time",
    });

    const first = "--do-it-to-me";
    const second = "no";

    var args_arr = [_][]const u8{ first, second };

    try parser.parseArgs(&args_arr);

    if (parser.getValue("do_it_to_me")) |val| {
        try std.testing.expect(!val.boolean);
    } else {
        std.debug.print("Value not found\n", .{});
        try std.testing.expect(false);
    }
}

test "Argument Parser parse arg float" {
    var parser = ArgumentParser.init(std.testing.allocator);
    defer parser.deinit();

    try parser.addArgument(ParserArg{
        .name = "--out-of-Space",
        .arg_type = .FLOAT,
        .help = "rolly rolly rolly got me star gazing",
    });

    const first = "--out-of-Space";
    const second = "3.14";

    var args_arr = [_][]const u8{ first, second };

    try parser.parseArgs(&args_arr);

    if (parser.getValue("out_of_Space")) |val| {
        try std.testing.expectEqual(val.flt, 3.14);
    } else {
        std.debug.print("Value not found\n", .{});
        try std.testing.expect(false);
    }
}

test "Argument Parser test lock" {
    var parser = ArgumentParser.init(std.testing.allocator);
    defer parser.deinit();

    try parser.addArgument(ParserArg{
        .name = "test",
        .help = "test",
    });

    const first = "test";
    const second = "test";

    var args_arr = [_][]const u8{ first, second };

    try parser.parseArgs(&args_arr);

    parser.addArgument(ParserArg{ .name = "another", .help = "another" }) catch |e| {
        try std.testing.expectEqual(e, ArgumentParser.ParserError.ParserLocked);
    };

    parser.parseArgs(&args_arr) catch |e| {
        try std.testing.expectEqual(e, ArgumentParser.ParserError.ParserLocked);
    };
}
