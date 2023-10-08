const std = @import("std");
const random = @import("random.zig");
const connection = @import("connection.zig");

const websocketMagicKeyHasherParameter = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";

pub const Error = error{
    InvalidUpgrade,
    ConnectionClosed,
};

pub fn init(allocator: std.mem.Allocator) Client {
    return Client{
        .client = std.http.Client{
            .allocator = allocator,
        },
    };
}

pub const Client = struct {
    client: std.http.Client,

    pub fn deinit(self: *Client) void {
        self.client.deinit();
    }

    pub fn connect(self: *Client, ws_url: []const u8) !connection.Conn {
        var arena = std.heap.ArenaAllocator.init(self.client.allocator);
        var allocator = arena.allocator();

        // we got an wss:// url but we will actually call the https:// url
        var uri = try std.Uri.parse(ws_url);
        if (std.mem.eql(u8, uri.scheme, "ws")) {
            uri.scheme = "http";
        } else if (std.mem.eql(u8, uri.scheme, "wss")) {
            uri.scheme = "https";
        }

        // headers
        var headers = std.http.Headers{ .allocator = allocator, .owned = true };
        defer headers.deinit();
        const key = try random.getString(allocator, 16);
        defer allocator.free(key);
        try headers.append("Upgrade", "websocket");
        try headers.append("Connection", "Upgrade");
        try headers.append("Sec-WebSocket-Key", key);
        try headers.append("Sec-WebSocket-Version", "13");

        var req = try self.client.request(.GET, uri, headers, .{});
        defer req.deinit();

        try req.start();
        try req.wait();

        // check if we got status code 101
        if (req.response.status != .switching_protocols) {
            return Error.InvalidUpgrade;
        }

        // check header in response
        const accept = req.response.headers.getFirstEntry("Sec-Websocket-Accept");
        if (accept) |field| {
            var sha1 = std.crypto.hash.Sha1.init(.{});
            sha1.update(key);
            sha1.update(websocketMagicKeyHasherParameter);
            var hash: [std.crypto.hash.Sha1.digest_length]u8 = undefined;
            sha1.final(&hash);
            const b64_size = std.base64.standard.Encoder.calcSize(hash.len);
            var expected = try allocator.alloc(u8, b64_size);
            defer allocator.free(expected);
            _ = std.base64.standard.Encoder.encode(expected, &hash);
            if (!std.mem.eql(u8, expected, field.value)) {
                return Error.InvalidUpgrade;
            }
        } else {
            return Error.InvalidUpgrade;
        }

        if (req.connection) |conn| {
            return connection.Conn{
                .client = self,
                .conn = &conn.data,
                .req = &req,
                .arena = arena,
            };
        }

        return Error.ConnectionClosed;
    }
};
