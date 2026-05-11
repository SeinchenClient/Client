const std = @import("std");
const net = std.Io.net;

const data = @import("data.zig");

const packet = @import("packet.zig");

const CryptManager = @import("CryptManager.zig");

pub fn main(init: std.process.Init) !void {
    const addr = try net.IpAddress.resolve(init.io, "127.0.0.1", 25565);

    var stream = try addr.connect(init.io, .{ .protocol = .tcp, .mode = .stream });
    defer stream.close(init.io);

    var readbuf: [1024]u8 = undefined;
    var r = stream.reader(init.io, &readbuf);
    const reader = &r.interface;

    var writebuf: [1024]u8 = undefined;
    var w = stream.writer(init.io, &writebuf);
    const writer = &w.interface;

    const pack: packet.handshake.serverbound.Handshake = .{
        .protocol_version = .{ .value = 47 },
        .server_address = .{ .value = "127.0.0.1", .allocator = init.gpa },
        .server_port = 25565,
        .next_state = .{ .value = @intFromEnum(packet.State.login) },
    };
    try pack.send(writer);

    const pack2: packet.login.serverbound.Login_Start = .{
        .name = data.String.from("Seinchen"),
    };
    try pack2.send(writer);

    var length = (try data.VarInt.init(reader)).value;
    const packID = (try data.VarInt.init(reader)).value;
    if(packID == 0x01) {
        length -= 1;
        const encryptionRequest = try packet.login.clientbound.Encryption_Request.receive(reader, @bitCast(length), init.gpa);

        var cryptManager: CryptManager = undefined;
        try cryptManager.initEncryption(encryptionRequest, writer, init.io, init.gpa);

    }

    while(true) {
        const len = (try data.VarInt.init(reader)).value;
        const packetID = (try data.VarInt.init(reader)).value;
        const payload: []u8 = try reader.take(@intCast(len - @as(i32, @intCast(data.VarInt.countBytesInt(packetID)))));

        std.debug.print("[{}] {}: {s}\n", .{len, packetID, payload});
    }
}
