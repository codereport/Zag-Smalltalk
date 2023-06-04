const std = @import("std");
const Context = @import("../context.zig").Context;
const execute = @import("../execute.zig");
const trace = execute.trace;
const ContextPtr = execute.CodeContextPtr;
const Code = execute.Code;
const tailCall = execute.tailCall;
const compileMethod = execute.compileMethod;
const CompiledMethod = execute.CompiledMethod;
const CompiledMethodPtr = execute.CompiledMethodPtr;
const Process = @import("../process.zig").Process;
const object = @import("../zobject.zig");
const Object = object.Object;
const Nil = object.Nil;
const True = object.True;
const False = object.False;
const u64_MINVAL = object.u64_MINVAL;
const sym = @import("../symbol.zig").symbols;
const heap = @import("../heap.zig");
const MinSmallInteger: i64 = object.MinSmallInteger;
const MaxSmallInteger: i64 = object.MaxSmallInteger;

pub const inlines = struct {
    pub inline fn p201(self: Object, other: Object) !Object { // value
        _ = self; _ = other;
        return error.primitiveError;
    }
    pub inline fn p202(self: Object, other: Object) !Object { // value:
        _ = self; _ = other;
        return error.primitiveError;
    }
    pub inline fn p203(self: Object, other: Object) !Object { // value:value:
        _ = self; _ = other;
        return error.primitiveError;
    }
    pub inline fn p204(self: Object, other: Object) bool { // value:value:value:
        return self.equals(other);
    }
    pub inline fn p205(self: Object, other: Object) !Object { // value:value:value:value:
        _ = self; _ = other;
        return error.primitiveError;
    }
    pub fn immutableClosure(sp: [*]Object, process: *Process) [*]Object {
        const val = sp[0];
        var newSp = sp;
        if (val.isInt() and val.u()<=Object.from(0x3fff_ffff_ffff).u() and val.u()>=Object.from(-0x4000_0000_0000).u()) {
            sp[0] = Object.makeGroup(.numericThunk,@truncate(u47,val.u()));
        } else if (val.isDouble() and (val.u()&0x1ffff)==0) {
            sp[0] = Object.makeGroup(.numericThunk,@as(u48,1)<<47|@truncate(u48,val.u()>>17));
        } else if (val.isImmediate()) {
            sp[0].tag = .immediateThunk;
        } else if (val.isHeapObject()) {
            sp[0].tag = .heapThunk;
        } else {
            newSp = generalClosure(sp,process,val);
        }
        return newSp;
    }
    pub inline fn generalClosure(oldSp: [*]Object, process: *Process, value: Object) [*]Object {
        const sp = process.allocStack(oldSp,3) catch @panic("can't allocate stack");
        sp[0] = Object.from(&sp[3]);
        sp[0].tag = .heapClosure;
        sp[1] = value;
        sp[2] = Object.from(&valueClosureMethod);
        sp[3] = heap.HeapObject.simpleStackObject(2,object.BlockClosure_I,sym.value.hash24()).o();
        return sp;
    }
    var valueClosureMethod = CompiledMethod.init2(sym.value,
                                                  pushValue,
                                                  e.returnNoContext);
    fn pushValue(pc: [*]const Code, sp: [*]Object, process: *Process, context: ContextPtr, selector: Object) [*]Object {
        if (!sym.value.equals(selector)) return @call(tailCall,e.dnu,.{pc,sp,process,context,selector});
        const closure = sp[0].to(heap.HeapObjectPtr);
        sp[0] = closure.prevPrev();
        return @call(tailCall,pc[0].prim,.{pc+1,sp,process,context,selector});
    }
};

pub const embedded = struct {
    pub const value = p201;
    pub fn p201(pc: [*]const Code, sp: [*]Object, process: *Process, context: ContextPtr, selector: Object) [*]Object { // value
        const val = sp[0];
        switch (val.tag) {
            .numericThunk => {
                if (((val.u()>>47)&1)==0) {
                    sp[0] = Object.from(@bitCast(i64,val.u()<<17)>>17);
                } else {
                    sp[0] = @bitCast(Object,val.u()<<17);
                }},
            .immediateThunk => sp[0].tag = .immediates,
            .heapThunk => sp[0].tag = .heap,
            .nonLocalThunk => unreachable,
            .heapClosure => {
                const closure = val.to(heap.HeapObjectPtr);
                const method = closure.prev().to(CompiledMethodPtr);
                if (method!=&inlines.valueClosureMethod) {
                    const newPc = method.codePtr();
                    context.setReturn(pc);
                    return @call(tailCall,newPc[0].prim,.{newPc+1,sp,process,context,sym.value});
                }
                if (!sym.value.equals(method.selector)) return @call(tailCall,e.dnu,.{pc,sp,process,context,selector});
                sp[0] = closure.prevPrev();
            },
            else => @panic("not closure"),
        }
        return @call(tailCall,pc[0].prim,.{pc+1,sp,process,context,selector});
    }
    pub fn immutableClosure(pc: [*]const Code, sp: [*]Object, process: *Process, context: ContextPtr, selector: Object) [*]Object {
        return @call(tailCall,pc[0].prim,.{pc+1,inlines.immutableClosure(sp,process),process,context,selector});
    }
    pub fn generalClosure(pc: [*]const Code, sp: [*]Object, process: *Process, context: ContextPtr, selector: Object) [*]Object {
        const newSp = inlines.generalClosure(sp+1,process,sp[0]) catch unreachable;
        return @call(tailCall,pc[0].prim,.{pc+1,newSp,process,context,selector});
    }
};
fn testImmutableClosure(process: *Process,value: Object) !object.Group {
    const ee = std.testing.expectEqual;
    var context = Context.init();
    const sp = process.endOfStack()-1;
    sp[0] = value;
    const newSp = embedded.immutableClosure(Code.end.ptr,sp,process,&context,Nil);
    if (newSp != sp) {
        try ee(value.u(),newSp[1].u());
    }
    const tag = newSp[0].tag;
    const newerSp = embedded.value(Code.end.ptr,newSp,process,&context,Nil);
    try ee(value.u(),newerSp[0].u());
    return tag;
}
test "immutableClosures" {
    const ee = std.testing.expectEqual;
    var process = Process.new();
    process.init();
    try ee(try testImmutableClosure(&process,Object.from(1)),.numericThunk);
    try ee(try testImmutableClosure(&process,Object.from(-1)),.numericThunk);
    try ee(try testImmutableClosure(&process,Object.from(0x3fff_ffff_ffff)),.numericThunk);
    try ee(try testImmutableClosure(&process,Object.from(-0x4000_0000_0000)),.numericThunk);
    try ee(try testImmutableClosure(&process,Object.from(1000.75)),.numericThunk);
    try ee(try testImmutableClosure(&process,Object.from(-1000.75)),.numericThunk);
    try ee(try testImmutableClosure(&process,Nil),.immediateThunk);
    try ee(try testImmutableClosure(&process,Object.from(&process)),.heapThunk);
    try ee(try testImmutableClosure(&process,Object.from(0x4000_0000_0000)),.heapClosure);
    try ee(try testImmutableClosure(&process,Object.from(-0x4000_0000_0001)),.heapClosure);
    try ee(try testImmutableClosure(&process,Object.from(1000.3)),.heapClosure);
}
pub const primitives = struct {
    pub fn p201(pc: [*]const Code, sp: [*]Object, process: *Process, context: ContextPtr, selector: Object) [*]Object { // value
        if (!sym.value.equals(selector)) return @call(tailCall,execute.dnu,.{pc,sp,process,context,selector});
        unreachable;
    }
    pub fn p202(pc: [*]const Code, sp: [*]Object, process: *Process, context: ContextPtr, selector: Object) [*]Object { // value:
        _ = pc; _ = sp; _ = process; _ = context; _ = selector; unreachable;
    }
    pub fn p203(pc: [*]const Code, sp: [*]Object, process: *Process, context: ContextPtr, selector: Object) [*]Object { // value:value:
        _ = pc; _ = sp; _ = process; _ = context; _ = selector; unreachable;
    }
    pub fn p204(pc: [*]const Code, sp: [*]Object, process: *Process, context: ContextPtr, selector: Object) [*]Object { // value:value:value:
        _ = pc; _ = sp; _ = process; _ = context; _ = selector; unreachable;
    }
    pub fn p205(pc: [*]const Code, sp: [*]Object, process: *Process, context: ContextPtr, selector: Object) [*]Object { // value:value:value:value:
        _ = pc; _ = sp; _ = process; _ = context; _ = selector; unreachable;
    }
};
const e = struct {
    usingnamespace @import("../execute.zig").controlPrimitives;
    usingnamespace embedded;
};