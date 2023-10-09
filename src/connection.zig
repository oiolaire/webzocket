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

const Opcode = enum(u4) {
    continuation = 0x0,
    text = 0x1,
    binary = 0x2,
    close = 0x8,
    ping = 0x9,
    pong = 0xa,
    _,
};

const Header = struct {
    op: Opcode,
    payload_len: usize,
    has_mask: bool,
    mask: [4]u8,
};

const ReadError = error{
    UnimplementedCondition,
    InvalidFrame,
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

    pub fn receive(self: *Conn) ![]const u8 {
        receiveFrame: while (true) {
            const header = try self.receiveHeader();

            switch (header.op) {
                .continuation => {
                    std.debug.print("we don't know what to do when we see a continuation op\n", .{});
                    return ReadError.UnimplementedCondition;
                },
                .close => {
                    return ReadError.Closed;
                },
                .ping => {
                    try self.sendRaw(.pong, &.{});
                    continue :receiveFrame;
                },
                .pong => {
                    std.debug.print("we got a pong\n", .{});
                    continue :receiveFrame;
                },
                .binary, .text => {
                    var payload = try self.arena.allocator().alloc(u8, header.payload_len);
                    var n: usize = 0;
                    while (n < header.payload_len) {
                        const more = try self.conn.read(payload[n..]);
                        if (more < 1) {
                            std.debug.print("can't read payload? {d}\n", .{more});
                            return &.{};
                        }
                        n = n + more;
                    }

                    if (header.has_mask) {
                        // TODO: unmask
                    }

                    return payload;
                },
                else => unreachable,
            }
        }
    }

    pub fn send(self: *Conn, payload: []const u8) !void {
        return self.sendRaw(.text, payload);
    }

    pub fn ping(self: *Conn) !void {
        return self.sendRaw(.ping, &.{});
    }

    fn receiveHeader(self: *Conn) !Header {
        var tmp: []u8 = self.read_buffer[0..2];
        const r = try self.conn.read(tmp);
        if (r < 2) {
            std.debug.print("nothing to read? {d}\n", .{r});
            return ReadError.InvalidFrame;
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

        var payload_len: usize = @intCast(tmp[1] & payload_len_bits);
        if (payload_len == 126) {
            tmp = self.read_buffer[0..2];
            const n = try self.conn.read(tmp);
            if (n < 2) {
                std.debug.print("can't read mid-sized payload length? {d}\n", .{n});
                return ReadError.InvalidFrame;
            }
            payload_len = @intCast(std.mem.readIntBig(u16, @as(*[2]u8, @ptrCast(tmp.ptr))));
        } else if (payload_len == 127) {
            tmp = self.read_buffer[0..8];
            const n = try self.conn.read(tmp);
            if (n < 8) {
                std.debug.print("can't read big-sized payload length? {d}\n", .{n});
                return ReadError.InvalidFrame;
            }
            payload_len = @intCast(std.mem.readIntBig(u64, @as(*[8]u8, @ptrCast(tmp.ptr))));
        }

        var mask: [4]u8 = undefined;
        if (has_mask) {
            const n = try self.conn.read(&mask);
            if (n < 1) {
                std.debug.print("can't read mask? {d}\n", .{n});
                return ReadError.InvalidFrame;
            }
        }

        return Header{
            .op = @enumFromInt(op),
            .payload_len = payload_len,
            .has_mask = has_mask,
            .mask = mask,
        };
    }

    fn sendRaw(self: *Conn, op: Opcode, payload: []const u8) !void {
        var allocator = self.arena.allocator();

        const max_size = max_frame_header_size + payload.len;
        if (self.write_buffer.len < max_size) {
            self.write_buffer = try allocator.realloc(self.write_buffer, max_size);
        }
        var msg = self.write_buffer;

        msg[0] = 0;
        msg[0] |= fin_bit; // always set the fin bit because we don't support sending more than one
        msg[0] |= @intFromEnum(op);

        msg[1] = 0;
        msg[1] |= mask_bit; // always set the mask bit because yes

        const payload_len = payload.len;
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
        std.mem.copy(u8, msg[next + 4 ..], payload);

        try self.conn.writeAll(msg[0..actual_size]);
    }
};
