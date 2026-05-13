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

    var cryptManager: CryptManager = undefined;

    var length = (try data.VarInt.init(reader)).value;
    const packID = (try data.VarInt.init(reader)).value;
    if(packID == 0x01) {
        length -= 1;
        const encryptionRequest = try packet.login.clientbound.Encryption_Request.receive(reader, @bitCast(length), init.gpa);

        try cryptManager.initEncryption(encryptionRequest, writer, init.io, init.gpa);
    }

    var compression_buf: [4]u8 = undefined;
    _ = try reader.readSliceShort(compression_buf[0..]);
    cryptManager.decryptAES(compression_buf[0..]);
    var compReader = std.Io.Reader.fixed(compression_buf[2..]);
    const pack3 = try packet.login.clientbound.Set_Compression.receive(&compReader, 2, init.gpa);
    std.debug.print("{}\n\n", .{pack3.threshold.value});

    while(true) {
        const raw_len = try data.VarInt.initDecrypting(reader, &cryptManager);
        const data_len = try data.VarInt.initDecrypting(reader, &cryptManager);
        const msg = try reader.readAlloc(init.gpa, @intCast(@as(u32, @intCast(raw_len.value)) - data_len.countBytes()));
        defer init.gpa.free(msg);
        
        cryptManager.decryptAES(msg);
        var rd = std.Io.Reader.fixed(msg);

        if(data_len.value != 0) continue;
        const packetID = (try data.VarInt.init(&rd)).value;
        const payload: []u8 = rd.buffered();
        
        std.debug.print("[{}] {}: {s}\n", .{raw_len.value, packetID, payload});
    }
}
