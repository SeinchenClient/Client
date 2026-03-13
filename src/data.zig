const std = @import("std");
const Reader = std.Io.Reader;
const Writer = std.Io.Writer;

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

    pub fn init(reader: Reader) !@This() { // TODO test probably need to switch endianness
        var i: u32 = 0;
        for(0..5) |offset| {
            const t = try reader.takeByte();
            i |= (t & 0x7f) << (offset * 7);
            if(t & 0x80 == 1) continue else break;
        }
        return .{ .value = @bitCast(i) };
    }

    pub fn into(self: @This(), writer: Writer) !void {
        // if parameter is 0, @clz returns the bit width of the parameter type
        if(self.value == 0) {
            _ = try writer.writeByte(0);
            return;
        }
        const needed_bytes: u8 = (@bitSizeOf(@TypeOf(self.value)) - @clz(self.value) - 1) / 7 + 1;
        var bytes: [needed_bytes]u8 = undefined;
        for(0..needed_bytes - 1) |idx| {
            bytes[idx] = (@as(u8, @truncate(self.value >> (idx * 7))) & 0x7f) | 0x80;
        }
        bytes[needed_bytes - 1] = @as(u8, @truncate(self.value >> ((needed_bytes - 1) * 7))) & 0x7f;

        _ = try writer.write(&bytes);
    }
};

pub const VarLong = struct {
    value: i64,

    pub fn init(reader: Reader) !@This() { // TODO test probably need to switch endianness
        var i: u64 = 0;
        for(0..10) |offset| {
            const t = try reader.takeByte();
            i |= (t & 0x7f) << (offset * 7);
            if(t & 0x80 == 1) continue else break;
        }
        return .{ .value = @bitCast(i) };
    }

    pub fn into(self: @This(), writer: Writer) !void {
        // if parameter is 0, @clz returns the bit width of the parameter type
        if(self.value == 0) {
            _ = try writer.writeByte(0);
            return;
        }
        const needed_bytes: u8 = (@bitSizeOf(@TypeOf(self.value)) - @clz(self.value) - 1) / 7 + 1;
        var bytes: [needed_bytes]u8 = undefined;
        for(0..needed_bytes - 1) |idx| {
            bytes[idx] = (@as(u8, @truncate(self.value >> (idx * 7))) & 0x7f) | 0x80;
        }
        bytes[needed_bytes - 1] = @as(u8, @truncate(self.value >> ((needed_bytes - 1) * 7))) & 0x7f;

        _ = try writer.write(&bytes);
    }
};

pub const String = []const u8; // deconstruct fat pointer into len->VarInt and body

pub const Chat = String;

pub const Chunk = []const u8;

pub const Metadata = []const u8;

pub const Slot = []const u8;

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
