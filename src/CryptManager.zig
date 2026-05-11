const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const Client = std.http.Client;

const asn1 = std.crypto.codecs.asn1;
const Integer = asn1.Opaque(asn1.Tag.universal(.integer, false));

const Modulus = std.crypto.ff.Modulus(4096);

const Sha1 = std.crypto.hash.Sha1;

const aes = std.crypto.core.aes;
const Aes128 = aes.Aes128;

const Auth = @import("secrets.zig");

const packet = @import("packet.zig");


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
    writer: *Io.Writer, 
    io: Io, 
    allocator: std.mem.Allocator
) !void {
    const publicKeyInfo = try asn1.der.decode(SubjectPublicKeyInfo, request.public_key);
    const publicKey = try asn1.der.decode(SubjectPublicKey, publicKeyInfo.subjectPublicKey.bytes);

    var sharedSecret: [16]u8 = undefined;
    try io.randomSecure(&sharedSecret);
    self.sharedSecret = sharedSecret[0..];

    const encryptedSharedSecret = try decryptRSA(io, allocator, sharedSecret[0..], publicKey);
    defer allocator.free(encryptedSharedSecret);

    const encryptedVerifyToken = try decryptRSA(io, allocator, request.verify_token, publicKey);
    defer allocator.free(encryptedVerifyToken);

    try self.authenticate(request, io, allocator);

    const encryptionResponse: packet.login.serverbound.Encryption_Response = .{
        .shared_secret_length = .{ .value = 128 },
        .shared_secret = encryptedSharedSecret,
        .verify_token_length = .{ .value = 128 },
        .verify_token = encryptedVerifyToken,
    };
    try encryptionResponse.send(writer);

    self.ctx = Aes128.initEnc(sharedSecret);
}

/// caller owns returned memory
fn decryptRSA(io: Io, allocator: std.mem.Allocator, message: []const u8, publicKey: SubjectPublicKey) ![]u8 {
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
    io: Io, 
    allocator: std.mem.Allocator
) !void {
    _ = .{io, allocator};
    var digest = Sha1.init(.{});
    digest.update(request.server_ID.value);
    digest.update(self.sharedSecret);
    digest.update(request.public_key);
    var serverIdBuf: [41]u8 = undefined;
    const serverId = toString(hexdigest(&digest), serverIdBuf[0..]);

    var client: std.http.Client = .{ .allocator = allocator, .io = io };
    defer client.deinit();

    const authCode = try acquireAuthorizationCode(allocator, io);
    defer allocator.free(authCode);
    const authToken = try acquireAuthorizationToken(allocator, &client, authCode);
    defer authToken.deinit();
    const xblToken = try acquireXblToken(allocator, &client, authToken.value.access_token);
    defer xblToken.deinit();
    const xstsToken = try acquireXstsToken(allocator, &client, xblToken.value.Token);
    defer xstsToken.deinit();
    const mcToken = try acquireMinecraftToken(allocator, &client, xstsToken.value.DisplayClaims.xui[0].uhs, xstsToken.value.Token);
    defer mcToken.deinit();
    const userData = try acquireUserInfo(allocator, &client, mcToken.value.access_token);
    defer userData.deinit();

    try verifyServer(&client, mcToken.value.access_token, userData.value.id, serverId);
}

/// caller owns returned memory
fn acquireAuthorizationCode(allocator: Allocator, io: Io) ![]const u8 {
    const authCodeUrl = 
        \\https://login.microsoftonline.com/consumers/oauth2/v2.0/authorize
        \\?client_id=
        ++ Auth.client_id ++ "\n" ++
        \\&response_type=code
        \\&redirect_uri=http://localhost:28003
        \\&scope=XboxLive.signin
    ;

    // open link in browser
    const argv: []const []const u8 = switch (@import("builtin").os.tag) {
        .windows => &[_][]const u8{ "cmd", "/c", "start", authCodeUrl[0..]},
        .macos   => &[_][]const u8{ "open", authCodeUrl[0..]},
        else     => &[_][]const u8{ "xdg-open", authCodeUrl[0..]},
    };
    const runResult = try std.process.run(allocator, io, .{ .argv = argv });
    defer allocator.free(runResult.stdout);
    defer allocator.free(runResult.stderr);
 
    const addr = try Io.net.IpAddress.parse("127.0.0.1", 28003);
    var server = try addr.listen(io, .{ .reuse_address = true });
    defer server.deinit(io);
 
    const stream = try server.accept(io);
    defer stream.close(io);
 
    var recv_buf: [2048]u8 = undefined;
    var send_buf: [128]u8 = undefined;
    var sr = stream.reader(io, recv_buf[0..]);
    var sw = stream.writer(io, send_buf[0..]);
    var httpserver = std.http.Server.init(&sr.interface, &sw.interface);
 
    var request = try httpserver.receiveHead();
    try request.respond("you can now close this tab and return to the application", .{});

    const ret = try allocator.alloc(u8, request.head.target.len - 7);
    @memcpy(ret, request.head.target[7..]);
    return ret;
}

/// caller owns returned memory
fn acquireAuthorizationToken(allocator: Allocator, client: *Client, authCode: []const u8) !std.json.Parsed(AccessResponse) {
    const authTokenUrl = try std.Uri.parse("https://login.microsoftonline.com/consumers/oauth2/v2.0/token");
 
    var request = try client.request(.POST, authTokenUrl, .{ .extra_headers = &.{ 
        .{ .name = "Content-Type", .value = "application/x-www-form-urlencoded" },
    }});
    defer request.deinit();
 
    var payload_buf: [2048]u8 = undefined;
    const payload = try std.fmt.bufPrint(payload_buf[0..], "{s}{s}\n{s}", .{
        \\client_id=
        ++ Auth.client_id ++ "\n" ++
        \\&client_secret=
        ++ Auth.client_secret ++ "\n" ++
        \\&code=
        , authCode,
        \\&grant_type=authorization_code
        \\&redirect_uri=http://localhost:28003
    });
    try request.sendBodyComplete(payload);
 
    var buf: [1024]u8 = undefined;
    var response = try request.receiveHead(&buf);
    if(response.head.status != .ok) return error.HttpNotOk; 
 
    const body = try response.reader(&.{}).allocRemaining(allocator, .unlimited);
    defer allocator.free(body);
    const parsedBody = try std.json.parseFromSlice(AccessResponse, allocator, body, .{});
    return parsedBody;
}

/// caller owns returned memory
fn acquireXblToken(allocator: Allocator, client: *Client, authToken: []const u8) !std.json.Parsed(XboxResponse) {
    const xblTokenUrl = try std.Uri.parse("https://user.auth.xboxlive.com/user/authenticate");
 
    var request = try client.request(.POST, xblTokenUrl, .{ .extra_headers = &.{ 
        .{ .name = "Content-Type", .value = "application/json" }, 
        .{ .name = "Accept", .value = "application/json" },
    }});
    defer request.deinit();
 
    var payload_buf: [2048]u8 = undefined;
    const payload = try std.fmt.bufPrint(payload_buf[0..], "{s}{s}{s}", .{
        \\{
        \\    "Properties": {
        \\        "AuthMethod": "RPS",
        \\        "SiteName": "user.auth.xboxlive.com",
        \\        "RpsTicket": "d=
        , authToken, "\"\n" ++
        \\    },
        \\    "RelyingParty": "http://auth.xboxlive.com",
        \\    "TokenType": "JWT"
        \\}
    });
    try request.sendBodyComplete(payload);
 
    var buf: [1024]u8 = undefined;
    var response = try request.receiveHead(&buf);
    if(response.head.status != .ok) return error.HttpNotOk;
 
    const body = try response.reader(&.{}).allocRemaining(allocator, .unlimited);
    defer allocator.free(body);
    const parsedBody = try std.json.parseFromSlice(XboxResponse, allocator, body, .{});
    return parsedBody;
}
 
/// caller owns returned memory
fn acquireXstsToken(allocator: Allocator, client: *Client, xblToken: []const u8) !std.json.Parsed(XboxResponse) {
    const xstsTokenUrl = try std.Uri.parse("https://xsts.auth.xboxlive.com/xsts/authorize");
 
    var request = try client.request(.POST, xstsTokenUrl, .{ .extra_headers = &.{
        .{ .name = "Content-Type", .value = "application/json" }, 
        .{ .name = "Accept", .value = "application/json" } 
    }});
    defer request.deinit();
 
    var payload_buf: [2048]u8 = undefined;
    const payload = try std.fmt.bufPrint(payload_buf[0..], "{s}{s}{s}", .{
        \\{
        \\    "Properties": {
        \\        "SandboxId": "RETAIL",
        \\        "UserTokens": [
        ++ "\n\"", xblToken, "\"\n" ++
        \\        ]
        \\    },
        \\    "RelyingParty": "rp://api.minecraftservices.com/",
        \\    "TokenType": "JWT"
        \\}
    });
    try request.sendBodyComplete(payload);

    var buf: [1024]u8 = undefined;
    var response = try request.receiveHead(&buf);
    if(response.head.status != .ok) return error.HttpNotOk;
 
    const body = try response.reader(&.{}).allocRemaining(allocator, .unlimited);
    defer allocator.free(body);
    const parsedBody = try std.json.parseFromSlice(XboxResponse, allocator, body, .{});
    return parsedBody;
    // TODO error codes
}

/// caller owns returned memory
fn acquireMinecraftToken(allocator: Allocator, client: *Client, uhs: []const u8, xstsToken: []const u8) !std.json.Parsed(McResponse) {
    const mcLoginUrl = try std.Uri.parse("https://api.minecraftservices.com/authentication/login_with_xbox");
 
    var request = try client.request(.POST, mcLoginUrl, .{ .extra_headers = &.{
        .{ .name = "Content-Type", .value = "application/json" }, 
        .{ .name = "Accept", .value = "application/json" } 
    }});
    defer request.deinit();

    var payload_buf: [3072]u8 = undefined;
    const payload = try std.fmt.bufPrint(payload_buf[0..], "{s}{s}{s}{s}{s}", .{
        \\{
        \\    "identityToken": "XBL3.0 x=
        , uhs,
        ";"
        , xstsToken, "\"\n" ++
        \\}
    });
    try request.sendBodyComplete(payload);

    var buf: [1024]u8 = undefined;
    var response = try request.receiveHead(&buf);
    if(response.head.status != .ok) return error.HttpNotOk;
 
    var read_buf: [128]u8 = undefined;
    var decompress: std.http.Decompress = undefined;
    const body = try decompress.init(response.reader(&read_buf), &.{}, .gzip).allocRemaining(allocator, .unlimited);
    defer allocator.free(body);
    const parsedBody = try std.json.parseFromSlice(McResponse, allocator, body, .{});
    return parsedBody;
}
 
/// caller owns returned memory
fn acquireUserInfo(allocator: Allocator, client: *Client, mcToken: []const u8) !std.json.Parsed(UserResponse) {
    const mcProfileUrl = try std.Uri.parse("https://api.minecraftservices.com/minecraft/profile");
 
    var header_buf: [2048]u8 = undefined;
    const headerValue = try std.fmt.bufPrint(header_buf[0..], "Bearer {s}", .{mcToken});
 
    var request = try client.request(.GET, mcProfileUrl, .{ .extra_headers = &.{
        .{ .name = "Authorization", .value = headerValue },
    }});
    defer request.deinit();
    try request.sendBodiless();

    var buf: [1024]u8 = undefined;
    var response = try request.receiveHead(&buf);
    if(response.head.status != .ok) return error.HttpNotOk;
 
    var read_buf: [128]u8 = undefined;
    var decompress: std.http.Decompress = undefined;
    const body = try decompress.init(response.reader(&read_buf), &.{}, .gzip).allocRemaining(allocator, .unlimited);
    defer allocator.free(body);
    const parsedBody = try std.json.parseFromSlice(UserResponse, allocator, body, .{});
    return parsedBody;
}

fn verifyServer(client: *Client, mcToken: []const u8, uuid: []const u8, serverId: []const u8) !void {
    const verifyUrl = try std.Uri.parse("https://sessionserver.mojang.com/session/minecraft/join");

    var request = try client.request(.POST, verifyUrl, .{ .extra_headers = &.{
        .{ .name = "Content-Type", .value = "application/json" }, 
        .{ .name = "Accept", .value = "application/json" } 
    }});
    defer request.deinit();

    var payload_buf: [3072]u8 = undefined;
    const payload = try std.fmt.bufPrint(payload_buf[0..], "{s}{s}{s}{s}{s}{s}{s}", .{
        \\{
        \\    "accessToken": "
        , mcToken, "\",\n" ++
        \\    "selectedProfile": "
        , uuid, "\",\n" ++
        \\    "serverId": "
        , serverId, "\"\n" ++
        \\}
    });
    try request.sendBodyComplete(payload);

    var buf: [1024]u8 = undefined;
    const response = try request.receiveHead(&buf);
    if(response.head.status != .no_content) return error.HttpNotOk;
}

pub fn hexdigest(digest: *Sha1) i160 {
    var hash: [20]u8 = undefined;
    digest.final(&hash);
    return std.mem.readInt(i160, hash[0..], .big);
}

fn toString(uuid: i160, buf: []u8) []u8 {
    return std.fmt.bufPrint(buf, "{x}", .{uuid}) catch unreachable;
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

const AccessResponse = struct {
    token_type: []u8,
    scope: []u8,
    expires_in: i32,
    ext_expires_in: i32,
    access_token: []u8,
};

const XboxResponse = struct {
    IssueInstant: []u8,
    NotAfter: []u8,
    Token: []u8,
    DisplayClaims: struct {
        xui: []struct {
            uhs: []u8,
        },
    },
};

const McResponse = struct {
    username: []u8,
    roles: []struct {}, // always empty array?
    metadata: struct {},
    access_token: []u8,
    token_type: []u8,
    expires_in: i32,
};

const UserResponse = struct {
    id: []u8,
    name: []u8,
    skins: []struct {
        id: []u8,
        state: []u8,
        url: []u8,
        textureKey: []u8,
        variant: []u8,
    },
    capes: []struct {
        id: []u8,
        state: []u8,
        url: []u8,
        alias: []u8,
    },
    profileActions: struct {},
};
