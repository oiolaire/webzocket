const std = @import("std");

pub fn getString(allocator: std.mem.Allocator, size: usize) ![]const u8 {
    const time: u64 = @intCast(std.time.timestamp());

    var random_value = try allocator.alloc(u8, size);
    defer allocator.free(random_value);
    for (0..size) |i| {
        random_value[i] = @truncate(time / (i + 1));
    }

    const b64_size = std.base64.standard.Encoder.calcSize(random_value.len);
    var random_value_b64 = try allocator.alloc(u8, b64_size);
    _ = std.base64.standard.Encoder.encode(random_value_b64, random_value);
    return random_value_b64;
}