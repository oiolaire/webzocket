const std = @import("std");
const wz = @import("mod.zig");

test "test connection" {
    const allocator = std.testing.allocator;

    try std.testing.expect(true);
    var client = wz.client.init(allocator);
    defer client.deinit();

    var conn = try client.connect("ws://127.0.0.1:8080/echo");
    defer conn.deinit();

    try conn.send("hlelo");

    var text1 = try conn.receive();
    std.debug.print("first text={s}\n", .{text1});
    var text2 = try conn.receive();
    std.debug.print("second text={s}\n", .{text2});
}
