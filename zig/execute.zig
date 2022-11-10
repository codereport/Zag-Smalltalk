const std = @import("std");
const checkEqual = @import("utilities.zig").checkEqual;
const Thread = @import("thread.zig").Thread;
const object = @import("object.zig");
const Object = object.Object;
const Nil = object.Nil;
const NotAnObject = object.NotAnObject;
const True = object.True;
const False = object.False;
const u64_MINVAL = object.u64_MINVAL;
const heap = @import("heap.zig");
const HeapPtr = heap.HeapPtr;
pub const Hp = [*]heap.Header;
const Format = heap.Format;
const Age = heap.Age;
const class = @import("class.zig");
const sym = @import("symbol.zig").symbols;
pub const tailCall: std.builtin.CallOptions = .{.modifier = .always_tail};
const noInlineCall: std.builtin.CallOptions = .{.modifier = .never_inline};
pub const MethodReturns = void;
// union(enum) {
//     Normal: Object,
//     NonLocal,
//     ExceptionSignaled,
//     pub fn nonLocal(self : MethodReturns) bool {
//         return self>=MethodReturns.NonLocal;
//     }
// };
pub const ThreadedFn = fn(programCounter: [*]const Code, stackPointer: [*]Object, heapPointer: Hp, thread: *Thread, context: ContextPtr) MethodReturns;

pub const ContextPtr = *Context;
pub const Context = struct {
    header: heap.Header,
    tpc: [*]const Code, // threaded PC
    npc: ThreadedFn, // native PC - in Continuation Passing Style
    size: u64,
    prevCtxt: ContextPtr,
    method: CompiledMethodPtr,
    temps: [1]Object,
    const baseSize = @sizeOf(Context)/@sizeOf(Object) - 1;
    inline fn pop(self: ContextPtr, sp: [*]Object, thread: *Thread, itemsToDiscard: usize) struct {
        sp: [*]Object,
        ctxt: ContextPtr,
    } {
        if (self.isInStack(sp,thread))
            return .{.sp=self.asObjectPtr() + baseSize + itemsToDiscard,.ctxt=self.prevCtxt};
        const itemsToKeep = self.items[itemsToDiscard..];
        const newSp = thread.endOfStack() - itemsToKeep.len;
        for (itemsToKeep) | obj,index | {
            newSp[index] = obj;
        }
        return .{.sp=newSp,.ctxt=self.previous()};
    }
    inline fn push(self: ContextPtr, sp: [*]Object, hp: Hp, thread: *Thread, method: CompiledMethodPtr, locals: usize, maxStackNeeded: usize)  struct {
        hp: Hp,
        ctxt: ContextPtr,
    } {
        const newSp = sp - baseSize - locals;
        if (heap.arenaFree(newSp,hp)<5+maxStackNeeded) @panic("grow heap");
        const ctxt = @ptrCast(ContextPtr,@alignCast(@alignOf(Context),newSp));
        ctxt.prevCtxt = self;
        ctxt.method = method;
        for (ctxt.temps[0..locals]) |*local| {local.*=Nil;}
        if (thread.needsCheck()) @panic("grow heap2");
        return .{.hp=hp,.ctxt=ctxt};
    }
    fn convertToProperHeapObject(self: ContextPtr, sp: [*]Object, thread: *Thread) void {
        if (self.isInStack(sp,thread)) {
            self.header = heap.header(2, Format.object, class.Context_I,0,Age.stack);
            self.size = (@ptrToInt(self.prevCtxt)-@ptrToInt(self))/@sizeOf(Object)-5;
            std.debug.print("obj = 0x{x:0>16}\n",.{Object.from(self.prevCtxt).u()});
            self.prevCtxt = @intToPtr(ContextPtr,Object.from(self.prevCtxt).u());
            self.method = @intToPtr(CompiledMethodPtr,Object.from(self.method).u());
            self.prevCtxt.convertToProperHeapObject(sp, thread);
        }
    }
    fn init(objects: []Object,method: CompiledMethodPtr) ContextPtr {
        objects[0] = heap.header(2,Format.both,class.Context_I,@truncate(u24,@ptrToInt(objects.ptr)),Age.stack).o(); // header
        // objects[1] - tpc
        // objects[2] - npc
        objects[3] = @bitCast(Object,objects.len-baseSize + 2);
        objects[4] = Nil;
        objects[5] = Object.from(method);
        return @ptrCast(ContextPtr,@alignCast(@alignOf(ContextPtr),objects.ptr));
    }
    pub inline fn allTemps(self: ContextPtr) []Object {
        @setRuntimeSafety(false);
        return @ptrCast(heap.HeapConstPtr,self).indexables(Object);
    }
    inline fn getTPc(self: ContextPtr) [*]const Code {
        return self.tpc;
    }
    inline fn setTPc(self: ContextPtr, pc: [*]const Code) void {
        self.tpc = pc;
    }
    inline fn getNPc(self: ContextPtr) ThreadedFn {
        return self.npc;
    }
    inline fn setNPc(self: ContextPtr, pc: ThreadedFn) void {
        self.npc = pc;
    }
    inline fn isInStack(self: *Context, sp: [*]Object, thread: *Thread) bool {
        return @ptrToInt(sp)<@ptrToInt(self) and @ptrToInt(self)<@ptrToInt(thread.endOfStack());
    }
    inline fn getTemp(self: ContextPtr, n: usize) Object {
        @setRuntimeSafety(false);
        return self.temps[n];
    }
    inline fn setTemp(self: ContextPtr, n: usize, v: Object) void {
        @setRuntimeSafety(false);
        self.temps[n] = v;
    }
    pub inline fn previous(self: ContextPtr) ContextPtr {
        return self.prevCtxt.to(ContextPtr);
    }
    inline fn asHeapPtr(self : ContextPtr) HeapPtr {
        return @ptrCast(HeapPtr,self);
    }
    inline fn asObjectPtr(self : ContextPtr) [*]Object {
        return @ptrCast([*]Object,self);
    }
    inline fn fromObjectPtr(op: [*]Object) *Context {
        return @ptrCast(*Context,op);
    }
    fn size(self: ContextPtr, sp: [*]Object, thread: *Thread) usize {
        return ((if (self.isInStack(sp,thread))
                     @ptrToInt(self)
                     else
                     @ptrToInt(thread.endOfStack()))-@ptrToInt(sp))/@sizeOf(Object);
    }
    fn collectNursery(pc: [*]const Code, sp: [*]Object, hp: Hp, thread: *Thread, context: ContextPtr) Object {
        if (true) @panic("need to collect nursery");
        return @call(tailCall,push,.{pc,sp,hp,thread,context});
    }
    fn print(self: ContextPtr)void{ //,sp: [*]Object, thread: *Thread) void {
        const pr = std.debug.print;
        pr("Context: {} {any}\n",.{self.header,self.allTemps()});
//        if (self.prevCtxt) |ctxt| {ctxt.print(sp,thread);}
    }
};
fn TestResult(comptime s: comptime_int, comptime source: [s] Object) type {
    const size = Context.baseSize+source.len;
    return struct {
        thread: Thread,
        ctxt: [size]Object,
        const Self = @This();
        var result: []Object = &[0]Object{};
        fn init() Self {
            var objs:[size]Object = [_]Object{Nil}**Context.baseSize++source;
            var m = CompiledMethod.init(Nil);
            var ct = Context.init(objs[0..],&m);
            ct.setNPc(end);
            for (source) |src,idx|
                objs[Context.baseSize+idx] = src;
            return Self {
                .thread = Thread.init(),
                .ctxt = objs,
            };
        }
        fn end(pc: [*]const Code, sp: [*]Object, hp: Hp, thread: *Thread, _: ContextPtr) void {
            _ = pc; _ = hp;
            result = thread.stack(sp);
        }
        fn method(self: *Self) ThreadedFn {
            _ = self;
            return end;
        }
        fn context(self: *Self) ContextPtr {
            return @ptrCast(ContextPtr,@alignCast(@alignOf(ContextPtr),&self.ctxt));
        }
        fn o(self: *Self) []Object {
            return self.ctxt[0..];
        }
    };
}
test "init context" {
    const expectEqual = std.testing.expectEqual;
    const objs = comptime [_]Object{True,Object.from(42)};
    var result = TestResult(objs.len,objs).init();
    const c = result.context();
    c.print();
    try expectEqual(result.o()[3].u(),4);
    try expectEqual(result.o()[6],True);
    var thread = result.thread;
    var sp = thread.endOfStack();
    c.convertToProperHeapObject(sp, &thread);
    c.print();
}

pub const CompiledMethodPtr = *CompiledMethod;
pub const CompiledMethod = extern struct {
    header: heap.Header,
    name: Object,
    class: Object,
    stackStructure: Object, // number of local values beyond the parameters
    size: u64,
    code: [1] Code,
    const Self = @This();
    const codeOffset = @offsetOf(CompiledMethod,"code");
    const nIVars = codeOffset/@sizeOf(Object)-2;
    comptime {
        if (checkEqual(codeOffset,@offsetOf(CompileTimeMethod(.{0}),"code"))) |s|
            @compileError("CompileMethod prefix not the same as CompileTimeMethod == " ++ s);
    }
    const pr = std.io.getStdOut().writer().print;
    fn init(name: Object) Self {
        return Self {
            .header = undefined,
            .name = name,
            .class = Nil,
            .stackStructure = Object.from(0),
            .size = 1,
            .code = [1]Code{Code.int(0)},
        };
    }
    fn codeSlice(self: * const CompiledMethod) [] const Code{
        @setRuntimeSafety(false);
        return self.code[0..self.codeSize()];
    }
    fn codePtr(self: * const CompiledMethod) [*] const Code {
        return @ptrCast([*]const Code,&self.code[0]);
    }
    inline fn codeSize(self: * const CompiledMethod) usize {
        return @alignCast(8,&self.header).inHeapSize()-@sizeOf(Self)/@sizeOf(Object)+1;
    }
    fn matchedSelector(pc: [*] const Code) bool {
        _ = pc;
        return true;
    }
    fn methodFromCodeOffset(pc: [*] const Code) CompiledMethodPtr {
        const method = @intToPtr(CompiledMethodPtr,@ptrToInt(pc)-codeOffset-(pc[0].uint)*@sizeOf(Code));
        method.print();
        return method;
    }
    fn print(self: *Self) void {
        pr("CMethod: {} {} {} {} (",.{self.header,self.name,self.class,self.stackStructure}) catch @panic("io");
//            for (self.code[0..]) |c| {
//                pr(" 0x{x:0>16}",.{@bitCast(u64,c)}) catch @panic("io");
//            }
        pr(")\n",.{}) catch @panic("io");
    }
};
pub const Code = packed union {
    prim: ThreadedFn,
    int: i64,
    uint: u64,
    object: Object,
    header: heap.Header,
//    method: CompiledMethodPtr,
    inline fn prim(pp: ThreadedFn) Code {
        return Code{.prim=pp};
    }
    inline fn int(i: i64) Code {
        return Code{.int=i};
    }
    inline fn uint(u: u64) Code {
        return Code{.uint=u};
    }
    inline fn object(o: Object) Code {
        return Code{.object=o};
    }
    inline fn header(h: heap.Header) Code {
        return Code{.header=h};
    }
//   inline fn method(m: CompiledMethodPtr) Code {
//        return Code{.method=m};
//    }
    inline fn end() Code {
        return Code{.object=NotAnObject};
    }
    inline fn codePtr(self: * const Code) [*]const Code {
        return @ptrCast([*]const Code,self);
    }
    inline fn methodPtr(self: * const Code) CompiledMethodPtr {
        return CompiledMethod.methodFromCodeOffset(self.codePtr());
    }
};
fn countNonLabels(comptime tup: anytype) usize {
    var n = 1;
    inline for (tup) |field| {
        switch (@TypeOf(field)) {
            Object => {n+=1;},
            @TypeOf(null) => {n+=1;},
            comptime_int,comptime_float => {n+=1;},
            ThreadedFn => {n+=1;},
            else => 
                switch (@typeInfo(@TypeOf(field))) {
                    .Pointer => {if (field[field.len-1]!=':') n = n + 1;},
                    else => {n = n+1;},
            }
        }
    }
    return n;
}
fn CompileTimeMethod(comptime tup: anytype) type {
    const codeSize = countNonLabels(tup);
    return extern struct { // structure must exactly match CompiledMethod
        header: heap.Header,
        name: Object,
        class: Object,
        stackStructure: Object,
        size: u64,
        code: [codeSize] Code,
        const pr = std.io.getStdOut().writer().print;
        const codeOffsetInUnits = CompiledMethod.codeOffset/@sizeOf(Code);
        const methodIVars = CompiledMethod.nIVars;
        const Self = @This();
        fn init(name: Object, comptime locals: comptime_int) Self {
            return .{
                .header = heap.header(methodIVars,Format.both,class.CompiledMethod_I,name.hash24(),Age.static),
                .name = name,
                .class = Nil,
                .stackStructure = Object.packedInt(locals,locals+name.numArgs(),0),
                .size = codeSize,
                .code = undefined,
            };
        }
        pub fn asCompiledMethodPtr(self: *Self) * CompiledMethod {
            return @ptrCast(* CompiledMethod,self);
        }
        fn headerOffset(_: *Self, codeIndex: usize) Code {
            return Code.uint(codeIndex+codeOffsetInUnits);
        }
        fn getCodeSize(_: *Self) usize {
            return codeSize;
        }
        fn print(self: *Self) void {
            pr("CTMethod: {} {} {} {} (",.{self.header,self.name,self.class,self.stackStructure}) catch @panic("io");
            for (self.code[0..]) |c| {
                pr(" 0x{x:0>16}",.{@bitCast(u64,c)}) catch @panic("io");
            }
            pr(")\n",.{}) catch @panic("io");
        }
    };
}
pub fn compileMethod(name: Object, comptime parameters: comptime_int, comptime locals: comptime_int, comptime tup: anytype) CompileTimeMethod(tup) {
//    var result: [countNonLabels(tup)+CompiledMethod.codeOffset]Code = undefined;
    const methodType = CompileTimeMethod(tup);
    var method = methodType.init(name,locals);
    method.code[0] = Code.prim(controlPrimitives.noop);
    comptime var n = 1;
    _ = parameters;
    inline for (tup) |field| {
        switch (@TypeOf(field)) {
            Object => {method.code[n]=Code.object(field);n=n+1;},
            @TypeOf(null) => {method.code[n]=Code.object(Nil);n=n+1;},
            comptime_int,comptime_float => {method.code[n]=Code.object(Object.from(field));n = n+1;},
            ThreadedFn => {method.code[n]=Code.prim(field);n=n+1;},
            else => {
                comptime var found = false;
                switch (@typeInfo(@TypeOf(field))) {
                    .Pointer => {
                        if (field[field.len-1]==':') {
                            found = true;
                        } else if (field.len==1 and field[0]=='^') {
                            method.code[n]=Code.int(n);
                            n=n+1;
                            found = true;
                        } else if (field.len==1 and field[0]=='*') {
                            method.code[n]=Code.int(-1);
                            n=n+1;
                            found = true;
                        } else {
                            comptime var lp = 0;
                            inline for (tup) |t| {
                                if (@TypeOf(t) == ThreadedFn) lp=lp+1
                                    else
                                    switch (@typeInfo(@TypeOf(t))) {
                                        .Pointer => {
                                            if (t[t.len-1]==':') {
                                                if (comptime std.mem.startsWith(u8,t,field)) {
                                                    method.code[n]=Code.int(lp-n);
                                                    n=n+1;
                                                    found = true;
                                                }
                                            } else lp=lp+1;
                                        },
                                        else => {lp=lp+1;},
                                }
                            }
                            if (!found) @compileError("missing label: \""++field++"\"");
                        }
                    },
                    else => {},
                }
                if (!found) @compileError("don't know how to handle \""++@typeName(@TypeOf(field))++"\"");
            },
        }
    }
//    method.code[n]=Code.end();
    method.print();
    return method;
}
const stdout = std.io.getStdOut().writer();
const print = std.io.getStdOut().writer().print;
test "compiling method" {
    const expectEqual = std.testing.expectEqual;
    var m = compileMethod(Nil,0,0,.{"abc:", testing.return_tos, "def", True, 42, "def:", "abc", "*", "^", null});
    var t = m.code[0..];
    try expectEqual(t.len,9);
    try expectEqual(t[0].prim,controlPrimitives.noop);
    try expectEqual(t[1].prim,testing.return_tos);
    try expectEqual(t[2].int,2);
    try expectEqual(t[3].object,True);
    try expectEqual(t[4].object,Object.from(42));
    try expectEqual(t[5].int,-5);
    try expectEqual(t[6].int,-1);
    try expectEqual(t[7].int,7);
    try expectEqual(CompiledMethod.methodFromCodeOffset((&t[7]).codePtr()),m.asCompiledMethodPtr());
    try expectEqual((&t[7]).methodPtr(),m.asCompiledMethodPtr());
    try expectEqual(t[8].object,Nil);
}
fn execute(pc: [*]const Code, sp: [*]Object, hp: Hp, thread: *Thread, context: ContextPtr) void {
    return @call(tailCall,pc[0].prim,.{pc+1,sp,hp,thread,context});
}
pub const controlPrimitives = struct {
    pub inline fn checkSpace(pc: [*]const Code, sp: [*]Object, hp: Hp, thread: *Thread, context: Context, needed: usize) void {
        _ = thread;
        _ = pc;
        _ = hp;
        _ = context;
        _ = sp;
        _ = needed;
    }
    pub fn noop(pc: [*]const Code, sp: [*]Object, hp: Hp, thread: *Thread, context: ContextPtr) void {
        return @call(tailCall,pc[0].prim,.{pc+1,sp,hp,thread,context});
    }
    pub fn branch(pc: [*]const Code, sp: [*]Object, hp: Hp, thread: *Thread, context: ContextPtr) void {
        const offset = pc[0].int;
        if (offset>=0) {
            const target = pc+1+@intCast(u64, offset);
            if (thread.needsCheck()) return @call(tailCall,Thread.check,.{target,sp,hp,thread,context});
            return @call(tailCall,target[0].prim,.{target+1,sp,hp,thread,context});
        }
        if (offset == -1) {
            const target = context.getTPc();
            if (thread.needsCheck()) return @call(tailCall,Thread.check,.{target,sp,hp,thread,context});
            return @call(tailCall,target[0].prim,.{target+1,sp,hp,thread,context});
        }
        const target = pc+1-@intCast(u64, -offset);
        if (thread.needsCheck()) return @call(tailCall,Thread.check,.{target,sp,hp,thread,context});
        return @call(tailCall,target[0].prim,.{target+1,sp,hp,thread.decCheck(),context});
    }
    pub fn ifTrue(pc: [*]const Code, sp: [*]Object, hp: Hp, thread: *Thread, context: ContextPtr) void {
        const v = sp[0];
        if (True.equals(v)) return @call(tailCall,branch,.{pc,sp+1,hp,thread,context});
        if (thread.needsCheck()) return @call(tailCall,Thread.check,.{pc+2,sp,hp,thread,context});
        if (False.equals(v)) return @call(tailCall,pc[1].prim,.{pc+2,sp+1,hp,thread,context});
        @panic("non boolean");
    }
    pub fn ifFalse(pc: [*]const Code, sp: [*]Object, hp: Hp, thread: *Thread, context: ContextPtr) void {
        const v = sp[0];
        if (False.equals(v)) return @call(tailCall,branch,.{pc,sp+1,hp,thread,context});
        if (True.equals(v)) return @call(tailCall,pc[1].prim,.{pc+2,sp+1,hp,thread,context});
        @panic("non boolean");
    }
    pub fn pushLiteral(pc: [*]const Code, sp: [*]Object, hp: Hp, thread: *Thread, context: ContextPtr) void {
        const newSp = sp-1;
        newSp[0]=pc[0].object;
        return @call(tailCall,pc[1].prim,.{pc+2,newSp,hp,thread,context});
    }
    pub fn pushLiteral0(pc: [*]const Code, sp: [*]Object, hp: Hp, thread: *Thread, context: ContextPtr) void {
        const newSp = sp-1;
        newSp[0]=Object.from(0);
        return @call(tailCall,pc[1].prim,.{pc+1,newSp,hp,thread,context});
    }
    pub fn pushLiteral1(pc: [*]const Code, sp: [*]Object, hp: Hp, thread: *Thread, context: ContextPtr) void {
        const newSp = sp-1;
        newSp[0]=Object.from(1);
        return @call(tailCall,pc[1].prim,.{pc+1,newSp,hp,thread,context});
    }
    pub fn push1Nil(pc: [*]const Code, sp: [*]Object, hp: Hp, thread: *Thread, context: ContextPtr) void {
        const newSp = sp-1;
        newSp[0]=Nil;
        return @call(tailCall,pc[0].prim,.{pc+1,newSp,hp,thread,context});
    }
    pub fn push2Nil(pc: [*]const Code, sp: [*]Object, hp: Hp, thread: *Thread, context: ContextPtr) void {
        const newSp = sp-2;
        newSp[0]=Nil;
        newSp[1]=Nil;
        return @call(tailCall,pc[0].prim,.{pc+1,newSp,hp,thread,context});
    }
    pub fn popIntoTemp(pc: [*]const Code, sp: [*]Object, hp: Hp, thread: *Thread, context: ContextPtr) void {
        context.setTemp(pc[0].uint,sp[0]);
        return @call(tailCall,pc[1].prim,.{pc+2,sp+1,hp,thread,context});
    }
    pub fn pushTemp(pc: [*]const Code, sp: [*]Object, hp: Hp, thread: *Thread, context: ContextPtr) void {
        const newSp = sp-1;
        newSp[0]=context.getTemp(pc[0].uint);
        return @call(tailCall,pc[1].prim,.{pc+2,newSp,hp,thread,context});
    }
    fn lookupMethod(cls: class.ClassIndex,selector: u64) CompiledMethodPtr {
        _ = cls;
        _ = selector;
        @panic("unimplemented");
    }
    pub fn send(pc: [*]const Code, sp: [*]Object, hp: Hp, thread: *Thread, context: ContextPtr) void {
        const selector = pc[0].object;
        const numArgs = selector.numArgs();
        const newPc = lookupMethod(sp[numArgs].get_class(),selector.hash32()).codePtr();
        context.setTPc(pc+1);
        return @call(tailCall,newPc[0].prim,.{newPc+1,sp,hp,thread,context});
    }
    pub fn call(pc: [*]const Code, sp: [*]Object, hp: Hp, thread: *Thread, context: ContextPtr) void {
        context.setReturn(pc+1);
        const newPc = pc[0].method.codePtr();
        return @call(tailCall,newPc[0].prim,.{newPc+1,sp,hp,thread,context});
    }
    pub fn pushContext(pc: [*]const Code, sp: [*]Object, hp: Hp, thread: *Thread, context: ContextPtr) void {
        const method = CompiledMethod.methodFromCodeOffset(pc);
        // can rewrite pc[0] to be direct mathod reference and pc[-1] to be pushContextAlt
        // - so second time will be faster
        // - but need to be careful to do in an idempotent way to guard against another thread executing this in parallel
        const stackStructure = method.stackStructure;
        const locals = stackStructure.h0;
        const maxStackNeeded = stackStructure.h1;
        const result = context.push(sp,hp,thread,method,locals,maxStackNeeded);
        return @call(tailCall,pc[1].prim,.{pc+2,result.ctxt.asObjectPtr(),result.hp,thread,result.ctxt});
    }
    pub fn returnWithContext(pc: [*]const Code, sp: [*]Object, hp: Hp, thread: *Thread, context: ContextPtr) void {
        _ = pc;
        _ = sp;
        _ = hp;
        _ = thread;
        _ = context;
//        const result = sp[0];
//        context.setReturn(pc+1);
//        const newPc = pc[0].method.codePtr();
//        return @call(tailCall,newPc[0].prim,.{newPc+1,sp,hp,thread,context});
        @panic("unimplemented");
    }
    pub fn dnu(pc: [*]const Code, sp: [*]Object, hp: Hp, thread: *Thread, context: ContextPtr) void {
        _ = pc;
        _ = sp;
        _ = hp;
        _ = thread;
        _ = context;
        @panic("unimplemented");
    }
};
const p = struct {
    usingnamespace controlPrimitives;
};
pub const testing = struct {
    pub fn return_tos(pc: [*]const Code, sp: [*]Object, hp: Hp, thread: *Thread, context: ContextPtr) void {
        _ = pc;
        _ = sp;
        _ = hp;
        _ = thread;
        _ = context;
        return;
    }
    pub fn failed_test(pc: [*]const Code, sp: [*]Object, hp: Hp, thread: *Thread, context: ContextPtr) void {
        _ = pc;
        _ = hp;
        _ = thread;
        _ = context;
        _ = sp;
        @panic("failed_test");
    }
    pub fn unexpected_return(pc: [*]const Code, sp: [*]Object, hp: Hp, thread: *Thread, context: ContextPtr) void {
        _ = pc;
        _ = sp;
        _ = hp;
        _ = thread;
        _ = context;
        @panic("unexpected_return");
    }
    pub fn dumpContext(pc: [*]const Code, sp: [*]Object, hp: Hp, thread: *Thread, context: ContextPtr) void {
        print("pc: 0x{x:0>16} sp: 0x{x:0>16} hp: 0x{x:0>16}",.{pc,sp,hp});
        context.print(sp,thread);
        return @call(tailCall,pc[0].prim,.{pc+1,sp,hp,thread,context});
    }
    pub fn testExecute(method: * const CompiledMethod) Object {
        const code = method.codeSlice();
        var context: Context = undefined;
        var thread = Thread.initForTest(null) catch unreachable;
        var sp = thread.endOfStack()-1;
        sp[0]=Nil;
        execute(code.ptr,sp+1,thread.getHeap(),(&thread).maxCheck(),&context);
        return sp[0];
    }
    pub fn debugExecute(method: * const CompiledMethod) Object {
        const code = method.codeSlice();
        var context: Context = undefined;
        var thread = Thread.initForTest(null) catch unreachable;
        var sp = thread.endOfStack()-1;
        sp[0]=Nil;
        execute(code.ptr,sp,thread.getArena().heap,1000,&thread,&context,method.name);
        return sp[0];
    }
};

test "simple return via execute" {
    const expectEqual = std.testing.expectEqual;
    var method = compileMethod(Nil,0,0,.{
        p.noop,
        testing.return_tos,
    });
    try expectEqual(testing.testExecute(method.asCompiledMethodPtr()),Nil);
}
test "simple executable" {
    const method = compileMethod(Nil,0,1,.{
        p.pushContext,"^",
        "label1:",
        p.pushLiteral,42,
        p.popIntoTemp,1,
        p.pushTemp,1,
        p.pushLiteral0,
        p.send,sym.@"<",
        p.ifFalse,"label3",
        "label2",
        "label3:",
        p.pushTemp,1,
        "label4:",
        p.returnWithContext,
        "label2:",
        p.pushLiteral0,
        "label4",
    });
    _ = method;
}
