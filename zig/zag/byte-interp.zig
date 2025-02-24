const std = @import("std");
const checkEqual = @import("utilities.zig").checkEqual;
const Process = @import("process.zig").Process;
const object = @import("zobject.zig");
const Object = object.Object;
const Nil = object.Nil;
const NotAnObject = object.NotAnObject;
const True = object.True;
const False = object.False;
const u64_MINVAL = object.u64_MINVAL;
const Context = @import("context.zig").Context;
const heap = @import("heap.zig");
const HeapPtr = heap.HeapPtr;
const Format = heap.Format;
const Age = heap.Age;
const class = @import("class.zig");
const sym = @import("symbol.zig").symbols;
const uniqueSymbol = object.uniqueSymbol;
const tailCall: std.builtin.CallModifier = .always_tail;
const print = std.debug.print;
const MethodReturns = void;
const execute = @import("execute.zig");
const TestExecution = execute.TestExecution;
const CompiledMethodPtr = *CompiledMethod;
const CompiledMethod = execute.CompiledMethod;
const CompileTimeMethod = execute.CompileTimeMethod;
const Code = execute.Code;

pub const ByteCode = enum(i8) {
    noop,
    branch,
    ifTrue,
    ifFalse,
    primFailure,
    dup,
    over,
    drop,
    pushLiteral,
    pushLiteral0,
    pushLiteral1,
    pushNil,
    pushTrue,
    pushFalse,
    popIntoTemp,
    popIntoTemp1,
    pushTemp,
    pushTemp1,
    lookupByteCodeMethod,
    send,
    call,
    callLocal,
    pushContext,
    returnTrampoline,
    returnWithContext,
    returnTop,
    returnNoContext,
    dnu,
    return_tos,
    failed_test,
    unexpected_return,
    dumpContext,
    p1,
    p2,
    p5,
    exit,
    _,
    const Self = @This();
    fn interpret(_pc: [*]const Code, _sp: [*]Object, process: *Process, _context: *Context, _: Object) MethodReturns {
        var pc: [*]align(1) const ByteCode = @as([*]align(1) const ByteCode, @ptrCast(_pc));
        var sp = _sp;
        var context = _context;
        var method = context.method;
        var references = (&method.header).arrayAsSlice(Object) catch unreachable;
        const inlines = @import("primitives.zig").inlines;
        interp: while (true) {
            const code = pc[0];
            std.debug.print("interp: ", .{});
            std.debug.print("interp: [{*}]: {}\n", .{ pc, code });
            pc += 1;
            while (true) {
                switch (code) {
                    .noop => {
                        continue :interp;
                    },
                    .branch => {
                        break; // to common code
                    },
                    .ifTrue => {
                        const v = sp[0];
                        sp += 1;
                        if (False.equals(v)) {
                            pc += 1;
                            continue :interp;
                        }
                        if (!True.equals(v)) @panic("non boolean");
                        break; // to branch
                    },
                    .ifFalse => {
                        const v = sp[0];
                        sp += 1;
                        if (True.equals(v)) {
                            pc += 1;
                            continue :interp;
                        }
                        if (!False.equals(v)) @panic("non boolean");
                        break; // to branch
                    },
                    .dup => {
                        sp -= 1;
                        sp[0] = sp[1];
                        continue :interp;
                    },
                    .over => {
                        sp -= 1;
                        sp[0] = sp[2];
                        continue :interp;
                    },
                    .drop => {
                        sp += 1;
                        continue :interp;
                    },
                    .pushLiteral => {
                        sp -= 1;
                        sp[0] = references[pc[0].u()];
                        pc += 1;
                        continue :interp;
                    },
                    .pushLiteral0 => {
                        sp -= 1;
                        sp[0] = Object.from(0);
                        continue :interp;
                    },
                    .pushTrue => {
                        sp -= 1;
                        sp[0] = True;
                        continue :interp;
                    },
                    .pushContext => {
                        method = @as(CompiledMethodPtr, @ptrFromInt(@intFromPtr(pc - pc[0].u()) - @sizeOf(Code) - CompiledMethod.codeOffset));
                        references = (&method.header).arrayAsSlice(Object) catch unreachable;
                        const stackStructure = method.stackStructure;
                        const locals = stackStructure.h0;
                        const maxStackNeeded = stackStructure.h1;
                        const selfOffset = stackStructure.l2;
                        const ctxt = context.push(sp, process, method, locals, maxStackNeeded, selfOffset);
                        ctxt.setNPc(interpret);
                        sp = ctxt.asObjectPtr();
                        context = ctxt;
                        pc += 1;
                        continue :interp;
                    },
                    .pushTemp => {
                        sp -= 1;
                        sp[0] = context.getTemp(pc[0].u() - 1);
                        pc += 1;
                        continue :interp;
                    },
                    .pushTemp1 => {
                        sp -= 1;
                        sp[0] = context.getTemp(0);
                        continue :interp;
                    },
                    .popIntoTemp => {
                        context.setTemp(pc[0].u(), sp[0]);
                        sp += 1;
                        pc += 1;
                        continue :interp;
                    },
                    .popIntoTemp1 => {
                        context.setTemp(0, sp[0]);
                        sp += 1;
                        continue :interp;
                    },
                    .returnWithContext => {
                        const result = context.pop(process);
                        const newSp = result.sp;
                        const callerContext = result.ctxt;
                        return @call(tailCall, callerContext.getNPc(), .{ callerContext.getTPc(), newSp, process, callerContext, Nil });
                    },
                    .returnNoContext => return @call(tailCall, context.getNPc(), .{ context.getTPc(), sp, process, context, Nil }),
                    .returnTop => {
                        const top = sp[0];
                        const result = context.pop(process);
                        const newSp = result.sp;
                        newSp[0] = top;
                        const callerContext = result.ctxt;
                        return @call(tailCall, callerContext.getNPc(), .{ callerContext.getTPc(), newSp, process, callerContext, Nil });
                    },
                    .p1 => { // SmallInteger>>#+
                        sp[1] = inlines.p1(sp[1], sp[0]) catch {
                            pc += 1;
                            continue :interp;
                        };
                        sp += 1;
                        break;
                    },
                    .p2 => { // SmallInteger>>#+
                        sp[1] = inlines.p2(sp[1], sp[0]) catch {
                            pc += 1;
                            continue :interp;
                        };
                        sp += 1;
                        break;
                    },
                    .p5 => { // SmallInteger>>#<=
                        sp[1] = Object.from(inlines.p5(sp[1], sp[0]) catch @panic("<= error"));
                        sp += 1;
                        break; // to branch
                    },
                    .callLocal => {
                        context.setTPc(asCodePtr(pc + 1));
                        const offset = pc[0].i();
                        if (offset >= 0) pc += 1 + @as(u64, @intCast(offset)) else pc -= @as(u64, @intCast(@as(i32, -offset) - 1));
                        continue :interp;
                    },
                    .exit => @panic("fell off the end"),
                    else => {
                        var buf: [100]u8 = undefined;
                        @panic(std.fmt.bufPrint(buf[0..], "unexpected bytecode {}", .{code}) catch unreachable);
                    },
                }
            }
            const offset = pc[0].i();
            if (offset >= 0) {
                pc = pc + 1 + @as(u64, @intCast(offset));
                continue;
            }
            if (offset == -1) {
                @panic("return branch");
            }
            pc = pc + 1 - @as(u64, @intCast(-offset));
        }
    }
    inline fn i(self: Self) i8 {
        return @intFromEnum(self);
    }
    inline fn u(self: Self) u8 {
        return @as(u8, @bitCast(self.i()));
    }
    inline fn int(v: i8) ByteCode {
        return @as(ByteCode, @enumFromInt(v));
    }
    inline fn uint(v: u8) ByteCode {
        return int(@as(i8, @bitCast(v)));
    }
    inline fn asCodePtr(self: [*]const Self) [*]const Code {
        @setRuntimeSafety(false);
        return @as([*]const Code, @ptrFromInt(@intFromPtr(self)));
    }
    var methods: [128]CompiledMethodPtr = undefined;
    var nMethods = 0;
    fn findMethod(search: CompiledMethodPtr) i8 {
        for (methods[0..nMethods], 0..) |v, index| {
            if (search == v)
                return @as(i8, @intCast(index));
        }
        methods[nMethods] = search;
        nMethods += 1;
        return nMethods - 1;
    }
};
fn countNonLabels(comptime tup: anytype) usize {
    var n = 1;
    inline for (tup) |field| {
        switch (@TypeOf(field)) {
            Object => {
                n += 1;
            },
            @TypeOf(null) => {
                n += 1;
            },
            comptime_int, comptime_float => {
                n += 1;
            },
            ByteCode => {
                n += 1;
            },
            else => switch (@typeInfo(@TypeOf(field))) {
                .Pointer => |pointer| {
                    if (@hasField(pointer.child, "len") and field[0] != ':') n = n + 1;
                },
                else => {
                    n = n + 1;
                },
            },
        }
    }
    return n;
}
fn convertCountSizes(comptime counts: execute.CountSizes) execute.CountSizes {
    return .{
        .codes = (counts.codes + 7) / 8,
        .refs = counts.refs + counts.objects,
        .objects = 0,
    };
}
pub fn compileByteCodeMethod(name: Object, comptime locals: comptime_int, comptime maxStack: comptime_int, comptime tup: anytype) CompileTimeMethod(convertCountSizes(execute.countNonLabels(tup))) {
    @setEvalBranchQuota(20000);
    const counts = comptime execute.countNonLabels(tup);
    const methodType = CompileTimeMethod(convertCountSizes(counts));
    var method = methodType.init(name, locals, maxStack);
    method.code[0] = Code.prim(ByteCode.interpret);
    const code = @as([*]ByteCode, @ptrFromInt(@intFromPtr(&method.code[1])));
    comptime var n = 0;
    inline for (tup) |field| {
        switch (@TypeOf(field)) {
            Object => {
                code[n] = ByteCode.uint(@as(u8, @intCast(method.findObject(field))));
                n += 1;
            },
            @TypeOf(null) => {
                code[n] = ByteCode.int(0);
                n += 1;
            },
            comptime_int => {
                code[n] = ByteCode.int(field);
                n += 1;
            },
            ByteCode => {
                code[n] = field;
                n += 1;
            },
            else => {
                comptime var found = false;
                switch (@typeInfo(@TypeOf(field))) {
                    .Pointer => {
                        if (field[0] == ':') {
                            found = true;
                        } else if (field.len == 1 and field[0] == '^') {
                            code[n] = ByteCode.uint(n);
                            n = n + 1;
                            found = true;
                        } else if (field.len == 1 and field[0] == '*') {
                            code[n] = ByteCode.int(-1);
                            n = n + 1;
                            found = true;
                        } else if (field.len >= 1 and field[0] >= '0' and field[0] <= '9') {
                            code[n] = ByteCode.ref(execute.intOf(field[0..]));
                            n += 1;
                            found = true;
                        } else {
                            comptime var lp = 0;
                            inline for (tup) |t| {
                                if (@TypeOf(t) == ByteCode) lp += 1 else switch (@typeInfo(@TypeOf(t))) {
                                    .Pointer => |tPointer| {
                                        if (@hasField(tPointer.child, "len") and t[0] == ':') {
                                            if (comptime std.mem.endsWith(u8, t, field)) {
                                                code[n] = ByteCode.int(lp - n - 1);
                                                n += 1;
                                                found = true;
                                            }
                                        } else lp += 1;
                                    },
                                    else => {
                                        lp += 1;
                                    },
                                }
                            }
                            if (!found) @compileError("missing label: \"" ++ field ++ "\"");
                        }
                    },
                    else => {},
                }
                if (!found) @compileError("don't know how to handle \"" ++ @typeName(@TypeOf(field)) ++ "\"");
            },
        }
    }
    code[n] = ByteCode.exit;
    //    method.print();
    return method;
}
const b = ByteCode;
test "compiling method" {
    const expectEqual = std.testing.expectEqual;
    const mref = comptime uniqueSymbol(42);
    var m = compileByteCodeMethod(Nil, 0, 0, .{ ":abc", b.return_tos, "def", True, comptime Object.from(42), ":def", "abc", "*", "^", 3, mref, Nil });
    //    const mcmp = m.asCompiledMethodPtr();
    //    m.update(mref,mcmp);
    var t = m.code[0..];
    for (m.code, 0..) |v, idx| {
        std.debug.print("t[{}] = {}\n", .{ idx, v });
    }
    try expectEqual(t.len, 11);
    try expectEqual(t[0], b.return_tos);
    try expectEqual(t[1].i(), 2);
    //try expectEqual(t[2].o(),True);
    //try expectEqual(t[3].o(),Object.from(42));
    try expectEqual(t[4].i(), -5);
    try expectEqual(t[5].i(), -1);
    try expectEqual(t[6].i(), 6);
    //    try expectEqual(t[?].asMethodPtr(),mcmp);
    try expectEqual(t[7].i(), 3);
    //    try expectEqual(t[8].method,mcmp);
    try expectEqual(t[9].o(), Nil);
}
pub const TestByteCodeExecution = TestExecution(ByteCode, CompiledMethod);
test "simple return via TestByteCodeExecution" {
    const expectEqual = std.testing.expectEqual;
    var method = compileByteCodeMethod(sym.yourself, 0, 0, .{
        b.noop,
        b.pushLiteral,
        comptime Object.from(42),
        b.returnNoContext,
    });
    var te = TestByteCodeExecution.new();
    te.init();
    var objs = [_]Object{ Nil, True };
    var result = te.run(objs[0..], method.asCompiledMethodPtr());
    std.debug.print("result = {any}\n", .{result});
    try expectEqual(result.len, 3);
    try expectEqual(result[0], Object.from(42));
    try expectEqual(result[1], Nil);
    try expectEqual(result[2], True);
}
test "context return via TestByteCodeExecution" {
    const expectEqual = std.testing.expectEqual;
    var method = compileByteCodeMethod(sym.@"at:", 0, 0, .{
        b.noop,
        b.pushContext,
        "^",
        b.pushLiteral,
        comptime Object.from(42),
        b.returnWithContext,
    });
    var te = TestByteCodeExecution.new();
    te.init();
    var objs = [_]Object{ Nil, True };
    var result = te.run(objs[0..], method.asCompiledMethodPtr());
    std.debug.print("result = {any}\n", .{result});
    try expectEqual(result.len, 1);
    try expectEqual(result[0], True);
}
test "context returnTop via TestByteCodeExecution" {
    const expectEqual = std.testing.expectEqual;
    var method = compileByteCodeMethod(sym.yourself, 0, 0, .{
        b.noop,
        b.pushContext,
        "^",
        b.pushLiteral,
        comptime Object.from(42),
        b.returnTop,
    });
    var te = TestByteCodeExecution.new();
    te.init();
    var objs = [_]Object{ Nil, True };
    var result = te.run(objs[0..], method.asCompiledMethodPtr());
    std.debug.print("result = {any}\n", .{result});
    try expectEqual(result.len, 1);
    try expectEqual(result[0], Object.from(42));
}
test "simple executable" {
    const expectEqual = std.testing.expectEqual;
    var method = compileByteCodeMethod(sym.yourself, 0, 1, .{
        b.pushContext,            "^",
        ":label1",                b.pushLiteral,
        comptime Object.from(42), b.popIntoTemp,
        1,                        b.pushTemp1,
        b.pushLiteral0,           b.pushTrue,
        b.ifFalse,                "label3",
        b.branch,                 "label2",
        ":label3",                b.pushTemp,
        1,                        ":label4",
        b.returnWithContext,      ":label2",
        b.pushLiteral0,           b.branch,
        "label4",
    });
    var objs = [_]Object{Nil};
    var te = TestByteCodeExecution.new();
    te.init();
    const result = te.run(objs[0..], method.asCompiledMethodPtr());
    std.debug.print("result = {any}\n", .{result});
    try expectEqual(result.len, 1);
    try expectEqual(result[0], Object.from(0));
}
