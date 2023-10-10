const std = @import("std");
const wz = @import("mod.zig");

test "test connection" {
    const allocator = std.testing.allocator;

    try std.testing.expect(true);
    var client = wz.client.init(allocator);
    defer client.deinit();

    var conn = try client.connect("wss://ws.ifelse.io");
    defer conn.deinit();

    var thread1 = try std.Thread.spawn(.{ .allocator = allocator }, read, .{&conn});
    var thread2 = try std.Thread.spawn(.{ .allocator = allocator }, write, .{&conn});

    std.time.sleep(5000000000);

    thread1.join();
    thread2.join();
}

fn write(conn: *wz.Conn) !void {
    try conn.send("banana");
    try conn.send("uva");
    try conn.send("Xorshift random number generators, also called shift-register generators, are a class of pseudorandom number generators that were invented by George Marsaglia.[1] They are a subset of linear-feedback shift registers (LFSRs) which allow a particularly efficient implementation in software without the excessive use of sparse polynomials.[2] They generate the next number in their sequence by repeatedly taking the exclusive or of a number with a bit-shifted version of itself. This makes execution extremely efficient on modern computer architectures, but it does not benefit efficiency in a hardware implementation. Like all LFSRs, the parameters have to be chosen very carefully in order to achieve a long period.[3]For execution in software, xorshift generators are among the fastest PRNGs, requiring very small code and state. However, they do not pass every statistical test without further refinement. This weakness is amended by combining them with a non-linear function, as described in the original paper. Because plain xorshift generators (without a non-linear step) fail some statistical tests, they have been accused of being unreliable.[3]: 360 Example implementation[edit]A C version[a] of three xorshift algorithms[1]: 4,5  is given here. The first has one 32-bit word of state, and period 232−1. The second has one 64-bit word of state and period 264−1. The last one has four 32-bit words of state, and period 2128−1. The 128-bit algorithm passes the diehard tests. However, it fails the MatrixRank and LinearComp tests of the BigCrush test suite from the TestU01 framework.All use three shifts and three or four exclusive-or operations:#include <stdint.h>struct xorshift32_state     uint32_t a;;/* The state must be initialized to non-zero */uint32_t xorshift32(struct xorshift32_state *state) /* Algorithm 'xor' from p. 4 of Marsaglia, 'Xorshift RNGs' */ uint32_t x = state->a; x ^= x << 13; x ^= x >> 17; x ^= x << 5; return state->a = x;struct xorshift64_state     uint64_t a;;uint64_t xorshift64(struct xorshift64_state *state) uint64_t x = state->a; x ^= x << 13; x ^= x >> 7; x ^= x << 17; return state->a = x;/* struct xorshift128_state can alternatively be defined as a pair   of uint64_t or a uint128_t where supported */struct xorshift128_state     uint32_t x[4];;/* The state must be initialized to non-zero */uint32_t xorshift128(struct xorshift128_state *state) /* Algorithm 'xor128' from p. 5 of Marsaglia, 'Xorshift RNGs' */ uint32_t t  = state->x[3];        uint32_t s  = state->x[0];  /* Perform a contrived 32-bit shift. */ state->x[3] = state->x[2]; state->x[2] = state->x[1]; state->x[1] = s; t ^= t << 11; t ^= t >> 8; return state->x[0] = t ^ s ^ (s >> 19);Non-linear variations[edit]All xorshift generators fail some tests in the BigCrush test suite. This is true for all generators based on linear recurrences, such as the Mersenne Twister or WELL. However, it is easy to scramble the output of such generators to improve their quality.The scramblers known as  and * still leave weakness in the low bits,[4] so they are intended for floating point use, as double-precision floating-point numbers only use 53 bits, so the lower 11 bits are not used. For general purpose, the scrambler ** (pronounced starstar) makes the LFSR generators pass in all bits.)");
    try conn.ping();
}

fn read(conn: *wz.Conn) !void {
    var text: []const u8 = &.{};

    for (0..5) |i| {
        _ = i;
        text = try conn.receive();
        std.debug.print("received text={s}\n", .{text});
        if (std.mem.eql(u8, text, "uva")) {
            try conn.send("thanks");
        }
    }
}
