const std = @import("std");
const wz = @import("mod.zig");

test "test connection" {
    const allocator = std.testing.allocator;

    try std.testing.expect(true);
    var client = wz.client.init(allocator);
    defer client.deinit();

    var conn = try client.connect("ws://127.0.0.1:8080/echo");
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
}

fn read(conn: *wz.Conn) !void {
    std.debug.print("starting thread\n", .{});
    while (true) {
        std.debug.print("will read\n", .{});
        var text = try conn.receive();
        std.debug.print("received text={s}\n", .{text});
        if (std.mem.eql(u8, text, "uva")) {
            try conn.send("thanks");
        }
    }
}
