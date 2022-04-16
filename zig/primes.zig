const std = @import("std");
const math = std.math;
const Order = math.Order;
const stdout = std.io.getStdOut().writer();
//const expect = @import("std").testing.expect;
const treap = @import("treap.zig");
const stats = @import("stats.zig");
const utilities = @import("utilities.zig");
const largestPrimeLessThan = utilities.largestPrimeLessThan;

var prime: u32 = 0;
fn priority(pos:u32) u32 {
    return (pos+1)*%prime;
}
fn compareU64(l: u64, r: u64) Order {
    return math.order(l,r);
}
const Treap_u64 = treap.Treap(u64);
const stats_u32 = stats.Stats(u32);

var best = stats_u32.init(0);
pub fn main() void {
    var prng = std.rand.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        std.os.getrandom(std.mem.asBytes(&seed)) catch unreachable;
        break :blk seed;
    });
    const rand = prng.random();
    
    var memory_ = [_]u8{0} ** (32767*16);
    var depths_ = [_]u32{0} ** 32767;
    var b : u5 = 5;
    while (b<16) : (b += 1) {
        best = stats_u32.init(0);
        const k = (@as(u32,1)<<b)-1;
        const memory = memory_[0..k*16];
        const depths = depths_[0..k];
        stdout.print("Searching for optimal primes for treap of size {} optimal height {}\n",.{k,b}) catch unreachable; 
        const primes = [_]u32{0xa1fdc7a3,
                              // 0x9e480773,
                              // 0x95eac4e9,
                              // 0x9e2fda23,
                              // 0x9cfdb27d,
                             
                              // 0x6a14d18f,
                              // 0x61c5a08b,
                              // 2718047303,
                              // 0x61fcc927,
                              // 0x9e3a146b,
                              // 0x9e37a06f,

                              // 1605146423,
                              // 2524803221,
                              // 3383910533,
                              // 2652726113,
                              // 2652447943,
                              // 1999999973,
                              };
        for (primes) |v| {
            tryTreap(false,v,memory,depths);
        }
        var i: usize = 0; //100_000/@intCast(usize,b);
        while (i > 0)
            : (i -= 1) {
                const j = largestPrimeLessThan(rand.int(u32)|0x80000000);
                tryTreap(false,@intCast(u32,j),memory,depths);
        }
        // stdout.print("*",.{}) catch unreachable;
        // const max = 0x100000000;
        // i = max;
        // while (i > max/2)
        //     : (i -= 500*k) {
        //         i = largestPrimeLessThan(i);
        //         tryTreap(@intCast(u32,i),memory,depths);
        // }
    }
}
fn tryTreap(printAnyway: bool,i: u32, memory: []u8, depths: []u32) void {
    prime =i;
    var trp = Treap_u64.init(memory,compareU64,0,priority);
    var index : u64 = 1;
    while (index<depths.len) : (index += 1) {
        _ = trp.insert(index) catch unreachable;
    }
    trp.depths(depths);
    var current = stats_u32.init(i);
    for (depths[1..]) |depth| {
        current.addData(@intToFloat(f64,depth));
    }
    var print = printAnyway;
    if (best.noData() or best.max()>current.max() or (best.max()==current.max() and best.mean()>current.mean())) {
        best = current;
        stdout.print("new best",.{}) catch unreachable;
        print = true;
    } else
        if (print) stdout.print("current",.{}) catch unreachable;
    if (print) stdout.print(" is {} 0x{x:0>8} with max={d:2.0} mean={d:5.2} stdev={d:5.2}\n", .{i,i,current.max(),current.mean(),current.stddev()}) catch unreachable;
}
