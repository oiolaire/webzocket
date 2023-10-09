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
    try conn.send("maçã");
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
