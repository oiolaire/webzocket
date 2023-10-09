const std = @import("std");
const client = @import("client.zig");

const max_frame_header_size = 2 + 8 + 4; // fixed header + length + mask
const mask_bit = 1 << 7; // frame header byte 1 bits from section 5.2 of RFC 6455
const payload_len_bits = 0x7f;
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
const op_pong = 0xa;

const ReadError = error{
    UnimplementedCondition,
    Closed,
};

pub const Conn = struct {
    client: *client.Client,
    conn: *std.http.Client.Connection,
    req: *std.http.Client.Request,
    arena: std.heap.ArenaAllocator,
    read_buffer: [8]u8,
    write_buffer: []u8,

    pub fn deinit(conn: *Conn) void {
        conn.req.deinit();
        conn.conn.deinit(&conn.client.client);
        conn.arena.deinit();
    }

    pub fn readText(self: *Conn) ![]const u8 {
        var tmp: []u8 = self.read_buffer[0..2];
        const r = try self.conn.read(tmp);
        if (r < 2) {
            std.debug.print("nothing to read? {d}\n", .{r});
            return &.{};
        }

        var fin: bool = (tmp[0] & fin_bit) != 0;
        if (!fin) {
            std.debug.print("we don't know what to do when fin is not true\n", .{});
            return ReadError.UnimplementedCondition;
        }
        if ((tmp[0] & rsv1_bit) != 0 or (tmp[0] & rsv2_bit) != 0 or (tmp[0] & rsv3_bit) != 0) {
            std.debug.print("we don't know what to do when any rsv bit is set\n", .{});
            return ReadError.UnimplementedCondition;
        }
        const op: u8 = tmp[0] & 0x0f;
        const has_mask: bool = (tmp[1] & mask_bit) != 0;

        std.debug.print("x {b}\n", .{tmp[1]});
        var payload_len: usize = @intCast(tmp[1] & payload_len_bits);
        std.debug.print("y: {}\n", .{payload_len});
        if (payload_len == 126) {
            std.debug.print("a\n", .{});
            tmp = self.read_buffer[0..2];
            std.debug.print("b\n", .{});
            const mpln = try self.conn.read(tmp);
            std.debug.print("c\n", .{});
            if (mpln < 2) {
                std.debug.print("can't read mid-sized payload length? {d}\n", .{r});
                return &.{};
            }
            std.debug.print("d\n", .{});
            payload_len = @intCast(std.mem.readIntLittle(u16, @as(*[2]u8, @ptrCast(tmp.ptr))));
            std.debug.print("e\n", .{});
        } else if (payload_len == 127) {
            tmp = self.read_buffer[0..8];
            const mpln = try self.conn.read(tmp);
            if (mpln < 8) {
                std.debug.print("can't read big-sized payload length? {d}\n", .{r});
                return &.{};
            }
            payload_len = @intCast(std.mem.readIntBig(u64, @as(*[8]u8, @ptrCast(tmp.ptr))));
        }

        var mask: [4]u8 = undefined;
        if (has_mask) {
            const n = try self.conn.read(&mask);
            if (n < 1) {
                std.debug.print("can't read mask? {d}\n", .{r});
                return &.{};
            }
        }

        switch (op) {
            op_continuation => {
                std.debug.print("we don't know what to do when we see a continuation op\n", .{});
                return ReadError.UnimplementedCondition;
            },
            op_close => {
                return ReadError.Closed;
            },
            op_ping => {
                std.debug.print("we don't know what to do when we see a ping op\n", .{});
                return ReadError.UnimplementedCondition;
            },
            op_pong => {
                std.debug.print("we got a pong\n", .{});
                return &.{};
            },
            op_binary => {
                std.debug.print("we don't know what to do when we see a binary op\n", .{});
                return ReadError.UnimplementedCondition;
            },
            op_text => {
                var payload = try self.arena.allocator().alloc(u8, payload_len);
                const n = try self.conn.read(payload);
                if (n < 1) {
                    std.debug.print("can't read payload? {d}\n", .{r});
                    return &.{};
                }

                std.debug.print("read payload: {}, mask is {}\n", .{ std.fmt.fmtSliceHexLower(payload), std.fmt.fmtSliceHexLower(&mask) });

                if (has_mask) {
                    // TODO: unmask
                }

                return payload;
            },
            else => unreachable,
        }
    }

    pub fn sendText(self: *Conn, text: []const u8) !void {
        var allocator = self.arena.allocator();

        const max_size = max_frame_header_size + text.len;
        if (self.write_buffer.len < max_size) {
            self.write_buffer = try allocator.realloc(self.write_buffer, max_size);
        }
        var msg = self.write_buffer;

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
        } else {
            msg[1] |= 127;
            const big_length: u64 = @intCast(payload_len);
            std.mem.writeIntBig(u64, msg[2..10], big_length);
            next = 10;
            actual_size = max_size;
        }

        // set mask to zero because we don't care
        std.mem.copy(u8, msg[next .. next + 4], &[_]u8{ 0, 0, 0, 0 });

        // now write the actual data -- the mask is zero so it has no effect
        std.mem.copy(u8, msg[next + 4 ..], text);

        try self.conn.writeAll(msg[0..actual_size]);
    }
};
