const std = @import("std");

/// Helper function that returns a function type with ArgType prepended to the
/// function's args.
/// Example:
///     Func    = fn(usize) void
///     ArgType = *Instance
///     --------------------------
///     Result  = fn(*Instance, usize) void
fn PrependFnArg(Func: type, ArgType: type) type {
    const fn_info = @typeInfo(Func);
    if (fn_info != .@"fn") @compileError("First argument must be a function type");
    const function_info = fn_info.@"fn";

    comptime var new_param_types: [function_info.param_types.len + 1]?type = undefined;
    comptime var new_param_attrs: [function_info.param_attrs.len + 1]std.builtin.Type.Fn.ParamAttributes = undefined;
    new_param_types[0] = ArgType;
    new_param_attrs[0] = .{};
    for (function_info.param_types, function_info.param_attrs, 0..) |param_type, param_attrs, i| {
        new_param_types[i + 1] = param_type;
        new_param_attrs[i + 1] = param_attrs;
    }

    return @Type(.{
        .@"fn" = .{
            .attrs = function_info.attrs,
            .return_type = function_info.return_type,
            .param_types = &new_param_types,
            .param_attrs = &new_param_attrs,
        },
    });
}

fn isGenericFn(comptime function_info: std.builtin.Type.Fn) bool {
    if (function_info.return_type == null) return true;
    for (function_info.param_types) |param_type| {
        if (param_type == null) return true;
    }
    return false;
}

// External Generic Interface (CallbackInterface)
pub fn CallbackInterface(comptime Func: type) type {
    const func_info = @typeInfo(Func);
    if (func_info != .@"fn") @compileError("CallbackInterface expects a function type");
    if (isGenericFn(func_info.@"fn")) @compileError("CallbackInterface does not support generic functions");
    if (func_info.@"fn".attrs.varargs) @compileError("CallbackInterface does not support var_args functions");

    const ArgsTupleType = std.meta.ArgsTuple(Func);
    const ReturnType = func_info.@"fn".return_type.?;
    const FnPtrType = *const fn (ctx: ?*const anyopaque, args: ArgsTupleType) ReturnType;

    return struct {
        ctx: ?*const anyopaque,
        callFn: FnPtrType,
        pub const Interface = @This();

        pub fn call(self: Interface, args: ArgsTupleType) ReturnType {
            if (self.ctx == null) @panic("Called uninitialized CallbackInterface");
            if (ReturnType == void) {
                self.callFn(self.ctx, args);
            } else {
                return self.callFn(self.ctx, args);
            }
        }
    };
}

pub fn Bind(Instance: type, Func: type) type {
    const func_info = @typeInfo(Func);
    if (func_info != .@"fn") @compileError("Bind expects a function type as second parameter");
    if (isGenericFn(func_info.@"fn")) @compileError("Binding generic functions is not supported");
    if (func_info.@"fn".attrs.varargs) @compileError("Binding var_args functions is not currently supported");

    const ReturnType = func_info.@"fn".return_type.?;
    const OriginalParamTypes = func_info.@"fn".param_types;
    const ArgsTupleType = std.meta.ArgsTuple(Func);
    const InstanceMethod = PrependFnArg(Func, *Instance);
    const InterfaceType = CallbackInterface(Func);

    return struct {
        instance: *Instance,
        method: *const InstanceMethod,
        pub const BoundFunction = @This();

        fn callMethod(self: *const BoundFunction, args: anytype) ReturnType {
            return @call(.auto, self.method, .{self.instance} ++ args);
        }

        // Trampoline function used by CallbackInterface.
        fn callDetached(ctx: ?*const anyopaque, args: ArgsTupleType) ReturnType {
            if (ctx == null) @panic("callDetached called with null context");
            const self: *const BoundFunction = @ptrCast(@alignCast(ctx.?));

            return self.callMethod(args);
        }

        pub fn interface(self: *const BoundFunction) InterfaceType {
            return .{ .ctx = @ptrCast(self), .callFn = &callDetached };
        }

        // Direct call convenience method using runtime tuple construction
        pub fn call(self: *const BoundFunction, args: anytype) ReturnType {
            // 1. Verify 'args' is the correct ArgsTupleType or compatible tuple literal
            // (This check could be more robust if needed)
            if (@TypeOf(args) != ArgsTupleType) {
                // Attempt reasonable check for tuple literal compatibility
                if (@typeInfo(@TypeOf(args)) != .@"struct" or !@typeInfo(@TypeOf(args)).@"struct".is_tuple) {
                    @compileError(std.fmt.comptimePrint(
                        "Direct .call expects arguments as a tuple literal compatible with {}, found type {}",
                        .{ ArgsTupleType, @TypeOf(args) },
                    ));
                }
                // Further check field count/types if necessary
                const arg_info = @typeInfo(@TypeOf(args)).@"struct";
                if (arg_info.field_names.len != OriginalParamTypes.len) {
                    @compileError(std.fmt.comptimePrint(
                        "Direct .call tuple literal has wrong number of arguments (expected {}, got {}) for {}",
                        .{ OriginalParamTypes.len, arg_info.field_names.len, ArgsTupleType },
                    ));
                }
                // Could add type checks per field here too
            }

            return self.callMethod(args);
        }

        pub fn init(instance_: *Instance, method_: *const InstanceMethod) BoundFunction {
            return .{ .instance = instance_, .method = method_ };
        }
    };
}

const testing = std.testing;

test "Bind Direct Call" {
    const Person = struct {
        name: []const u8,
        _buf: [1024]u8 = undefined,
        pub fn speak(self: *@This(), msg: []const u8) ![]const u8 {
            return std.fmt.bufPrint(&self._buf, "{s}: {s}", .{ self.name, msg });
        }
    };
    const FuncSig = fn ([]const u8) anyerror![]const u8;
    var p = Person{ .name = "Alice" };
    const bound = Bind(Person, FuncSig).init(&p, &Person.speak);
    const res = try bound.call(.{"Hi"}); // Pass tuple literal
    try testing.expectEqualStrings("Alice: Hi", res);
}

test "BindInterface Call (External)" {
    const Person = struct {
        name: []const u8,
        _buf: [1024]u8 = undefined,
        pub fn speak(self: *@This(), message: []const u8) ![]const u8 {
            return std.fmt.bufPrint(&self._buf, "{s} says: >>{s}!<<\n", .{ self.name, message });
        }
    };
    const CallBack = fn ([]const u8) anyerror![]const u8;
    var alice: Person = .{ .name = "Alice" };
    const BoundSpeak = Bind(Person, CallBack);
    const bound_speak = BoundSpeak.init(&alice, &Person.speak);
    var alice_interface = bound_speak.interface();
    const greeting = try alice_interface.call(.{"Hello"}); // Pass tuple literal
    try testing.expectEqualStrings("Alice says: >>Hello!<<\n", greeting);
}

test "BindInterface Polymorphism (External)" {
    const Person = struct {
        name: []const u8,
        _buf: [1024]u8 = undefined,
        pub fn speak(self: *@This(), message: []const u8) ![]const u8 {
            return std.fmt.bufPrint(&self._buf, "{s} says: >>{s}!<<\n", .{ self.name, message });
        }
    };
    const Dog = struct {
        name: []const u8,
        _buf: [1024]u8 = undefined,
        pub fn bark(self: *@This(), message: []const u8) ![]const u8 {
            return std.fmt.bufPrint(&self._buf, "{s} barks: >>{s}!<<\n", .{ self.name, message });
        }
    };
    const CallBack = fn ([]const u8) anyerror![]const u8;
    const CbInterface = CallbackInterface(CallBack);

    var alice: Person = .{ .name = "Alice" };
    const bound_alice = Bind(Person, CallBack).init(&alice, &Person.speak);
    const alice_interface = bound_alice.interface();

    var bob: Dog = .{ .name = "Bob" };
    const bound_bob = Bind(Dog, CallBack).init(&bob, &Dog.bark);
    const bob_interface = bound_bob.interface();

    const interfaces = [_]CbInterface{ alice_interface, bob_interface };
    var results: [2][]const u8 = undefined;
    for (interfaces, 0..) |iface, i| {
        results[i] = try iface.call(.{"Test"});
    } // Pass tuple literal

    try testing.expectEqualStrings("Alice says: >>Test!<<\n", results[0]);
    try testing.expectEqualStrings("Bob barks: >>Test!<<\n", results[1]);
}

test "Void Return Type (External Interface)" {
    var counter: u32 = 0;
    const Counter = struct {
        count: *u32,
        pub fn increment(self: *@This(), amount: u32) void {
            self.count.* += amount;
        }
    };
    const Decrementer = struct {
        count: *u32,
        pub fn decrement(self: *@This(), amount: u32) void {
            self.count.* -= amount;
        }
    };
    const IncrementFn = fn (u32) void;
    const IncInterface = CallbackInterface(IncrementFn);

    var my_counter = Counter{ .count = &counter };
    const bound_inc = Bind(Counter, IncrementFn).init(&my_counter, &Counter.increment);
    bound_inc.call(.{5});
    try testing.expectEqual(@as(u32, 5), counter);

    var my_dec = Decrementer{ .count = &counter };
    const bound_dec = Bind(Decrementer, IncrementFn).init(&my_dec, &Decrementer.decrement);

    const iface1 = bound_inc.interface();
    const iface2 = bound_dec.interface();
    const void_ifaces = [_]IncInterface{ iface1, iface2 };

    void_ifaces[0].call(.{3}); // counter = 5 + 3 = 8
    try testing.expectEqual(@as(u32, 8), counter);
    void_ifaces[1].call(.{2}); // counter = 8 - 2 = 6
    try testing.expectEqual(@as(u32, 6), counter);
}
