const std = @import("std");
const Reader = std.Io.Reader;
const Writer = std.Io.Writer;
const Allocator = std.mem.Allocator;

pub const Tag = enum(u8) { 
    End         = 0x00, // end of Compound
    Byte        = 0x01, // i8
    Short       = 0x02, // i16
    Int         = 0x03, // i32
    Long        = 0x04, // i64
    Float       = 0x05, // f32
    Double      = 0x06, // f64
    ByteArray   = 0x07, // i32 size -> [tagByte]
    String      = 0x08, // u16 size -> [u8] (UTF-8)
    List        = 0x09, // u8 tagID -> i32 size -> [var_tagID]
    Compound    = 0x0a, // [u8 tagID -> tagString name -> var_tagID : tagEnd]
    IntArray    = 0x0b, // i32 size -> [tagInt]
    LongArray   = 0x0c, // i32 size -> [tagLong]
};

pub const Value = union(Tag) {
    End: void,
    Byte: i8,
    Short: i16,
    Int: i32,
    Long: i64,
    Float: f32,
    Double: f64,
    ByteArray: []const i8,
    String: []const u8,
    List: List,
    Compound: Compound,
    IntArray: []const i32,
    LongArray: []const i64,

    const Self = @This();

    fn init(reader: *Reader, allocator: Allocator, tag: Tag) anyerror!Self {
        return switch(tag) {
            .End        => .{ .End = {} },
            .Byte       => .{ .Byte = try reader.takeByteSigned() },
            .Short      => .{ .Short = try reader.takeInt(i16, .big) },
            .Int        => .{ .Int = try reader.takeInt(i32, .big) },
            .Long       => .{ .Long = try reader.takeInt(i64, .big) },
            .Float      => .{ .Float = @as(f32, @bitCast(try reader.takeInt(u32, .big))) },
            .Double     => .{ .Double = @as(f64, @bitCast(try reader.takeInt(u64, .big))) },
            .ByteArray  => .{ .ByteArray = try initArray(reader, allocator, i8) },
            .String     => .{ .String = try initString(reader, allocator) },
            .List       => .{ .List = try List.init(reader, allocator) },
            .Compound   => .{ .Compound = try Compound.init(reader, allocator) },
            .IntArray   => .{ .IntArray = try initArray(reader, allocator, i32) },
            .LongArray  => .{ .LongArray = try initArray(reader, allocator, i64) },
        };
    }

    fn deinit(self: Self, allocator: Allocator) void {
        switch(self) {
            .ByteArray  => |b| allocator.free(b),
            .String     => |s| allocator.free(s),
            .List       => |l| l.deinit(),
            .Compound   => |v| v.deinit(),
            .IntArray   => |i| allocator.free(i),
            .LongArray  => |v| allocator.free(v),
            else => {},
        }
    }

    pub inline fn get(self: Self, tag: Tag) std.meta.TagPayload(Self, tag) {
        return switch(tag) { 
            .End        => .End,
            .Byte       => self.Byte,
            .Short      => self.Short,
            .Int        => self.Int,
            .Long       => self.Long,
            .Float      => self.Float,
            .Double     => self.Double,
            .ByteArray  => self.ByteArray,
            .String     => self.String,
            .List       => self.List,
            .Compound   => self.Compound,
            .IntArray   => self.IntArray,
            .LongArray  => self.LongArray,
        };
    }
};

fn initString(reader: *Reader, allocator: Allocator) ![]const u8 {
    const len = try reader.takeInt(u16, .big);
    const buf = try allocator.alloc(u8, len);
    std.mem.copyForwards(u8, buf, try reader.take(len));
    return buf;
}

fn initArray(reader: *Reader, allocator: Allocator, T: type) ![]const T {
    const len = try reader.takeInt(u32, .big);
    const buf = try allocator.alloc(T, len);
    std.mem.copyForwards(T, buf, @ptrCast(@alignCast(try reader.take(len))));
    return buf;
}

pub const Compound = struct {
    allocator: Allocator,
    data: std.StringHashMap(Value),

    const Self = @This();

    fn init(reader: *Reader, allocator: Allocator) !Self {
        var self: Self = .{
            .allocator = allocator,
            .data = std.StringHashMap(Value).init(allocator),
        };

        while(reader.takeByte()) |t| {
            const tag: Tag = @enumFromInt(t);
            if(tag == .End) { break; }

            const name = try initString(reader, allocator);
            const val = try Value.init(reader, allocator, tag);

            try self.data.put(name, val);
        } else |err| return err;
        
        return self;
    }

    fn deinit(self: *const Self) void {
        var it = self.data.iterator();
        while(it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.*.deinit(self.allocator);
        }
        @constCast(self).data.deinit();
    }

    pub inline fn get(self: *const Self, key: []const u8) Value {
        return self.data.get(key) orelse .End;
    }
};

pub const List = struct {
    tag: Tag,
    allocator: Allocator,
    values: []Value,

    const Self = @This();

    fn init(reader: *Reader, allocator: Allocator) !Self {
        const tag: Tag = @enumFromInt(try reader.takeByte());
        const len = try reader.takeInt(u32, .big);
        const buf = try allocator.alloc(Value, len);
        for(0..len) |it| {
            buf[it] = try Value.init(reader, allocator, tag);
        }
        return .{
            .tag = tag,
            .allocator = allocator,
            .values = buf,
        };
    }

    fn deinit(self: *const Self) void {
        for(self.values) |val| {
            val.deinit(self.allocator);
        }
        self.allocator.free(self.values);
    }

    pub inline fn get(self: *const Self, idx: u32) Value {
        if(idx >= self.values.len) { return .End; }
        return self.values[idx];
    }
};

pub const NBT = struct {
    allocator: Allocator,
    name: []const u8,
    fields: Compound,

    const Self = @This();

    pub fn init(reader: *Reader, allocator: Allocator) !Self {
        std.debug.assert(try reader.takeByte() == @intFromEnum(Tag.Compound));
        return .{
            .allocator = allocator,
            .name = try initString(reader, allocator),
            .fields = try Compound.init(reader, allocator),
        };
    }

    pub fn deinit(self: *const Self) void {
        self.allocator.free(self.name);
        self.fields.deinit();
    }

    pub inline fn get(self: *const Self, key: []const u8) Value {
        return self.fields.get(key);
    }
};

pub fn print(value: NBT, writer: *Writer) !void {
    try printCompoundEntry(value.name, .{ .Compound = value.fields }, writer, 0);
    try writer.flush();
}

fn printCompoundEntry(key: []const u8, value: Value, writer: *Writer, indent: u32) anyerror!void {
    if(std.meta.activeTag(value) == .End) return;
    for(0..indent) |_| try writer.print("\t", .{});
    switch(value) {
        .Byte => |b| try writer.print("TAG_Byte('{s}'): {}\n", .{key, b}),
        .Short => |s| try writer.print("TAG_Short('{s}'): {}\n", .{key, s}),
        .Int => |i| try writer.print("TAG_Int('{s}'): {}\n", .{key, i}),
        .Long => |l| try writer.print("TAG_Long('{s}'): {}\n", .{key, l}),
        .Float => |f| try writer.print("TAG_Float('{s}'): {}\n", .{key, f}),
        .Double => |d| try writer.print("TAG_Double('{s}'): {}\n", .{key, d}),
        .ByteArray => |b| {
            try writer.print("TAG_ByteArray('{s}'): [B;", .{key});
            for(0..b.len-1) |v| try writer.print("{},", .{v}); 
            if(b.len != 0) try writer.print("{}", .{b[b.len - 1]});
            try writer.print("]\n", .{});
        },
        .String => |s| try writer.print("TAG_String('{s}'): '{s}'\n", .{key, s}),
        .List => |l| {
            try writer.print("TAG_List('{s}'): {} entries\n", .{key, l.values.len});
            for(0..indent) |_| try writer.print("\t", .{});
            try writer.print("{{\n", .{});
            
            try printList(l.values, writer, indent + 1);

            for(0..indent) |_| try writer.print("\t", .{});
            try writer.print("}}\n", .{});
        },
        .Compound => |c| {
            try writer.print("TAG_Compound('{s}'): {} entries\n", .{key, c.data.count()});
            for(0..indent) |_| try writer.print("\t", .{});
            try writer.print("{{\n", .{});

            var it = c.data.iterator();
            while(it.next()) |kv| {
                try printCompoundEntry(kv.key_ptr.*, kv.value_ptr.*, writer, indent + 1);
            }

            for(0..indent) |_| try writer.print("\t", .{});
            try writer.print("}}\n", .{});
        },
        .IntArray => |i| {
            try writer.print("TAG_IntArray('{s}'): [I;", .{key});
            for(i) |v| try writer.print("{},", .{v}); 
            if(i.len != 0) try writer.print("{}", .{i[i.len - 1]});
            try writer.print("]\n", .{});
        },
        .LongArray => |l| {
            try writer.print("TAG_LongArray('{s}'): [L;", .{key});
            for(l) |v| try writer.print("{},", .{v}); 
            if(l.len != 0) try writer.print("{}", .{l[l.len - 1]});
            try writer.print("]\n", .{});
        },
        else => {},
    }
}

fn printList(values: []Value, writer: *Writer, indent: u32) anyerror!void {
    for(values) |value| {
        for(0..indent) |_| try writer.print("\t", .{});
        switch(value) {
            .Byte => |b| try writer.print("TAG_Byte(None): {}\n", .{b}),
            .Short => |s| try writer.print("TAG_Short(None): {}\n", .{s}),
            .Int => |i| try writer.print("TAG_Int(None): {}\n", .{i}),
            .Long => |l| try writer.print("TAG_Long(None): {}\n", .{l}),
            .Float => |f| try writer.print("TAG_Float(None): {}\n", .{f}),
            .Double => |d| try writer.print("TAG_Double(None): {}\n", .{d}),
            .ByteArray => |b| {
                try writer.print("TAG_ByteArray(None): [B;", .{});
                for(0..b.len-1) |v| try writer.print("{},", .{v}); 
                if(b.len != 0) try writer.print("{}", .{b[b.len - 1]});
                try writer.print("]\n", .{});
            },
            .String => |s| try writer.print("TAG_String(None): '{s}'\n", .{s}),
            .List => |l| {
                try writer.print("TAG_List(None): {} entries\n", .{l.values.len});
                for(0..indent) |_| try writer.print("\t", .{});
                try writer.print("{{\n", .{});
                
                try printList(l.values, writer, indent + 1);

                for(0..indent) |_| try writer.print("\t", .{});
                try writer.print("}}\n", .{});
            },
            .Compound => |c| {
                try writer.print("TAG_Compound(None): {} entries\n", .{c.data.count()});
                for(0..indent) |_| try writer.print("\t", .{});
                try writer.print("{{\n", .{});

                var it = c.data.iterator();
                while(it.next()) |kv| {
                    try printCompoundEntry(kv.key_ptr.*, kv.value_ptr.*, writer, indent + 1);
                }

                for(0..indent) |_| try writer.print("\t", .{});
                try writer.print("}}\n", .{});
            },
            .IntArray => |i| {
                try writer.print("TAG_IntArray(None): [I;", .{});
                for(i) |v| try writer.print("{},", .{v}); 
                if(i.len != 0) try writer.print("{}", .{i[i.len - 1]});
                try writer.print("]\n", .{});
            },
            .LongArray => |l| {
                try writer.print("TAG_LongArray(None): [L;", .{});
                for(l) |v| try writer.print("{},", .{v}); 
                if(l.len != 0) try writer.print("{}", .{l[l.len - 1]});
                try writer.print("]\n", .{});
            },
            else => {},
        }
    }
}
