const std = @import("std");
const client = @import("client.zig");

const mask_bit = 1 << 7; // frame header byte 1 bits from section 5.2 of RFC 6455
const max_frame_header_size = 2 + 8 + 4; // fixed header + length + mask
// frame header byte 0 bits from section 5.2 of RFC 6455
const fin_bit = 1 << 7;
const rsv1_bit = 1 << 6;
const rsv2_bit = 1 << 5;
const rsv3_bit = 1 << 4;
// opcodes
const op_continuation = 0x0;
const op_text = 0x1;
const op_binary = 0x2;
const op_close = 0x8;
const op_ping = 0x9;
const op_pong = 0xA;

pub const Error = error{
    MessageTooBig,
};

pub const Conn = struct {
    client: *client.Client,
    conn: *std.http.Client.Connection,
    req: *std.http.Client.Request,
    arena: std.heap.ArenaAllocator,
    buffer: []u8,

    pub fn deinit(conn: *Conn) void {
        conn.req.deinit();
        conn.conn.deinit(&conn.client.client);
        conn.arena.deinit();
    }

    pub fn read(self: *Conn) !void {
        _ = self;
    }

    pub fn sendText(self: *Conn, text: []const u8) !void {
        var allocator = self.arena.allocator();

        const max_size = max_frame_header_size + text.len;
        if (self.buffer.len < max_size) {
            self.buffer = try allocator.realloc(self.buffer, max_size);
        }
        var msg = self.buffer;

        msg[0] = 0;
        msg[0] |= fin_bit; // always set the fin bit because we don't support sending more than one
        msg[0] |= op_text;

        msg[1] = 0;
        msg[1] |= mask_bit; // always set the mask bit because yes

        const payload_len = text.len;
        var next: usize = undefined;
        var actual_size: usize = undefined;
        if (payload_len <= 125) {
            const sm_length: u8 = @truncate(payload_len);
            msg[1] |= sm_length;
            next = 2;
            actual_size = max_size - 8;
        } else if (payload_len < 65536) {
            msg[1] |= 126;
            const mid_length: u16 = @truncate(payload_len);
            std.mem.writeIntBig(u16, msg[2..4], mid_length);
            next = 4;
            actual_size = max_size - 6;
        } else if (payload_len < 18446744073709551616) {
            msg[1] |= 127;
            const big_length: u64 = @intCast(payload_len);
            std.mem.writeIntBig(u64, msg[2..10], big_length);
            next = 10;
            actual_size = max_size;
        } else {
            return Error.MessageTooBig;
        }

        // set mask to zero because we don't care
        std.mem.copy(u8, msg[next .. next + 4], &[_]u8{ 0, 0, 0, 0 });

        // now write the actual data -- the mask is zero so it has no effect
        std.mem.copy(u8, msg[next + 4 ..], text);

        try self.conn.writeAll(msg[0..actual_size]);
    }
};
