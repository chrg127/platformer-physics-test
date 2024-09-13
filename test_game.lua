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

function vec.x(v) return v.x end
function vec.y(v) return v.y end
function vec.dim(v, d) return d == 1 and v.x or v.y end

function vec.set_dim(v, d, x)
    return vec.v2(d == 0 and x or v.x, d == 1 and x or v.y)
end

local rec = {}

function rec.new(x, y, w, h) return rl.new("Rectangle", x, y, w, h) end
function rec.newV(pos, size) return rl.new("Rectangle", pos.x, pos.y, size.x, size.y) end

-- general utilities starting here
function lt(a, b) return a < b end
function gt(a, b) return a > b end
function sign(x) return x < 0 and -1 or x > 0 and 1 or 0 end

function findf(t, x, comp)
    for _, v in pairs(t) do
        if comp ~= nil and comp(x, v) or x == v  then
            return v
        end
    end
    return false
end

function map(fn, t)
    local r = {}
    for k, v in pairs(t) do
        table.insert(r, fn(k, v))
    end
    return r
end

function filter(pred, t)
    local r = {}
    for k, v in pairs(t) do
        if pred(k, v) then
            table.insert(r, v)
        end
    end
    return r
end

function foldl(fn, init, t)
    local r = init
    for k, v in pairs(t) do
        r = fn(k, v, r)
    end
    return r
end

function minf(fn, t)
    return foldl(function (k, v, r) return math.min(fn(v), r) end, math.huge, t)
end

function maxf(fn, t)
    return foldl(function (k, v, r) return math.max(fn(v), r) end, -math.huge, t)
end

function identity(x) return x end

function rlerp(a, b, v)
    return (v - a) / (b - a)
end

function lerp(a, b, t)
    return a + t*(b - a)
end

function aabb_point_inside(aabb, p)
    return rl.CheckCollisionPointRec(p, rec.newV(aabb[1], aabb[2] - aabb[1]))
end

function clamp(x, min, max)
    return math.min(math.max(x, min), max)
end

-- our game uses 16x16 tiles
local TILE_SIZE = 16
-- a screen will always be 20x16 tiles
-- smw is 16x14, so this viewport is slightly larger
local SCREEN_WIDTH = 25
local SCREEN_HEIGHT = 20
-- scale window up to this number
local SCALE = 2
-- set this to true for free movement instead of being bound by gravity
local FREE_MOVEMENT = false

rl.SetConfigFlags(rl.FLAG_VSYNC_HINT)
rl.InitWindow(SCREEN_WIDTH * TILE_SIZE * SCALE, SCREEN_HEIGHT * TILE_SIZE * SCALE, "witch game")
rl.SetTargetFPS(60)

local buffer = rl.LoadRenderTexture(SCREEN_WIDTH * TILE_SIZE, SCREEN_HEIGHT * TILE_SIZE)

local camera = rl.new("Camera2D", vec.v2(SCREEN_WIDTH * TILE_SIZE / 2, SCREEN_HEIGHT * TILE_SIZE / 2), vec.v2(0, 0), 0, 1)

local tilemap = {
    { 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    { 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    { 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    { 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    { 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    { 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    { 0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    { 0, 0, 0, 0, 0, 1, 0, 0, 0, 2, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1, 0, 1, 0, 1, 0 },
    { 1, 1, 1, 1, 1, 1, 0, 0, 0, 1, 1, 1, 0, 0, 0, 0, 1, 1, 1, 0, 1, 0, 1, 0, 1 },
    { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0 },
    { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
}

function is_air(t)
    return tilemap[t.y] == nil or tilemap[t.y][t.x] == nil or tilemap[t.y][t.x] == 0
end

function p2t(p)
    return vec.floor(p / TILE_SIZE) + vec.v2(1, 1)
end

function t2p(t)
    return (t - vec.v2(1, 1)) * TILE_SIZE
end

local player = {
    pos = vec.v2(SCREEN_WIDTH * TILE_SIZE / 2, SCREEN_HEIGHT * TILE_SIZE / 2) - vec.v2(8, 0),
    draw_size = vec.v2(TILE_SIZE, TILE_SIZE * 2),
    hitbox = { vec.v2(0, 0), vec.v2(TILE_SIZE-0, TILE_SIZE*2) },
    vel = vec.v2(0, 0),
    on_ground = false,
    old_on_ground = false,
    coyote_time = 0,
    jump_buf = false,
    collision_points = {
        {
            { vec.v2(  0,  8), vec.v2(  0, 16), vec.v2(  0, 24), }, --left
            { vec.v2(  0,-24), vec.v2(  0,-16), vec.v2(  0, -8), }  -- right 
        }, {
            { vec.v2(  4,  0), vec.v2( 12,  0), }, -- top
            { vec.v2(-12,  0), vec.v2( -4,  0), }  -- bottom
        }
    },
}

local logfile = io.open("log.txt", "w")

while not rl.WindowShouldClose() do
    local dt = rl.GetFrameTime()

    local cur_line = 5
    local lines_to_print = {}
    function tprint(s)
        table.insert(lines_to_print, { s, cur_line })
        cur_line = cur_line + 10
        logfile:write(s .. "\n")
    end

    tprint(tostring(rl.GetFPS()) .. " FPS")

    -- physics
    local ACCEL = 700
    local DECEL = 300
    local VEL_CAP = 14 * TILE_SIZE
    local GRAVITY = 400
    local SLOW_GRAVITY = 300 -- used when pressing the jump button while falling
    local JUMP_HEIGHT_MAX = 4.5 -- tiles
    local JUMP_HEIGHT_MIN = 0.2 -- tiles
    local COYOTE_TIME_FRAMES = 10

    local JUMP_VEL     = -math.sqrt(2 * GRAVITY * (JUMP_HEIGHT_MAX * TILE_SIZE))
    local JUMP_VEL_MIN = -math.sqrt(2 * GRAVITY * (JUMP_HEIGHT_MIN * TILE_SIZE))

    local accel_hor = (rl.IsKeyDown(rl.KEY_LEFT)  and -ACCEL or 0)
                    + (rl.IsKeyDown(rl.KEY_RIGHT) and  ACCEL or 0)
    local decel_hor = player.vel.x > 0 and -DECEL
                   or player.vel.x < 0 and  DECEL
                   or 0
    local gravity = rl.IsKeyDown(rl.KEY_Z) and not player.on_ground and player.vel.y > 0
                and SLOW_GRAVITY or GRAVITY
    local accel = vec.v2(accel_hor + decel_hor, gravity)

    local old_vel = player.vel
    player.vel = player.vel + accel * dt
    player.vel.x = clamp(player.vel.x, -VEL_CAP, VEL_CAP)
    if math.abs(player.vel.x) < 4 then
        player.vel.x = 0
    end

    if  (rl.IsKeyPressed(rl.KEY_Z) or player.jump_buf)
    and (player.on_ground or player.coyote_time > 0) then
        player.vel.y = JUMP_VEL
        player.jump_buf = false
    end
    player.coyote_time = (player.old_on_ground and not player.on_ground and player.vel.y > 0) and COYOTE_TIME_FRAMES
                      or (player.on_ground) and 0
                      or math.max(0, player.coyote_time - 1)

    if not rl.IsKeyDown(rl.KEY_Z) and not player.on_ground
       and player.vel.y < JUMP_VEL_MIN then
        player.vel.y = JUMP_VEL_MIN
    end

    local old_pos = player.pos
    if not FREE_MOVEMENT then
        player.pos = player.pos + player.vel * dt
    else
        player.pos = player.pos + vec.v2(
            rl.IsKeyDown(rl.KEY_LEFT) and -1 or rl.IsKeyDown(rl.KEY_RIGHT) and 1 or 0,
            rl.IsKeyDown(rl.KEY_UP)   and -1 or rl.IsKeyDown(rl.KEY_DOWN)  and 1 or 0
        ) * 4
    end

    tprint("oldpos = " .. tostring(old_pos))
    tprint("pos    = " .. tostring(player.pos))
    tprint("vel    = " .. tostring(player.vel))
    tprint("accel  = " .. tostring(accel))
    tprint("coyote = " .. tostring(player.coyote_time))

    -- collision with ground
    player.old_on_ground = player.on_ground
    player.on_ground = false
    local callbacks = {
        function () tprint("pushing left") end,
        function () tprint("pushing right") end,
        function () tprint("pushing up") end,
        function ()
            tprint("pushing down")
            player.on_ground = true
        end
    }

    local hitbox = map(function (_, v) return v + player.pos end, player.hitbox)
    tprint(fmt.tostring("hitbox =", hitbox))

    function get_tiles(points)
        local ts = {}
        for _, p in ipairs(points) do
            local t = p2t(p)
            if not is_air(t) then
                local p = t2p(t)
                table.insert(ts, p)
                table.insert(ts, p + vec.v2(TILE_SIZE, TILE_SIZE))
            end
        end
        return ts
    end

    function get_points(hitbox, from)
        return map(function (_, axis)
            return {
                map(function (_, lefts)  return hitbox[1] + lefts  end, axis[1]),
                map(function (_, rights) return hitbox[2] + rights end, axis[2])
            }
        end, from)
    end

    local points = get_points(hitbox, player.collision_points)

    for axis = 0, 1 do
        local fns = { vec.x, vec.y }
        local dim = fns[axis+1]
        for move = 0, 1 do
            local tiles = get_tiles(points[axis+1][move+1])
            local ops = {maxf, minf}
            local tile = ops[move+1](dim, tiles)
            if math.abs(tile) ~= math.huge then
                player.vel = vec.set_dim(player.vel, axis, 0)
                local diff = { 0, dim(hitbox[1]) - dim(hitbox[2]) }
                player.pos = vec.set_dim(player.pos, axis, tile + diff[move+1] - dim(player.hitbox[1]))
                callbacks[axis * 2 + move + 1]()
            end
        end
    end

    tprint("pos (adjusted) = " .. tostring(player.pos))

    -- do jump buffering here since we've got points calculated...
    -- and #filter(function (_, v) return not is_air(v) end,
    --          map(function (_, v) return p2t(v + vec.v2(0, 10)) end,
    --              points[2][2])) > 0 then
    if rl.IsKeyPressed(rl.KEY_Z) and not player.on_ground and player.vel.y > 0 then
        for _, p in ipairs(points[2][2]) do
            if not is_air(p2t(p + vec.v2(0, 12))) then
                player.jump_buf = true
            end
        end
    end

    tprint("jump buf = " .. tostring(player.jump_buf))

    camera.target = player.pos

    rl.BeginDrawing()
    rl.BeginTextureMode(buffer)
    rl.ClearBackground(rl.BLACK)

    rl.BeginMode2D(camera)

    for y = 1, SCREEN_HEIGHT do
        for x = 1, SCREEN_WIDTH do
            local tile = tilemap[y][x]
            if tile ~= 0 then
                local color = tile == 2 and rl.RED or rl.WHITE
                rl.DrawRectangleV(vec.v2(x-1, y-1) * TILE_SIZE, vec.v2(TILE_SIZE, TILE_SIZE), color)
            end
        end
    end

    if points ~= nil then
        for _, ps1 in ipairs(points) do
            for _, ps2 in ipairs(ps1) do
                for _, p in ipairs(ps2) do
                    rl.DrawPixelV(p, rl.GREEN)
                end
            end
        end
    end

    rl.DrawRectangleLinesEx(rec.newV(player.pos, player.draw_size), 1.0, rl.RED)

    rl.EndMode2D()

    for _, line in ipairs(lines_to_print) do
        rl.DrawText(line[1], 5, line[2], 10, rl.GREEN)
    end

    rl.EndTextureMode()

    rl.DrawTexturePro(
        buffer.texture,
        rec.new(0, 0, SCREEN_WIDTH * TILE_SIZE        , -SCREEN_HEIGHT * TILE_SIZE        ),
        rec.new(0, 0, SCREEN_WIDTH * TILE_SIZE * SCALE,  SCREEN_HEIGHT * TILE_SIZE * SCALE),
        vec.v2(0, 0), 0,
        rl.WHITE
    )

	rl.EndDrawing()
end

