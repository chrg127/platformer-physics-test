local fmt = require "fmt"

local vec = {}

vec.unit = rl.new("Vector2", 1, 1)
vec.zero = rl.new("Vector2", 0, 0)

function vec.v2(x, y) return rl.new("Vector2", x, y) end
function vec.normalize(v) return rl.Vector2Normalize(v) end
function vec.length(v) return rl.Vector2Length(v) end
function vec.rotate(v, angle) return rl.Vector2Rotate(v, angle) end

function vec.floor(v) return vec.v2(math.floor(v.x), math.floor(v.y)) end
function vec.eq(a, b) return rl.Vector2Equals(a, b) == 1 end

local rec = {}

function rec.new(x, y, w, h) return rl.new("Rectangle", x, y, w, h) end
function rec.newV(pos, size) return rl.new("Rectangle", pos.x, pos.y, size.x, size.y) end

function table_find(t, x, comp)
    for _, v in pairs(t) do
        if comp ~= nil and comp(x, v) or x == v  then
            return v
        end
    end
    return false
end

-- our game uses 16x16 tiles
local TILE_SIZE = 16
-- a screen will always be 20x16 tiles
-- smw is 16x14, so this viewport is slightly larger
local SCREEN_WIDTH = 25
local SCREEN_HEIGHT = 20
-- scale window up to this number
local SCALE = 2

rl.SetConfigFlags(rl.FLAG_VSYNC_HINT)
rl.InitWindow(SCREEN_WIDTH * TILE_SIZE * SCALE, SCREEN_HEIGHT * TILE_SIZE * SCALE, "witch game")
rl.SetTargetFPS(60)

local buffer = rl.LoadRenderTexture(SCREEN_WIDTH * TILE_SIZE, SCREEN_HEIGHT * TILE_SIZE)

local camera = rl.new("Camera2D", vec.v2(SCREEN_WIDTH * TILE_SIZE / 2, SCREEN_HEIGHT * TILE_SIZE / 2), vec.v2(0, 0), 0, 1)

local tilemap = {
    { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    { 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    { 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    { 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1, 0, 1, 0 },
    { 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 1, 1, 0, 1, 0, 1, 0, 1 },
    { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0 },
    { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
}

function p2t(p)
    return vec.floor(p / TILE_SIZE) + vec.v2(1, 1)
end

local player = {
    pos = vec.v2(SCREEN_WIDTH * TILE_SIZE / 2, SCREEN_HEIGHT * TILE_SIZE / 2),
    draw_size = vec.v2(TILE_SIZE, TILE_SIZE * 2),
    hitbox = vec.v2(TILE_SIZE, TILE_SIZE * 2),
    vel = vec.v2(0, 0),
    on_ground = false,
}

while not rl.WindowShouldClose() do
    local dt = rl.GetFrameTime()

    -- print("new frame")

    -- physics

    local accel = vec.v2(
        (rl.IsKeyDown(rl.KEY_LEFT)  and -800 or 0)
      + (rl.IsKeyDown(rl.KEY_RIGHT) and  800 or 0),
        ((rl.IsKeyPressed(rl.KEY_Z) and player.on_ground) and -15000 or 0)
    )

    local decel = player.vel.x > 0 and -500
                or player.vel.x < 0 and  500
                or 0

    local gravity = vec.v2(0, 400)

    player.vel = player.vel + (accel + vec.v2(decel, 0) + gravity) * dt
    if player.vel.x > 500 then
        player.vel.x = 500
    elseif player.vel.x < -500 then
        player.vel.x = -500
    end
    if math.abs(player.vel.x) < 10 then
        player.vel.x = 0
    end

    local old_pos = player.pos
    player.pos = player.pos + player.vel * dt

	rl.BeginDrawing()

    rl.BeginTextureMode(buffer)
	rl.ClearBackground(rl.BLACK)

    rl.DrawText("pos   = " .. tostring(player.pos),   5, 15, 10, rl.WHITE)
    rl.DrawText("vel   = " .. tostring(player.vel),   5, 25, 10, rl.WHITE)
    rl.DrawText("accel = " .. tostring(accel),        5, 35, 10, rl.WHITE)
    rl.DrawText("accel = " .. tostring(decel),        5, 45, 10, rl.WHITE)

    -- collision with ground
    local points = {
        player.pos                                          , player.pos + vec.v2(1, 0) * TILE_SIZE ,
        player.pos + vec.v2(0, 1) * TILE_SIZE , player.pos + vec.v2(1, 1) * TILE_SIZE ,
        player.pos + vec.v2(0, 2) * TILE_SIZE , player.pos + vec.v2(1, 2) * TILE_SIZE ,
    }
    local collided_tiles = {}
    for _, p in ipairs(points) do
        local t = p2t(p)
        if not table_find(collided_tiles, t) and tilemap[t.y] ~= nil
        and tilemap[t.y][t.x] ~= nil and tilemap[t.y][t.x] ~= 0 then
            table.insert(collided_tiles, t)
        end
    end

    player.on_ground = false
    if #collided_tiles > 0 then
        table.sort(collided_tiles, function (a, b) return a.y < b.y end)
        rl.DrawText("on ground, tile y = " .. tostring(collided_tiles[1].y * TILE_SIZE),        5, 55, 10, rl.WHITE)
        player.vel.y = 0
        player.pos.y = (collided_tiles[1].y - 1) * TILE_SIZE - player.hitbox.y
        player.on_ground = true
    end

    camera.target = player.pos

    rl.BeginMode2D(camera)

    for y = 1, SCREEN_HEIGHT do
        for x = 1, SCREEN_WIDTH do
            if tilemap[y][x] ~= 0 then
                if table_find(collided_tiles, vec.v2(x, y), vec.eq) then
                    rl.DrawRectangleV(vec.v2(x-1, y-1) * TILE_SIZE, vec.v2(TILE_SIZE, TILE_SIZE), rl.RED)
                else
                    rl.DrawRectangleV(vec.v2(x-1, y-1) * TILE_SIZE, vec.v2(TILE_SIZE, TILE_SIZE), rl.WHITE)
                end
            end
        end
    end

    rl.DrawRectangleLinesEx(rec.newV(player.pos, player.draw_size), 1.0, rl.RED)

    rl.EndMode2D()
    rl.EndTextureMode()

    rl.DrawTexturePro(
        buffer.texture,
        rec.new(0, 0, SCREEN_WIDTH * TILE_SIZE        , -SCREEN_HEIGHT * TILE_SIZE        ),
        rec.new(0, 0, SCREEN_WIDTH * TILE_SIZE * SCALE,  SCREEN_HEIGHT * TILE_SIZE * SCALE),
        vec.v2(0, 0), 0,
        rl.WHITE
    )

    rl.DrawFPS(10, 10)
	rl.EndDrawing()
end

