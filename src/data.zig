const std = @import("std");
const Reader = std.Io.Reader;
const Writer = std.Io.Writer;
const Allocator = std.mem.Allocator;

const nbt = @import("nbt.zig");

// pub const Type = union(enum(u8)) {
//     Boolean: bool,
//     Byte: i8,
//     UnsignedByte: u8,
//     Short: i16,
//     UnsignedShort: u16,
//     Int: i32,
//     Long: i64,
//     Float: f32,
//     Double: f64,
//     String: []const u8,
//     Chat: []const u8,
//     VarInt: VarInt,
//     VarLong: VarLong,
//     Chunk: Chunk, // TODO see https://minecraft.wiki/w/Chunk_Format?oldid=2763879
//     Metadata: Metadata, // TODO see https://minecraft.wiki/w/Entity_metadata?oldid=2767708
//     Slot: Slot, // TODO see https://minecraft.wiki/w/Slot_Data?oldid=2768590
//     NBT = nbt.NBT,
//     Position: Position,
//     Angle: u8, // steps of 1/256 of a full turn
//     UUID: u64, 
//     Optional: ?anyopaque,
//     Array: []const anyopaque,
//     Enum: anyopaque,
//     ByteArray: []const i8,
// };

pub const VarInt = struct { 
    value: i32,

    pub fn init(reader: *Reader) !@This() { // TODO test probably need to switch endianness
        var i: u32 = 0;
        for(0..5) |offset| {
            const t = try reader.takeByte();
            i |= (t & 0x7f) << @as(u3, @truncate(offset * 7));
            if(t & 0x80 == 0x80) continue else break;
        }
        return .{ .value = @bitCast(i) };
    }

    pub inline fn write(self: @This(), writer: *Writer) !void {
        return try writeInt(self.value, writer);
    }

    pub fn writeInt(value: i32, writer: *Writer) !void {
        if(value == 0) {
            _ = try writer.writeByte(0);
            return;
        }
        // const needed_bytes: u8 = (@bitSizeOf(i32) - @clz(value) - 1) / 7 + 1;
        const needed_bytes: u8 = @truncate(countBytesInt(value));
        // var bytes: [needed_bytes]u8 = undefined;
        for(0..needed_bytes - 1) |idx| {
            // bytes[idx] = (@as(u8, @truncate(value >> (idx * 7))) & 0x7f) | 0x80;
            const byte = (@as(u8, @truncate(@as(u32, @bitCast(value)) >> @truncate(idx * 7))) & 0x7f) | 0x80;
            _ = try writer.writeByte(byte);
        }
        // bytes[needed_bytes - 1] = @as(u8, @truncate(value >> ((needed_bytes - 1) * 7))) & 0x7f;
        const byte = @as(u8, @truncate(@as(u32, @bitCast(value)) >> @truncate((needed_bytes - 1) * 7))) & 0x7f;
        _ = try writer.writeByte(byte);

        // _ = try writer.write(&bytes);
    }

    pub inline fn writeUnchecked(self: @This(), writer: *Writer) !void {
        return writeIntUnchecked(self.value, writer);
    }

    pub inline fn writeIntUnchecked(value: i32, writer: *Writer) !void {
        _ = try writer.writeByte(@as(u8, @truncate(@as(u32, @bitCast(value)))));
    }

    pub inline fn countBytes(self: @This()) u32 {
        return countBytesInt(self.value);
    }

    pub inline fn countBytesInt(value: i32) u32 {
        return if(value == 0) 1 else (@bitSizeOf(i32) - @clz(value) - 1) / 7 + 1;
    }
};

pub const VarLong = struct {
    value: i64,

    pub fn init(reader: *Reader) !@This() { // TODO test probably need to switch endianness
        var i: u64 = 0;
        for(0..10) |offset| {
            const t = try reader.takeByte();
            i |= (t & 0x7f) << (offset * 7);
            if(t & 0x80 == 1) continue else break;
        }
        return .{ .value = @bitCast(i) };
    }

    pub inline fn write(self: @This(), writer: *Writer) !void {
        return try writeLong(self.value, writer);
    }

    pub fn writeLong(value: i64, writer: *Writer) !void {
        if(value == 0) {
            _ = try writer.writeByte(0);
            return;
        }
        // const needed_bytes: u8 = (@bitSizeOf(i64) - @clz(value) - 1) / 7 + 1;
        const needed_bytes: u8 = @truncate(countBytesLong(value));
        var bytes: [needed_bytes]u8 = undefined;
        for(0..needed_bytes - 1) |idx| {
            bytes[idx] = (@as(u8, @truncate(value >> (idx * 7))) & 0x7f) | 0x80;
        }
        bytes[needed_bytes - 1] = @as(u8, @truncate(value >> ((needed_bytes - 1) * 7))) & 0x7f;

        _ = try writer.write(&bytes);
    }

    pub inline fn writeUnchecked(self: @This(), writer: *Writer) !void {
        return writeLongUnchecked(self.value, writer);
    }

    pub inline fn writeLongUnchecked(value: i64, writer: *Writer) !void {
        _ = try writer.writeByte(@as(u8, @truncate(@as(u64, @bitCast(value)))));
    }

    pub inline fn countBytes(self: @This()) u32 {
        return countBytesLong(self.value);
    }

    pub inline fn countBytesLong(value: i64) u32 {
        return if(value == 0 ) 1 else (@bitSizeOf(i64) - @clz(value) - 1) / 7 + 1;
    }
};

pub const String = struct {
    value: []const u8,
    allocator: ?Allocator,

    pub fn init(reader: *Reader, allocator: Allocator) !@This() {
        const len = (try VarInt.init(reader)).value;
        const buf = try allocator.alloc(u8, @intCast(len));
        @memcpy(buf, try reader.take(@intCast(len)));
        return .{ 
            .value = buf,
            .allocator = allocator,
        };
    }

    pub fn from(value: []const u8) @This() {
        return .{
            .value = value,
            .allocator = null,
        };
    }

    pub inline fn deinit(self: @This()) void {
        if(self.allocator) |alloc| {
            alloc.free(self.value);
        }
    }

    pub inline fn write(self: @This(), writer: *Writer) !void {
        return try writeString(self.value, writer);
    }

    pub inline fn writeString(value: []const u8, writer: *Writer) !void {
        _ = try VarInt.writeInt(@intCast(value.len), writer);
        _ = try writer.write(value);
    }

    pub inline fn countBytes(self: @This()) u32 {
        return countBytesString(self.value);
    }

    pub inline fn countBytesString(value: []const u8) u32 {
        return VarInt.countBytesInt(@intCast(value.len)) + @as(u32, @intCast(value.len));
    }
};

pub const Chat = String;

pub const Chunk = []const u8;

pub const Metadata = struct {
    keys: []const u8,
    values: []const Type,
    allocator: Allocator,

    const Type = union(enum(u3)) {
        byte: i8 = 0,
        short: i16 = 1,
        int: i32 = 2,
        float: f32 = 3,
        string: String = 4,
        slot: Slot = 5,
        // xyz: struct {x: i32, y: i32, z: i32}, // not currently used
        rotation: Rotation = 7,
    };

    pub const Rotation = struct {
        pitch: f32,
        yaw: f32,
        roll: f32,
    };

    pub fn init(reader: *Reader, allocator: Allocator) !@This() {
        var keys: std.ArrayList(u8) = .empty;
        defer keys.deinit(allocator);
        var values: std.ArrayList(Type) = .empty;
        defer values.deinit(allocator);
        
        while (try reader.takeByte() != 0x7f) {
            const kv = try reader.takeByte();
            try keys.append(allocator, kv & 0x1f);
            try values.append(allocator, switch(kv >> 5) {
                0 => .{ .byte = try reader.takeByteSigned() },
                1 => .{ .short = try reader.takeInt(i16, .big) },
                2 => .{ .int = try reader.takeInt(i32, .big) },
                3 => .{ .float = @as(f32, @bitCast(try reader.takeInt(u32, .big))) },
                4 => .{ .string = try String.init(reader, allocator) },
                5 => .{ .slot = try Slot.init(reader, allocator) },
                7 => .{ .rotation = .{
                    .pitch = @as(f32, @bitCast(try reader.takeInt(u32, .big))),
                    .yaw = @as(f32, @bitCast(try reader.takeInt(u32, .big))),
                    .roll = @as(f32, @bitCast(try reader.takeInt(u32, .big))),
                }},
            });
        }
    
        return .{
            .keys = keys.toOwnedSlice(allocator),
            .values = values.toOwnedSlice(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: @This()) void {
        self.allocator.free(self.keys);
        for(self.values) |element| {
            switch(element) {
                .string => |s| s.deinit(),
                .slot => |s| s.deinit(),
                else => {},
            }
        }
        self.allocator.free(self.values);
    }

    // I won't ever need to send Metadata to the server
};

pub const Slot = struct {
    itemID: i16,
    item_count: i8,
    item_damage: i16,
    nbt_available: bool,
    nbt: ?nbt.NBT,

    pub fn init(reader: *Reader, allocator: Allocator) !@This() {
        const itemID = try reader.takeInt(i16, .big);
        if(itemID == -1) {
            return .{
                .itemID = itemID,
                .item_count = undefined,
                .item_damage = undefined,
                .nbt_available = undefined,
                .nbt = undefined,
            };
        }
        return .{
            .itemID = itemID,
            .item_count = try reader.takeInt(i8, .big),
            .item_damage = try reader.takeInt(i16, .big),
            .nbt_available = (try reader.peekByte()) == 1,
            .nbt = if((try reader.takeByte()) == 1) nbt.NBT.init(&reader, allocator) else null,
            // TODO see if i need to init Compound instead
        };
    }

    pub fn deinit(self: @This()) void {
        if(self.itemID != -1) {
            if(self.nbt_available) {
                self.nbt.?.deinit();
            }
        }
    }

    pub fn write(self: @This(), writer: *Writer) !void {
        _ = .{ self, writer };
        // TODO implement
    }

    pub inline fn countBytes(self: @This()) u32 {
        _ = self;
        // TODO implement
    }

    const itemID_enum = enum(i16) {
        empty = -1,
        // ...
    };
};

pub const Position = packed struct {
    x: i26,
    y: i12,
    z: i26,
};

pub const FixedInt = packed struct {
    int: i27,
    float: u5,
};

pub const FixedByte = packed struct {
    int: i3,
    float: u5,
};
