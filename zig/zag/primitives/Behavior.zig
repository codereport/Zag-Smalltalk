const std = @import("std");
const execute = @import("../execute.zig");
const trace = execute.trace;
const Context = execute.Context;
const ContextPtr = *Context;
const Code = execute.Code;
const tailCall = execute.tailCall;
const compileMethod = execute.compileMethod;
const CompiledMethodPtr = execute.CompiledMethodPtr;
const Process = @import("../process.zig").Process;
const object = @import("../zobject.zig");
const Object = object.Object;
const Nil = object.Nil;
const True = object.True;
const False = object.False;
const u64_MINVAL = object.u64_MINVAL;
const Sym = @import("../symbol.zig").symbols;
const heap = @import("../heap.zig");
const MinSmallInteger: i64 = object.MinSmallInteger;
const MaxSmallInteger: i64 = object.MaxSmallInteger;

pub fn init() void {}

pub const inlines = struct {
    pub inline fn p71(self: Object, other: Object) !Object { // basicNew:
        _ = self;
        _ = other;
        //        return error.primitiveError;
        unreachable;
    }
};
pub const embedded = struct {
    const fallback = execute.fallback;
    pub fn @"new:"(pc: [*]const Code, sp: [*]Object, process: *Process, context: ContextPtr, selector: Object) [*]Object {
        sp[1] = inlines.p71(sp[1], sp[0]) catch return @call(tailCall, fallback, .{ pc, sp, process, context, Sym.@"new:" });
        return @call(tailCall, pc[0].prim, .{ pc + 1, sp + 1, process, context, selector });
    }
};
pub const primitives = struct {
    pub fn p71(pc: [*]const Code, sp: [*]Object, process: *Process, context: ContextPtr, selector: Object) [*]Object { // new:
        _ = .{ pc, sp, process, context, selector };
        unreachable;
    }
};
const p = struct {
    usingnamespace execute.controlPrimitives;
    usingnamespace primitives;
};
fn testExecute(method: CompiledMethodPtr) []Object {
    var te = execute.TestExecution.new();
    te.init();
    var objs = [_]Object{};
    var result = te.run(objs[0..], method);
    std.debug.print("result = {any}\n", .{result});
    return result;
}
