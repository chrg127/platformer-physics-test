local ffi = require "ffi"
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

function rec.new(pos, size) return rl.new("Rectangle", pos.x, pos.y, size.x, size.y) end

-- general utilities starting here
-- (not all of these are used, but they're nice to have)
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

function flatten(t)
    local r = {}
    function loop(t)
        for _, v in ipairs(t) do
            if type(v) == 'table' then
                loop(v)
            else
                table.insert(r, v)
            end
        end
    end
    loop(t)
    return r
end

function rlerp(a, b, v)
    return (v - a) / (b - a)
end

function lerp(a, b, t)
    return a + t*(b - a)
end

function aabb_point_inside(aabb, p)
    return rl.CheckCollisionPointRec(p, rec.new(aabb[1], aabb[2] - aabb[1]))
end

function clamp(x, min, max)
    return math.min(math.max(x, min), max)
end

-- our game uses 16x16 tiles
local TILE_SIZE = 16
-- a screen will always be 25x20 tiles
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

function get_normal(a, b)
    -- assumes a and b are in counter-clockwise order
    return vec.normalize(vec.rotate(a - b, -math.pi/2))
end

-- store info about a tile here, such as color, shape, normals, etc.
-- (there are other ways to structure this data, such as struct-of-arrays, but
-- this way the quickest to code)
local tile_info = {
    [1]  = { color = rl.WHITE, },
    [2]  = { color = rl.RED, },
    [3]  = { color = rl.WHITE, slope = { part = 'top',  points = { vec.v2(1, 1), vec.v2(0, 0), vec.v2(0, 1) } } },
    [4]  = { color = rl.WHITE, slope = { part = 'top',  points = { vec.v2(1, 0), vec.v2(0, 1), vec.v2(1, 1) } } },
    [5]  = { color = rl.WHITE, slope = { part = 'top',  points = { vec.v2(0, 0), vec.v2(1, 1), vec.v2(1, 0) } } },
    [6]  = { color = rl.WHITE, slope = { part = 'top',  points = { vec.v2(0, 1), vec.v2(1, 0), vec.v2(0, 0) } } },
    [7]  = { color = rl.WHITE, slope = { part = 'top',  points = { vec.v2(1, 0), vec.v2(0, 2), vec.v2(1, 2) } } },
    [8]  = { color = rl.WHITE, slope = { part = 'part', points = { vec.v2(1, 0), vec.v2(0, 2), vec.v2(1, 2) } } },
    [9]  = { color = rl.WHITE, slope = { part = 'top',  points = { vec.v2(1, 2), vec.v2(0, 0), vec.v2(0, 2) } } },
    [10] = { color = rl.WHITE, slope = { part = 'part', points = { vec.v2(1, 2), vec.v2(0, 0), vec.v2(0, 2) } } },
    [11] = { color = rl.WHITE, slope = { part = 'top',  points = { vec.v2(0, 2), vec.v2(1, 0), vec.v2(0, 0) } } },
    [12] = { color = rl.WHITE, slope = { part = 'part', points = { vec.v2(0, 2), vec.v2(1, 0), vec.v2(0, 0) } } },
    [13] = { color = rl.WHITE, slope = { part = 'top',  points = { vec.v2(0, 0), vec.v2(1, 2), vec.v2(1, 0) } } },
    [14] = { color = rl.WHITE, slope = { part = 'part', points = { vec.v2(0, 0), vec.v2(1, 2), vec.v2(1, 0) } } },
}

local tilemap = {
    {  1,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0 },
    {  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0 },
    {  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0 },
    {  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0 },
    {  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0 },
    {  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0 },
    {  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0 },
    {  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0 },
    {  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0 },
    {  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0 },
    {  0,  0,  0,  0,  0,  1,  1,  1,  1,  2,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0 },
    {  0,  0,  0,  7,  9,  0,  0,  0,  0,  1,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0 },
    {  0,  0,  0,  8, 10,  0,  0,  0,  0,  2,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0 },
    {  0,  0,  0, 13, 11,  0,  0,  0,  0,  1,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0 },
    {  0,  0,  0, 14, 12,  1,  1,  1,  1,  2,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0 },
    {  0,  0,  0,  4,  3,  1,  0,  0,  0,  1,  0,  0,  1,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0 },
    {  0,  0,  0,  5,  6,  1,  0,  0,  0,  2,  0,  0,  1,  0,  0,  0,  0,  0,  0,  1,  0,  1,  0,  1,  0 },
    {  1,  1,  1,  1,  1,  1,  0,  0,  0,  1,  1,  1,  0,  0,  0,  4,  1,  1,  1,  0,  1,  0,  1,  0,  1 },
    {  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  1,  1,  1,  1,  1,  0,  0,  0,  0,  0,  0,  0,  0 },
    {  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0 },
}

function is_air(t)
    return tilemap[t.y] == nil or tilemap[t.y][t.x] == nil or tilemap[t.y][t.x] == 0
end

function is_slope(ti)
    return ti >= 3
end

function p2t(p)
    return vec.floor(p / TILE_SIZE) + vec.v2(1, 1)
end

function t2p(t)
    return (t - vec.v2(1, 1)) * TILE_SIZE
end

local player = {
    pos           = vec.v2(SCREEN_WIDTH, SCREEN_HEIGHT) * TILE_SIZE / 2
                  - vec.v2(TILE_SIZE/2, 0),
    vel           = vec.zero,
    on_ground     = false,
    coyote_time   = 0,
    jump_buf      = false,
}

local PLAYER_DRAW_SIZE = vec.v2(TILE_SIZE, TILE_SIZE * 2)
local PLAYER_HITBOX = { vec.v2(0, 0), vec.v2(TILE_SIZE-0, TILE_SIZE*2) }

local PLAYER_COLLISION_POINTS = {
    {
        { vec.v2( -1,  4), vec.v2( -1, 16), vec.v2( -1, 28), }, -- left
        { vec.v2(  0,-28), vec.v2(  0,-16), vec.v2(  0, -4), }  -- right
    }, {
        { vec.v2(  0,  0), vec.v2( 15,  0), }, -- top
        { vec.v2(-16,  0), vec.v2( -1,  0), }  -- bottom
    }
}

-- physics constant for the player, change these to control the "feel" of the game
local ACCEL = 700
local DECEL = 300
local VEL_CAP = 14 * TILE_SIZE
local GRAVITY = 400
-- used when pressing the jump button while falling
local SLOW_GRAVITY = 300
local JUMP_HEIGHT_MAX = 4.5 -- tiles
local JUMP_HEIGHT_MIN = 0.2 -- tiles
local COYOTE_TIME_FRAMES = 10
-- how many pixels over the ground should a jump be registered?
local JUMP_BUF_WINDOW = 16

local JUMP_VEL     = -math.sqrt(2 * GRAVITY * (JUMP_HEIGHT_MAX * TILE_SIZE))
local JUMP_VEL_MIN = -math.sqrt(2 * GRAVITY * (JUMP_HEIGHT_MIN * TILE_SIZE))

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

    -- player physics
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

    -- collision with ground
    local old_on_ground = player.on_ground
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

    local hitbox = map(function (_, v) return v + player.pos end, PLAYER_HITBOX)
    tprint("hitbox = {" .. tostring(hitbox[1]) .. ", " .. tostring(hitbox[2]) .. "}")

    function get_tiles(points, axis, move)
        local ts = {}
        for _, p in ipairs(points) do
            local t = p2t(p)
            if not is_air(t) then
                local tile = tilemap[t.y][t.x]
                if not (is_slope(tile) and axis == 0) then
                    table.insert(ts, t)
                end
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

    local points = get_points(hitbox, PLAYER_COLLISION_POINTS)

    for axis = 0, 1 do
        local fns = { vec.x, vec.y }
        local dim = fns[axis+1]
        local move = sign(dim(player.pos - old_pos))
        if move ~= 0 then
            move = move == -1 and 0 or 1

        -- for move = 0, 1 do
            local tiles = get_tiles(points[axis+1][move+1], axis, move)
            tprint(fmt.tostring("tiles =", tiles))
            local tiles2 = flatten(map(function (_, t)
                local p = t2p(t)
                return { p, p + vec.v2(TILE_SIZE, TILE_SIZE) }
            end, tiles))
            if axis == 1 and move == 1 then
                tprint(fmt.tostring("tiles =", tiles[1], tiles[2]))
                if #tiles > 2 then
                    tprint(fmt.tostring(tiles[3]))
                end
                if #tiles > 3 then
                    tprint(fmt.tostring(tiles[4]))
                end
            end
            local ops = {maxf, minf}
            local tile = ops[move+1](dim, tiles2)
            if math.abs(tile) ~= math.huge then
                player.vel = vec.set_dim(player.vel, axis, 0)
                local diff = { 0, dim(hitbox[1]) - dim(hitbox[2]) }
                local new_dim = math.floor(tile + diff[move+1] - dim(PLAYER_HITBOX[1]))
                player.pos = vec.set_dim(player.pos, axis, new_dim)
                tprint(fmt.tostring("new_dim =", new_dim))
                hitbox = map(function (_, v) return v + player.pos end, PLAYER_HITBOX)
                points = get_points(hitbox, PLAYER_COLLISION_POINTS)
                callbacks[axis * 2 + move + 1]()
            end
        end
    end

    tprint("pos (adjusted) = " .. tostring(player.pos))

    player.coyote_time = (old_on_ground and not player.on_ground and player.vel.y > 0) and COYOTE_TIME_FRAMES
                      or (player.on_ground) and 0
                      or math.max(0, player.coyote_time - 1)
    tprint("coyote = " .. tostring(player.coyote_time))

    -- do jump buffering here since we've got points calculated...
    if rl.IsKeyPressed(rl.KEY_Z) and not player.on_ground and player.vel.y > 0 then
        print("checking points")
        for _, p in ipairs(points[2][2]) do
            if not is_air(p2t(p + vec.v2(0, JUMP_BUF_WINDOW))) then
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
                local info = tile_info[tile]
                local orig = t2p(vec.v2(x, y))
                if info.slope ~= nil then
                    if info.slope.part == 'top' then
                        local points = map(function (_, p)
                            return orig + p * TILE_SIZE
                        end, info.slope.points)
                        rl.DrawTriangle(points[1], points[2], points[3], info.color)
                        local normal = get_normal(points[1], points[2])
                        local slope_height = maxf(vec.y, info.slope.points)
                        local line_orig = orig + vec.v2(TILE_SIZE, TILE_SIZE * slope_height) / 2
                        rl.DrawLineV(line_orig, line_orig + normal * TILE_SIZE, rl.RED)
                    end
                else
                    rl.DrawRectangleV(orig, vec.v2(TILE_SIZE, TILE_SIZE), info.color)
                end
            end
        end
    end

    rl.DrawRectangleLinesEx(rec.new(player.pos, PLAYER_DRAW_SIZE), 1.0, rl.RED)

    if points ~= nil then
        for _, ps1 in ipairs(points) do
            for _, ps2 in ipairs(ps1) do
                for _, p in ipairs(ps2) do
                    rl.DrawPixelV(p, rl.GREEN)
                end
            end
        end
    end

    rl.EndMode2D()

    for _, line in ipairs(lines_to_print) do
        rl.DrawText(line[1], 5, line[2], 10, rl.GREEN)
    end

    rl.EndTextureMode()

    rl.DrawTexturePro(
        buffer.texture,
        rec.new(vec.zero, vec.v2(SCREEN_WIDTH * TILE_SIZE        , -SCREEN_HEIGHT * TILE_SIZE        )),
        rec.new(vec.zero, vec.v2(SCREEN_WIDTH * TILE_SIZE * SCALE,  SCREEN_HEIGHT * TILE_SIZE * SCALE)),
        vec.zero, 0,
        rl.WHITE
    )

	rl.EndDrawing()
end

