const datatypes = @import("data.zig");
const VarInt = datatypes.VarInt;
const VarLong = datatypes.VarLong;
const String = datatypes.String;
const Chat = datatypes.Chat;
const Position = datatypes.Position;
const FixedInt = datatypes.FixedInt;
const FixedByte = datatypes.FixedByte;
const Chunk = datatypes.Chunk;
const Metadata = datatypes.Metadata;
const Slot = datatypes.Slot;

const NBT = @import("nbt.zig").NBT;

const std = @import("std");
const Writer = std.Io.Writer;
const Reader = std.Io.Reader;
const Allocator = std.mem.Allocator;

pub const State = enum {
    handshake,
    status,
    login,
    play,
};

pub const ID = union(State) {
    handshake: union(enum(u1)) {
        clientbound: enum(u8) {},
        serverbound: enum(u8) {
            Handshake = 0x00,
        },
    },
    status: union(enum(u1)) {
        clientbound: enum(u8) {
            Response = 0x00,
            Pong = 0x01,
        },
        serverbound: enum(u8) {
            Request = 0x00,
            Ping = 0x01,
        },
    },
    login: union(enum(u1)) {
        clientbound: enum(u8) {
            Disconnect = 0x00,
            Encryption_Request = 0x01,
            Login_Success = 0x02,
            Set_Compression = 0x03,
        },
        serverbound: enum(u8) {
            Login_Start = 0x00,
            Encryption_Response = 0x01,
        },
    },
    play: union(enum(u1)) {
        clientbound: enum(u8) {
            Keep_Alive = 0x00,
            Join_Game = 0x01,
            Chat_Message = 0x02,
            Time_Update = 0x03,
            Entity_Equipment = 0x04,
            Spawn_Position = 0x05,
            Update_Health = 0x06,
            Respawn = 0x07,
            Player_Position_And_Look = 0x08,
            Held_Item_Change = 0x09,
            Use_Bed = 0x0a,
            Animation = 0x0b,
            Spawn_Player = 0x0c,
            Collect_Item = 0x0d,
            Spawn_Object = 0x0e,
            Spawn_Mob = 0x0f,
            Spawn_Painting = 0x10,
            Spawn_Experience_Orb = 0x11,
            Entity_Velocity = 0x12,
            Destroy_Entities = 0x13,
            Entity = 0x14,
            Entity_Relative_Move = 0x15,
            Entity_Look = 0x16,
            Entity_Look_And_Relative_Move = 0x17,
            Entity_Teleport = 0x18,
            Entity_Head_Look = 0x19,
            Entity_Status = 0x1a,
            Attach_Entity = 0x1b,
            Entity_Metadata = 0x1c,
            Entity_Effect = 0x1d,
            Remove_Entity_Effect = 0x1e,
            Set_Experience = 0x1f,
            Entity_Properties = 0x20,
            Chunk_Data = 0x21,
            Multi_Block_Change = 0x22,
            Block_Change = 0x23,
            Block_Action = 0x24,
            Block_Break_Animation = 0x25,
            Map_Chunk_Bulk = 0x26,
            Explosion = 0x27,
            Effect = 0x28,
            Sound_Effect = 0x29,
            Particle = 0x2a,
            Change_Game_State = 0x2b,
            Spawn_Global_Entity = 0x2c,
            Open_Window = 0x2d,
            Close_Window = 0x2e,
            Set_Slot = 0x2f,
            Window_Items = 0x30,
            Window_Property = 0x31,
            Confirm_Transaction = 0x32,
            Update_Sign = 0x33,
            Map = 0x34,
            Update_Block_Entity = 0x35,
            Open_Sign_Editor = 0x36,
            Statistics = 0x37,
            Player_List_Item = 0x38,
            Player_Abilities = 0x39,
            Tab_Complete = 0x3a,
            Scoreboard_Objective = 0x3b,
            Update_Score = 0x3c,
            Display_Scoreboard = 0x3d,
            Teams = 0x3e,
            Plugin_Message = 0x3f,
            Disconnect = 0x40,
            Server_Difficulty = 0x41,
            Combat_Event = 0x42,
            Camera = 0x43,
            World_Border = 0x44,
            Title = 0x45,
            Set_Compression = 0x46,
            Player_List_Header_And_Footer = 0x47,
            Resource_Pack_Send = 0x48,
            Update_Entity_NBT = 0x49,
        },
        serverbound: enum(u8) {
            Keep_Alive = 0x00,
            Chat_Message = 0x01,
            Use_Entity = 0x02,
            Player = 0x03,
            Player_Position = 0x04,
            Player_Look = 0x05,
            Player_Position_And_Look = 0x06,
            Player_Digging = 0x07,
            Player_Block_Placement = 0x08,
            Held_Item_Change = 0x09,
            Animation = 0x0a,
            Entity_Action = 0x0b,
            Steer_Vehicle = 0x0c,
            Close_Window = 0x0d,
            Click_Window = 0x0e,
            Confirm_Transaction = 0x0f,
            Creative_Inventory_Action = 0x10,
            Enchant_Item = 0x11,
            Update_Sign = 0x12,
            Player_Abilities = 0x13,
            Tab_Complete = 0x14,
            Client_Settings = 0x15,
            Client_Status = 0x16,
            Plugin_Message = 0x17,
            Spectate = 0x18,
            Resource_Pack_Status = 0x19,
        },
    },
};

pub const Header = struct {
    length: VarInt,
    packet_ID: ID,
};

pub const handshake = struct {
    pub const clientbound = struct {};

    pub const serverbound = struct {
        pub const Handshake = struct {
            protocol_version: VarInt,
            server_address: String,
            server_port: u16,
            next_state: VarInt,

            pub fn send(self: @This(), writer: *Writer) !void {
                try VarInt.writeInt(@bitCast(self.protocol_version.countBytes()
                                    + self.server_address.countBytes()
                                    + 2
                                    + self.next_state.countBytes()
                                    + 1),
                    writer
                );
                const id: ID = .{.handshake = .{.serverbound = .Handshake}};
                try VarInt.writeInt(@intFromEnum(id.handshake.serverbound), writer);
                
                try self.protocol_version.write(writer);
                try self.server_address.write(writer);
                _ = try writer.writeInt(u16, self.server_port, .big);
                try self.next_state.write(writer);

                try writer.flush();
            }
        };
    };
};

pub const status = struct {
    pub const clientbound = struct {
        pub const Response = struct {
            JSON_response: String,
        };

        pub const Pong = struct {
            payload: u64,
        };
    };

    pub const serverbound = struct {
        pub const Request = struct {};

        pub const Ping = struct {
            payload: u64,
        };
    };
};

pub const login = struct {
    pub const clientbound = struct {
        pub const Disconnect = struct {
            reason: Chat,
        };
        
        pub const Encryption_Request = struct {
            server_ID: String,
            public_key_length: VarInt,
            public_key: []const u8,
            verify_token_length: VarInt,
            verify_token: []const u8,
        };

        pub const Login_Success = struct {
            UUID: String,
            username: String,
        };

        pub const Set_Compression = struct {
            threshold: VarInt,
        };
    };

    pub const serverbound = struct {
        pub const Login_Start = struct {
            name: String,
        };

        pub const Encryption_Response = struct {
            shared_secret_length: VarInt,
            shared_secret: []const u8,
            verify_token_length: VarInt,
            verify_token: []const u8,
        };
    };
};

pub const play = struct {
    pub const clientbound = struct {
        pub const Keep_Alive = struct {
            keep_alive_ID: VarInt,
        };

        pub const Join_Game = struct {
            entity_ID: i32,
            gamemode: u8,
            dimension: i8,
            difficulty: u8,
            max_players: u8,
            level_type: String,
            reduced_debug_info: bool,
        };

        pub const Chat_Message = struct {
            JSON_Data: Chat,
            position: i8,
        };

        pub const Time_Update = struct {
            world_age: i64,
            time_of_day: i64,
        };

        pub const Entity_Equipment = struct {
            entity_ID: VarInt,
            slot: i16,
            item: Slot,
        };

        pub const Spawn_Position = struct {
            location: Position,
        };

        pub const Update_Health = struct {
            health: f32,
            food: VarInt,
            food_saturation: f32,
        };

        pub const Respawn = struct {
            dimension: i32,
            difficulty: u8,
            gamemode: u8,
            level_type: String,
        };

        pub const Player_Position_And_Look = struct {
            x: f64,
            y: f64,
            z: f64,
            yaw: f32,
            pitch: f32,
            flags: i8,

            const flags_enum = enum(i8) {
                x = 0x01,
                y = 0x02,
                z = 0x04,
                y_rot = 0x08,
                x_rot = 0x10,
            };
        };

        pub const Held_Item_Change = struct {
            slot: i8,
        };

        pub const Use_Bed = struct {
            entity_ID: VarInt,
            location: Position,
        };

        pub const Animation = struct {
            entity_ID: VarInt,
            animation: u8,

            const animation_enum = enum(u8) {
                swing_arm = 0,
                take_damage = 1,
                leave_bed = 2,
                eat_food = 3,
                critical_effect = 4,
                magic_critical_effect = 5,
            };
        };

        pub const Spawn_Player = struct {
            entity_ID: VarInt,
            player_UUID: u64,
            x: FixedInt,
            y: FixedInt,
            z: FixedInt,
            yaw: u8,
            pitch: u8,
            current_item: i16,
            metadata: Metadata,
        };

        pub const Collect_Item = struct {
            collected_entity_ID: VarInt,
            collector_entity_ID: VarInt,
        };

        pub const Spawn_Object = struct {
            entity_ID: VarInt,
            @"type": i8,
            x: FixedInt,
            y: FixedInt,
            z: FixedInt,
            pitch: u8,
            yaw: u8,
            data: i32,
            velocity_x: ?i16,
            velocity_y: ?i16,
            velocity_z: ?i16,
        };

        pub const Spawn_Mob = struct {
            entity_ID: VarInt,
            @"type": i8,
            x: FixedInt,
            y: FixedInt,
            z: FixedInt,
            yaw: u8,
            pitch: u8,
            head_pitch: u8,
            data: i32,
            velocity_x: ?i16,
            velocity_y: ?i16,
            velocity_z: ?i16,
            metadata: Metadata,
        };

        pub const Spawn_Painting = struct {
            entity_ID: VarInt,
            title: String,
            location: Position,
            direction: u8,
        };

        pub const Spawn_Experience_Orb = struct {
            entity_ID: VarInt,
            x: FixedInt,
            y: FixedInt,
            z: FixedInt,
            count: i16,
        };

        pub const Entity_Velocity = struct {
            entity_ID: VarInt,
            velocity_x: i16,
            velocity_y: i16,
            velocity_z: i16,
        };

        pub const Destroy_Entities = struct {
            count: VarInt,
            entity_IDs: []VarInt,
        };

        pub const Entity = struct {
            entity_ID: VarInt,
        };

        pub const Entity_Relative_Move = struct {
            entity_ID: VarInt,
            delta_x: FixedByte,
            delta_y: FixedByte,
            delta_z: FixedByte,
            on_gound: bool,
        };

        pub const Entity_Look = struct {
            entity_ID: VarInt,
            yaw: u8,
            pitch: u8,
            on_ground: bool,
        };

        pub const Entity_Look_And_Relative_Move = struct {
            entity_ID: VarInt,
            delta_x: FixedByte,
            delta_y: FixedByte,
            delta_z: FixedByte,
            yaw: u8,
            pitch: u8,
            on_ground: bool,
        };

        pub const Entity_Teleport = struct {
            entity_ID: VarInt,
            x: FixedInt,
            y: FixedInt,
            z: FixedInt,
            yaw: u8,
            pitch: u8,
            on_ground: bool,
        };

        pub const Entity_Head_Look = struct {
            entity_ID: VarInt,
            head_yaw: u8,
        };

        pub const Entity_Status = struct {
            entity_ID: i32,
            entity_status: i8,

            const entity_status_enum = enum(i8) {
                mob_spawn_minecart_time_reset_OR_rabbit_jump_animation = 1,
                living_entity_hurt = 2,
                living_entity_dead = 3,
                iron_golem_arms = 4,
                taming_heart_particles = 6,
                tamed_smoke_particles = 7,
                wolf_shaking_water_animation = 8,
                eating = 9,
                sheep_eating_grass_OR_tnt_ignite_sound = 10,
                iron_golem_rose = 11,
                villager_mating_heart_particles = 12,
                villager_angry_particles = 13,
                villager_happy_particles = 14,
                witch_magic_particles = 15,
                zombie_to_villager_sound = 16,
                firework_exploding = 17,
                animal_mate_heart_particles = 18,
                reset_squid_rotation = 19,
                explosion_particle = 20,
                guardian_sound = 21,
                enable_reduced_debug_info = 22,
                disable_reduced_debug_info = 23,
            };
        };

        pub const Attach_Entity = struct {
            entity_ID: i32,
            vehicle_ID: i32,
            leash: bool,
        };

        pub const Entity_Metadata = struct {
            entity_ID: VarInt,
            metadata: Metadata,
        };

        pub const Entity_Effect = struct {
            entity_ID: VarInt,
            effect_ID: i8,
            amplifier: i8,
            duration: VarInt,
            hide_particles: bool,
        };

        pub const Remove_Entity_Effect = struct {
            entity_ID: VarInt,
            effect_ID: i8,
        };

        pub const Set_Experience = struct {
            experience_bar: f32,
            level: VarInt,
            total_experience: VarInt,
        };

        pub const Entity_Properties = struct {
            entity_ID: VarInt,
            number_of_properties: i32,
            property: []const Property,
    
            const Property = struct {
                key: String,
                value: f64,
                number_of_modifiers: VarInt,
                modifiers: []const Modifier,
            };

            const Modifier = struct {
                UUID: u64,
                amount: f64,
                operation: i8,
            };
        };

        pub const Chunk_Data = struct {
            chunk_x: i32,
            chunk_z: i32,
            continuous: bool,
            bitmask: u16,
            size: VarInt,
            data: Chunk,
        };

        pub const Multi_Block_Change = struct {
            chunk_x: i32,
            chunk_z: i32,
            record_count: VarInt,
            record: []const Record,
            
            const Record = struct {
                horizontal_position: packed struct {
                    x: u4,
                    z: u4,
                },
                y_coordinate: u8,
                block_ID: VarInt,
            };
        };

        pub const Block_Change = struct {
            location: Position,
            block_ID: VarInt,
        };

        pub const Block_Action = struct {
            location: Position,
            byte_1: u8,
            byte_2: u8,
            block_type: VarInt,
        };

        pub const Block_Break_Animation = struct {
            entity_ID: VarInt,
            location: Position,
            destroy_stage: i8,
        };

        pub const Map_Chunk_Bulk = struct {
            sky_light_sent: bool,
            chunk_column_count: VarInt,
            chunk_meta: []const ChunkMeta,
            chunk_data: []const Chunk,

            const ChunkMeta = struct {
                chunk_x: i32,
                chunk_y: i32,
                bitmask: u16,
            };
        };

        pub const Explosion = struct {
            x: f32,
            y: f32,
            z: f32,
            radius: f32,
            record_count: i32,
            records: []const struct {
                x: i8,
                y: i8,
                z: i8,
            },
            player_motion_x: f32,
            player_motion_y: f32,
            player_motion_z: f32,
        };

        pub const Effect = struct {
            effect_ID: i32,
            location: Position,
            data: i32,
            disable_relative_volume: bool,

            const effect_ID_enum = enum(i32) {
                random_click1 = 1000,
                random_click2 = 1001,
                random_box = 1002,
                random_door_open_OR_random_door_close = 1003, // random
                random_fizz = 1004,
                music_disk = 1005,
                mob_ghast_charge = 1007,
                mob_ghast_fireball = 1008,
                mob_ghast_fireball_lower = 1009,
                mob_zombie_wood = 1010,
                mob_zombie_metal = 1011,
                mob_zombie_woodbreak = 1012,
                mob_wither_spawn = 1013,
                mob_wither_shoot = 1014,
                mob_bat_takeoff = 1015,
                mob_zombie_infect = 1016,
                mob_zombie_unfect = 1017,
                mob_enderdragon_end = 1018,
                random_anvil_break = 1020,
                random_anvil_use = 1021,
                random_anvil_land = 1022,
                
                smoke = 2000,
                block_break = 2001,
                splash_potion_effect_and_sound = 2002,
                eye_ender_break_animation_effect_and_sound = 2003,
                mob_spawn_particle_smoke_and_flames = 2004,
                happy_villager_effect_and_bonemealing = 2005,
            };

            const smoke_directions = enum(i32) {
                south_east = 0,
                south = 1,
                south_west = 2,
                east = 3,
                up = 4,
                west = 5,
                north_east = 6,
                north = 7,
                north_west = 8,
            };
        };

        pub const Sound_Effect = struct {
            sound_name: String,
            effect_position_x: i32,
            effect_position_y: i32,
            effect_position_z: i32,
            volume: f32,
            pitch: u8,
        };

        pub const Particle = struct {
            particle_ID: i32,
            long_distance: bool,
            x: f32,
            y: f32,
            z: f32,
            offset_x: f32,
            offset_y: f32,
            offset_z: f32,
            particle_data: f32,
            particle_count: i32,
            data: []VarInt,

            pub const particle_ID_enum = enum(i32) {
                explode = 0,
                largeexplosion = 1,
                hugeexplosion = 2,
                fireworksSpark = 3,
                bubble = 4,
                splash = 5,
                wake = 6,
                suspended = 7,
                depthsuspend = 8,
                crit = 9,
                magicCrit = 10,
                smoke = 11,
                largesmoke = 12,
                spell = 13,
                instantSpell = 14,
                mobSpell = 15,
                mobSpellAmbient = 16,
                witchMagic = 17,
                dripWater = 18,
                dripLava = 19,
                angryVillager = 20,
                happyVillager = 21,
                townaura = 22,
                note = 23,
                portal = 24,
                enchantmenttable = 25,
                flame = 26,
                lava = 27,
                footstep = 28,
                cloud = 29,
                reddust = 30,
                snowballpoof = 31,
                snowshovel = 32,
                slime = 33,
                heart = 34,
                barrier = 35,
                iconcrack_x_y = 36,
                blockcrack_xy = 37,
                blockdust_x = 38,
                droplet	= 39,
                take = 40,
                mobappearance = 41,
            };
        };

        pub const Change_Game_State = struct {
            reason: u8,
            value: f32,
    
            const reason_enum = enum(u8) {
                invalid_bed = 0,
                end_raining = 1,
                begin_raining = 2,
                change_game_mode = 3,
                enter_credits = 4,
                demo_message = 5,
                arrow_hitting_player = 6,
                fade_value = 7,
                fade_time = 8,
                play_mob_appearance = 10,
            };
        };

        pub const Spawn_Global_Entity = struct {
            entity_ID: VarInt,
            @"type": i8,
            x: FixedInt,
            y: FixedInt,
            z: FixedInt,
        };

        pub const Open_Window = struct {
            window_ID: u8,
            window_type: String,
            window_title: Chat,
            number_of_slots: u8,
            entity_ID: ?i32,
        };

        pub const Close_Window = struct {
            window_ID: u8,
        };

        pub const Set_Slot = struct {
            window_ID: i8,
            slot: i16,
            slot_data: Slot,
        };

        pub const Window_Items = struct {
            window_ID: u8,
            count: i16,
            slot_data: []const Slot,
        };

        pub const Window_Property = struct {
            window_ID: u8,
            property: i16,
            value: i16,

            const furnace_properties = enum(i16) {
                fire_icon = 0,
                maximum_fuel_burn_time = 1,
                progress_arrow = 2,
                maximum_progress = 3,
            };

            const enchantment_table_properties = enum(i16) {
                level_requirement_top_slot = 0,
                level_requirement_middle_slot = 1,
                level_requirement_bottom_slot = 2,
                enchantment_view_seed = 3,
                enchantment_hover_top_slot = 4,
                enchantment_hover_middle_slot = 5,
                enchantment_hover_bottom_slot = 6,
            };

            const beacon_properties = enum(i16) {
                power_level = 0,
                first_potion_effect = 1,
                second_potion_effect = 2,
            };

            const anvil_properties = enum(i16) {
                repair_cost = 0,
            };
    
            const brewing_stand_properties = enum(i16) {
                brew_time = 0,
            };
        };

        pub const Confirm_Transaction = struct {
            window_ID: i8,
            action_number: i16,
            accepted: bool,
        };

        pub const Update_Sign = struct {
            location: Position,
            line_1: Chat,
            line_2: Chat,
            line_3: Chat,
            line_4: Chat,
        };

        pub const Map = struct {
            item_damage: VarInt,
            scale: i8,
            icon_count: VarInt,
            icon: []const Icon,
            columns: i8,
            rows: ?i8,
            x: ?i8,
            y: ?i8,
            length: ?VarInt,
            data: ?[]const u8,

            const Icon = struct {
                direction_and_type: packed struct {
                    direction: u4,
                    @"type": u4,
                },
                x: i8,
                y: i8,
            };
        };

        pub const Update_Block_Entity = struct {
            location: Position,
            action: u8,
            NBT_data: ?NBT,

            const action_enum = enum(u8) {
                spawn_potentials = 1,
                command_block_text = 2,
                beacon = 3,
                mob_head = 4,
                flower_in_pot = 5,
                banner = 6,
            };
        };

        pub const Open_Sign_Editor = struct {
            location: Position,
        };

        pub const Statistics = struct {
            count: VarInt,
            statistic: []const Statistic,

            const Statistic = struct {
                name: String,
                value: VarInt,
            };
        };

        pub const Player_List_Item = struct {
            action: VarInt,
            number_of_players: VarInt,
            player: []const Player,

            const action_enum = enum(u8) {
                add_player = 0,
                update_gamemode = 1,
                update_latency = 2,
                update_display_name = 3,
                remove_player = 4,
            };
            
            const Player = struct {
                UUID: u64,
                action: union(action_enum) {
                    add_player: struct {
                        name: String,
                        number_of_properties: VarInt,
                        property: []const Property,
                        gamemode: VarInt,
                        ping: VarInt,
                        has_display_name: bool,
                        display_name: ?Chat,
                    },
                    update_gamemode: struct {
                        gamemode: VarInt,
                    },
                    update_latency: struct {
                        ping: VarInt,
                    },
                    update_display_name: struct {
                        has_display_name: bool,
                        display_name: ?Chat,
                    },
                    remove_player: struct {},
                },
            };

            const Property = struct {
                name: String,
                value: String,
                is_signed: bool,
                signature: ?String,
            };
        };

        pub const Player_Abilities = struct {
            flags: i8,
            flying_speed: f32,
            fov_modifier: f32,

            const flags_enum = enum(i8) {
                invulnerable = 0x01,
                flying = 0x02,
                allow_flying = 0x04,
                creative_mode = 0x08,
            };
        };

        pub const Tab_Complete = struct {
            count: VarInt,
            matches: []String,
        };

        pub const Scoreboard_Objective = struct {
            objective_name: String,
            mode: i8,
            objective_value: ?String,
            @"type": ?String,
        };

        pub const Update_Score = struct {
            score_name: String,
            action: i8,
            objective_name: String,
            value: ?VarInt,
        };

        pub const Display_Scoreboard = struct {
            position: i8,
            score_name: String,
        };

        pub const Teams = struct {
            team_name: String,
            mode: i8,
            team_display_name: ?String,
            team_prefix: ?String,
            team_suffix: ?String,
            friendly_fire: ?i8,
            name_tag_visibility: ?String,
            color: ?i8,
            player_count: ?VarInt,
            players: ?[]const String,
        };

        pub const Plugin_Message = struct {
            channel: String, // TODO see https://minecraft.wiki/w/Plugin_channels?oldid=2767993
            data: []const u8,
        };

        pub const Disconnect = struct {
            reason: Chat,
        };

        pub const Server_Difficulty = struct {
            difficulty: u8,
        };

        pub const Combat_Event = struct {
            event: VarInt,
            duration: ?VarInt,
            player_ID: ?VarInt,
            entity_ID: ?i32,
            message: String,
        };

        pub const Camera = struct {
            camera_ID: VarInt,
        };

        pub const World_Border = struct {
            action: VarInt,
            concrete: union(action_enum) {
                set_size: struct {
                    radius: f64,
                },
                lerp_size: struct {
                    old_radius: f64,
                    new_radius: f64,
                    speed: VarLong,
                },
                set_center: struct {
                    x: f64,
                    z: f64,
                },
                initialize: struct {
                    x: f64,
                    z: f64,
                    old_radius: f64,
                    new_radius: f64,
                    speed: VarLong,
                    portal_teleport_boundary: VarInt,
                    warning_time: VarInt,
                    warning_blocks: VarInt,
                },
                set_warning_time: struct {
                    warning_time: VarInt,
                },
                set_warning_blocks: struct {
                    warning_blocks: VarInt,
                },
            },

            const action_enum = enum(u8) {
                set_size = 0,
                lerp_size = 1,
                set_center = 2,
                initialize = 3,
                set_warning_time = 4,
                set_warning_blocks = 5,
            };
        };

        pub const Title = struct {
            action: VarInt,
            concrete: union(action_enum) {
                set_title: struct {
                    title_text: Chat,
                },
                set_subtitle: struct {
                    subtitle_text: Chat,
                },
                set_times_and_display: struct {
                    fade_in: i32,
                    stay: i32,
                    fade_out: i32,
                },
                hide: struct {},
                reset: struct {},
            },
    
            const action_enum = enum(u8) {
                set_title = 0,
                set_subtitle = 1,
                set_times_and_display = 2,
                hide = 3,
                reset = 4,
            };
        };

        pub const Set_Compression = struct {
            threshold: VarInt,
        };

        pub const Player_List_Header_And_Footer = struct {
            header: Chat,
            footer: Chat,
        };

        pub const Resource_Pack_Send = struct {
            URL: String,
            hash: String,
        };

        pub const Update_Entity_NBT = struct {
            entity_ID: VarInt,
            tag: NBT,
        };
    };

    pub const serverbound = struct {
        pub const Keep_Alive = struct {
            keep_alive_ID: VarInt,
        };

        pub const Chat_Message = struct {
            message: String,
        };

        pub const Use_Entity = struct {
            target: VarInt,
            @"type": VarInt,
            target_x: ?f32,
            target_y: ?f32,
            target_z: ?f32,
        };

        pub const Player = struct {
            on_ground: bool,
        };

        pub const Player_Position = struct {
            x: f64,
            feet_y: f64,
            z: f64,
            on_ground: bool,
        };

        pub const Player_Look = struct {
            yaw: f32,
            pitch: f32,
            on_ground: bool,
        };

        pub const Player_Position_And_Look = struct {
            x: f64,
            feet_y: f64,
            z: f64,
            yaw: f32,
            pitch: f32,
            on_ground: bool,
        };

        pub const Player_Digging = struct {
            status: i8,
            location: Position,
            face: i8,

            const status_enum = enum(i8) {
                started_digging = 0,
                cancelled_digging = 1,
                finished_digging = 2,
                drop_item_stack = 3,
                drop_item = 4,
                shoot_arrow_OR_finish_eating = 5,
            };

            const face_enum = enum(i8) {
                neg_y = 0,
                pos_y = 1,
                neg_z = 2,
                pos_z = 3,
                neg_x = 4,
                pos_x = 5,
            };
        };

        pub const Player_Block_Placement = struct {
            location: Position,
            face: i8,
            held_item: Slot,
            cursor_position_x: i8,
            cursor_position_y: u8,
            cursor_position_z: i8,
        };

        pub const Held_Item_Change = struct {
            slot: i16,
        };

        pub const Animation = struct {};

        pub const Entity_Action = struct {
            entity_ID: VarInt,
            action_ID: VarInt,
            action_parameter: VarInt,
        
            const action_ID_enum = enum(u8) {
                start_sneaking = 0,
                stop_sneaking = 1,
                leave_bed = 2,
                start_sprinting = 3,
                stop_sprinting = 4,
                jump_with_horse = 5,
                open_ridden_horse_inventory = 6,
            };
        };

        pub const Steer_Vehicle = struct {
            sideways: f32,
            forward: f32,
            flags: u8,
        };

        pub const Close_Window = struct {
            window_ID: u8,
        };

        pub const Click_Window = struct {
            window_ID: u8,
            slot: i16,
            button: i8,
            action_number: i16,
            mode: i8,
            clicked_item: Slot,

            // TODO see https://minecraft.wiki/w/Protocol?oldid=2772100#Click_Window
        };

        pub const Confirm_Transaction = struct {
            window_ID: i8,
            action_number: i16,
            accepted: bool,
        };

        pub const Creative_Inventory_Action = struct {
            slot: i16,
            clicked_item: Slot,
        };

        pub const Enchant_Item = struct {
            window_ID: i8,
            enchantment: i8,
        };

        pub const Update_Sign = struct {
            location: Position,
            line_1: Chat,
            line_2: Chat,
            line_3: Chat,
            line_4: Chat,
        };

        pub const Player_Abilities = struct {
            flags: i8,
            flying_speed: f32,
            walking_speed: f32,

            const flags_enum = enum(i8) {
                is_creative = 0x01,
                is_flying = 0x02,
                can_fly = 0x04,
                god_mode = 0x08,
            };
        };

        pub const Tab_Complete = struct {
            text: String,
            has_position: bool,
            looked_at_block: ?Position,
        };

        pub const Client_Settings = struct {
            locale: String,
            view_distance: i8,
            chat_mode: i8,
            chat_colors: bool,
            displayed_skin_parts: u8,

            const displayed_skin_parts_enum = enum(u8) {
                cape = 0x01,
                jacket =0x02,
                left_sleeve = 0x04,
                right_sleeve = 0x08,
                left_pants = 0x10,
                right_pants = 0x20,
                hat = 0x40,
            };
        };

        pub const Client_Status = struct {
            action_ID: VarInt,
        
            const action_ID_enum = enum(u8) {
                respawn = 0,
                stats = 1,
                archievement = 2,
            };
        };

        pub const Plugin_Message = struct {
            channel: String,
            data: []const u8, // TODO see https://minecraft.wiki/w/Plugin_channels?oldid=2767993
        };

        pub const Spectate = struct {
            target_player: u64,
        };

        pub const Resource_Pack_Status = struct {
            hash: String,
            result: VarInt,

            const result_enum = enum(u8) {
                successsful = 0,
                declined = 1,
                failed = 2,
                accepted = 3,
            };
        };
    };
};
