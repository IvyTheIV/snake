const builtin = @import("builtin");

const std = @import("std");
const rl = @import("raylib");
const Rng = std.rand.DefaultPrng;

const fps = 60;
const updates_per_sec = 6;

const screen_width = 600;
const screen_height = 600;
const num_tiles = 24;
const tiles_sq = num_tiles * num_tiles;
const min_length = @min(screen_width, screen_height);
const tile_size: comptime_int = @intFromFloat(@round(@as(
    comptime_float,
    min_length / num_tiles,
)));

const NextState = union(enum) {
    Play,
    GameOver: usize,
    Exit,
};

pub fn main() !void {
    rl.initWindow(screen_width, screen_height, "snake");
    defer rl.closeWindow();

    rl.setTargetFPS(fps);

    var buffer: [tiles_sq * @sizeOf(u1) + tiles_sq * @sizeOf(?[2]u16)]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const allocator = fba.allocator();

    const snake_body = try allocator.alloc(?[2]u16, num_tiles * num_tiles);
    defer allocator.free(snake_body);

    const grid_data = try allocator.alloc(u1, num_tiles * num_tiles);
    defer allocator.free(grid_data);

    var seed: u64 = undefined;
    try std.os.getrandom(std.mem.asBytes(&seed));
    var rand = Rng.init(seed);

    var next_state: NextState = .Play;
    while (true) {
        switch (next_state) {
            .Play => next_state = game_loop(grid_data, snake_body, &rand),
            .GameOver => |score| next_state = game_over(score),
            .Exit => return,
        }
    }
}

pub fn game_loop(grid_data: []u1, snake_body: []?[2]u16, rand: *Rng) NextState {
    var grid = GridUnmanaged().init(.{ num_tiles, num_tiles }, grid_data);
    var snake = SnakeUnmanaged(u16).init(.{ num_tiles / 2, num_tiles / 2 }, snake_body);

    var snake_direction = [_]i2{ 0, 0 };
    var prev_snake_direction = [_]i2{ 0, 0 };
    var fruit_coordinates = spawnFruit(u16, &grid, rand);

    var inc: u8 = 0;
    var score: usize = 0;

    while (true) : (inc = (inc + 1) % fps) {
        if (rl.windowShouldClose()) {
            return .Exit;
        }
        score = snake.len - 1;

        const key_pressed = rl.getKeyPressed();
        switch (key_pressed) {
            .key_w, .key_k, .key_up => snake_direction = .{ 0, -1 },
            .key_a, .key_h, .key_left => snake_direction = .{ -1, 0 },
            .key_s, .key_j, .key_down => snake_direction = .{ 0, 1 },
            .key_d, .key_l, .key_right => snake_direction = .{ 1, 0 },
            .key_q => return .Exit,
            .key_r => return .Play,
            .key_g => return .{ .GameOver = score },
            else => {},
        }

        if (inc % (60 / updates_per_sec) == 0) {
            if (snake_direction[0] +% prev_snake_direction[0] == 0 and snake_direction[1] +% prev_snake_direction[1] == 0) {
                snake_direction = prev_snake_direction;
            }
            prev_snake_direction = snake_direction;

            const current_position = snake.at(0).?;
            var new_position = [_]u16{
                @intCast(@mod(@as(i32, current_position[0]) + snake_direction[0], num_tiles)),
                @intCast(@mod(@as(i32, current_position[1]) + snake_direction[1], num_tiles)),
            };

            grid.set(u16, snake.at(snake.len - 1).?, 0);
            snake.push(new_position);

            if (grid.at(u16, new_position) == 1) {
                return .{ .GameOver = score };
            } else if (std.meta.eql(current_position, fruit_coordinates)) {
                fruit_coordinates = spawnFruit(u16, &grid, rand);
                if (snake.len == grid.data.len) {
                    return .{ .GameOver = score + 1 };
                }
            } else {
                snake.pop();
            }
            grid.set(u16, new_position, 1);
        }

        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.black);

        rl.drawRectangle(
            @intCast(fruit_coordinates[0] * tile_size),
            @intCast(fruit_coordinates[1] * tile_size),
            tile_size,
            tile_size,
            rl.Color.red,
        );
        for (0..snake.len) |i| {
            const coordinates = snake.at(i).?;
            rl.drawRectangle(
                coordinates[0] * tile_size,
                coordinates[1] * tile_size,
                tile_size,
                tile_size,
                rl.Color.fromHSV(0, 0, 0.5 - 0.25 * @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(snake.len))),
            );
        }

        const coordinates = snake.at(0).?;
        var buf: [6]u8 = undefined;
        const fmt_text: []u8 = std.fmt.bufPrint(&buf, "{d: >5}", .{score}) catch unreachable;
        buf[fmt_text.len] = 0;
        const text = buf[0..fmt_text.len :0];
        const text_size = 12;

        rl.drawText(
            text,
            coordinates[0] * tile_size + tile_size / 2 - text_size,
            coordinates[1] * tile_size + tile_size - text_size,
            text_size,
            rl.Color.black,
        );
    }
}

pub fn game_over(score: usize) NextState {
    while (true) {
        if (rl.windowShouldClose()) {
            return .Exit;
        }
        const key_pressed = rl.getKeyPressed();
        switch (key_pressed) {
            .key_r => return .Play,
            .key_q => return .Exit,
            else => {},
        }

        rl.beginDrawing();
        defer rl.endDrawing();

        const text_size = 48;
        rl.clearBackground(rl.Color.black);
        rl.drawText(
            "game over",
            screen_width / 2 - (text_size / 4) * 10,
            screen_height / 4,
            text_size,
            rl.Color.gray,
        );
        rl.drawText(
            rl.textFormat("score: %d", .{score}),
            screen_width / 2 - (text_size / 4) * 10,
            screen_height / 4 + text_size,
            text_size / 2,
            rl.Color.gray,
        );

        rl.drawText(
            "try again?",
            screen_width / 2 - (text_size / 4) * 7,
            screen_height - screen_height / 3,
            text_size / 2,
            rl.Color.gray,
        );

        rl.drawText(
            "no      yes",
            screen_width / 2 - (text_size / 4) * 7,
            screen_height - screen_height / 3 + text_size,
            text_size / 2,
            rl.Color.gray,
        );

        rl.drawText(
            "    :q         :r",
            screen_width / 2 - (text_size / 4) * 7,
            screen_height - screen_height / 3 + text_size,
            text_size / 2,
            rl.Color.yellow,
        );
    }
}

pub fn spawnFruit(comptime T: type, grid: *GridUnmanaged(), rand: *Rng) [2]T {
    var coordinates = .{
        rand.random().uintLessThan(T, num_tiles),
        rand.random().uintLessThan(T, num_tiles),
    };
    while (grid.at(T, coordinates) != 0) {
        coordinates = .{
            rand.random().uintLessThan(T, num_tiles),
            rand.random().uintLessThan(T, num_tiles),
        };
    }
    return coordinates;
}

pub fn GridUnmanaged() type {
    return struct {
        const Self = @This();

        data: []u1,
        rows: usize,
        cols: usize,

        pub fn init(dimensions: [2]usize, slice: []u1) Self {
            for (slice) |*item| {
                item.* = 0;
            }

            return Self{
                .data = slice,
                .rows = dimensions[0],
                .cols = dimensions[1],
            };
        }

        pub fn at(self: Self, comptime N: type, coordinates: [2]N) u1 {
            return self.data[coordinates[1] + coordinates[0] * self.cols];
        }

        pub fn set(self: *Self, comptime N: type, coordinates: [2]N, item: u1) void {
            self.data[coordinates[1] + coordinates[0] * self.cols] = item;
        }
    };
}

pub fn SnakeUnmanaged(comptime T: type) type {
    return struct {
        const Self = @This();
        var capacity: usize = 0;

        len: usize,
        head: usize,
        tail: usize,
        body: []?[2]T,

        pub fn init(head_position: [2]T, slice: []?[2]T) Self {
            capacity = slice.len;

            if (builtin.mode == std.builtin.OptimizeMode.Debug) {
                for (slice) |*item| {
                    item.* = null;
                }
            }
            slice[slice.len - 1] = head_position;

            return Self{
                .len = 1,
                .head = slice.len - 1,
                .tail = slice.len - 1,
                .body = slice,
            };
        }

        pub fn push(self: *Self, item: [2]T) void {
            std.debug.assert(self.len < capacity);
            std.debug.assert(self.len > 0);

            self.head = (capacity + self.head - 1) % capacity;
            self.body[self.head] = item;
            self.len += 1;
        }

        pub fn pop(self: *Self) void {
            std.debug.assert(self.len > 1);

            // const return_value = self.body[self.tail].?;

            self.body[self.tail] = null;
            self.tail = (capacity + self.tail - 1) % capacity;
            self.len -= 1;
        }

        pub fn at(self: *const Self, idx: usize) ?[2]T {
            return self.body[(idx + self.head) % capacity];
        }
    };
}

test "snake_structure" {
    var allocator = std.testing.allocator;
    var snake_body = try allocator.alloc(?[2]usize, 4);
    defer allocator.free(snake_body);

    var snake = SnakeUnmanaged(usize).init(.{ 3, 2 }, snake_body);
    for (0..3) |i| {
        snake.push(.{ 3, i + 3 });
    }

    for (0..2) |_| {
        snake.pop();
    }

    for (0..15) |i| {
        snake.push(.{ 3, i + 4 });
        snake.pop();
    }

    snake.push(.{ 3, 40 });
    snake.push(.{ 3, 40 });
}
