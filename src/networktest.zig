const std = @import("std");
const net = std.Io.net;

const data = @import("data.zig");

const packet = @import("packet.zig");

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

const asn1 = std.crypto.codecs.asn1;
const Integer = asn1.Opaque(asn1.Tag.universal(.integer, false));

const Modulus = std.crypto.ff.Modulus(4096);

const Sha1 = std.crypto.hash.Sha1;

const aes = std.crypto.core.aes;
const Aes128 = aes.Aes128;

const CryptManager = struct {
    sharedSecret: []u8, // if the context is all we need this could be removed idk yet
    ctx: aes.AesEncryptCtx(Aes128),

    const SubjectPublicKeyInfo = struct {
        algorithm: struct {
            algorithm: asn1.Oid,
            parameters: ?asn1.Any,
        },
        subjectPublicKey: asn1.BitString,
    };

    const SubjectPublicKey = struct {
        modulus: Integer,
        publicExponent: Integer,
    };

    /// rsa PKCS#1 v1.5 encryption
    /// + mojang authentication
    pub fn initEncryption(
        self: *@This(), 
        request: packet.login.clientbound.Encryption_Request, 
        writer: *std.Io.Writer, 
        io: std.Io, 
        allocator: std.mem.Allocator
    ) !void {
        const publicKeyInfo = try asn1.der.decode(SubjectPublicKeyInfo, request.public_key);
        const publicKey = try asn1.der.decode(SubjectPublicKey, publicKeyInfo.subjectPublicKey.bytes);

        var sharedSecret: [16]u8 = undefined;
        try io.randomSecure(&sharedSecret);
        self.sharedSecret = sharedSecret[0..];

        const encryptedSharedSecret = try decryptRSA(io, allocator, sharedSecret[0..], publicKey);
        errdefer allocator.free(encryptedSharedSecret);
        defer allocator.free(encryptedSharedSecret);

        const encryptedVerifyToken = try decryptRSA(io, allocator, request.verify_token, publicKey);
        errdefer allocator.free(encryptedVerifyToken);
        defer allocator.free(encryptedVerifyToken);

        const encryptionResponse: packet.login.serverbound.Encryption_Response = .{
            .shared_secret_length = .{ .value = 128 },
            .shared_secret = encryptedSharedSecret,
            .verify_token_length = .{ .value = 128 },
            .verify_token = encryptedVerifyToken,
        };
        try encryptionResponse.send(writer);

        self.ctx = Aes128.initEnc(sharedSecret);

        try self.authenticate(request, io, allocator);
    }

    /// caller owns returned memory
    fn decryptRSA(io: std.Io, allocator: std.mem.Allocator, message: []const u8, publicKey: SubjectPublicKey) ![]u8 {
        const modulus = try Modulus.fromBytes(publicKey.modulus.bytes, .big);
        const exponent = publicKey.publicExponent.bytes;
        
        // 128 byte encrypted message
        var em = [_]u8{0} ** 128;
        
        // padding: 0x00 | 0x02 | random | 0x00 | message
        var prng: std.Random.IoSource = .{ .io = io };
        const random = prng.interface();
        em[0] = 0x00;
        em[1] = 0x02;
        for(em[2 .. 128 - message.len - 1]) |*b| {
            b.* = 1 + random.uintLessThan(u8, 0xFF);
        }
        em[128 - message.len - 1] = 0x00;
        @memcpy(em[128 - message.len ..], message[0..]);
        
        // convert padded key to integer
        const msgInt = try Modulus.Fe.fromBytes(modulus, em[0..], .big);

        // rsa encryption
        const cipher = try modulus.powWithEncodedPublicExponent(msgInt, exponent, .big);
        const output = try allocator.alloc(u8, 128);
        try cipher.toBytes(output, .big);

        return output;
    }

    pub fn authenticate(
        self: @This(), 
        request: packet.login.clientbound.Encryption_Request, 
        io: std.Io, 
        allocator: std.mem.Allocator
    ) !void {
        _ = .{io, allocator};
        var digest = Sha1.init(.{});
        digest.update(request.server_ID.value);
        digest.update(self.sharedSecret);
        digest.update(request.public_key);
        const whatisthis = hexdigest(&digest);
        std.debug.print("{x}\n", .{whatisthis});

        // TODO entire auth tbh
    }

    pub fn hexdigest(digest: *Sha1) i160 {
        var hash: [20]u8 = undefined;
        digest.final(&hash);
        return std.mem.readInt(i160, hash[0..], .big);
    }

    // TODO both functions are the same, haven't been tested, the encrypted/decrypted string should be in the input buffer

    /// AES-128/CFB8 encryption
    pub fn encryptAES(self: @This(), message: []u8) void {
        var shiftRegister = self.sharedSecret; // shared secret used as IV

        for(message) |*b| {
            var keyStream: [16]u8 = undefined;
            self.ctx.encrypt(&keyStream, &shiftRegister);

            const cipherText = b.* ^ keyStream[0];
            b.* = cipherText;

            @memmove(shiftRegister[0..15], shiftRegister[1..16]);
            shiftRegister[15] = cipherText;
        }
    }

    /// AES-128/CFB8 decryption
    pub fn decryptAES(self: @This(), message: []u8) void {
        var shiftRegister = self.sharedSecret; // shared secret used as IV

        for(message) |*b| {
            var keyStream: [16]u8 = undefined;
            self.ctx.encrypt(&keyStream, &shiftRegister);

            const plainText = b.* ^ keyStream[0];
            b.* = plainText;

            @memmove(shiftRegister[0..15], shiftRegister[1..16]);
            shiftRegister[15] = plainText;
        }
    }
};
