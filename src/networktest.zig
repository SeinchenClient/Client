const std = @import("std");
const net = std.net;

const data = @import("data.zig");

const packet = @import("packet.zig");

pub fn main() !void {
    const addr = try net.Address.resolveIp("127.0.0.1", 25565);

    var stream = try net.tcpConnectToAddress(addr);
    defer stream.close();

    var readbuf: [1024]u8 = undefined;
    var r = stream.reader(&readbuf);
    const reader = r.interface();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var writebuf: [1024]u8 = undefined;
    var w = stream.writer(&writebuf);
    const writer = &w.interface;

    // try data.VarInt.writeInt(15, writer);
    // const handshake: packet.ID = .{ .handshake = .{ .serverbound = .Handshake } };
    // try data.VarInt.writeInt(@intFromEnum(handshake.handshake.serverbound), writer);

    const pack: packet.handshake.serverbound.Handshake = .{
        .protocol_version = .{ .value = 47 },
        .server_address = .{ .value = "127.0.0.1", .allocator = allocator },
        .server_port = 25565,
        .next_state = .{ .value = 2 },
    };
    
    try pack.send(writer);

    // try data.VarInt.writeInt(47, writer);
    // try data.String.writeString("127.0.0.1", writer);
    // try writer.writeInt(u16, 25565, .big);
    // try data.VarInt.writeInt(2, writer);

    // try writer.flush();

    try data.VarInt.writeInt(10, writer);
    const loginstart: packet.ID = .{ .login = .{ .serverbound = .Login_Start } };
    try data.VarInt.writeInt(@intFromEnum(loginstart.login.serverbound), writer);

    try data.String.writeString("Seinchen", writer);

    try writer.flush();

    while(true) {
        const len = (try data.VarInt.init(reader)).value;
        const packetID = (try data.VarInt.init(reader)).value;
        const payload: []u8 = try reader.take(@intCast(len));
    
        std.debug.print("[{}] {}: {s}\n", .{len, packetID, payload});
    }
}

pub fn writePacket(kind: type, payload: anytype, writer: *std.Io.Writer) !void {
    const fields = @typeInfo(kind);
    inline for(fields.@"struct".fields) |field| {
        switch(@typeInfo(field.type)) {
            .bool => try writer.writeByte(if(@field(payload, field.name) == true) 1 else 0),
            .int => try writer.writeInt(field.type, @field(payload, field.name), .big),
            .float => |f| try writer.writeInt(
                @Type(.{ .int = .{ .bits = f.bits, .signedness = .unsigned } }), 
                @as(
                    @Type(.{ .int = .{ .bits = f.bits, .signedness = .unsigned } }), 
                    @field(payload, f.name)
                ), 
                .big
            ),
            .@"struct" => try @field(payload, field.name).write(writer),
            else => std.debug.print("invalid type!\n", .{}),
        }
    }
}
