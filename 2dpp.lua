local ffi = require "ffi"
local fmt = require "fmt"

local vec = {}

vec.one  = rl.new("Vector2", 1, 1)
vec.zero = rl.new("Vector2", 0, 0)
vec.huge = rl.new("Vector2", math.huge, math.huge)

function vec.v2(x, y) return rl.new("Vector2", x, y) end
function vec.normalize(v) return rl.Vector2Normalize(v) end
-- function vec.length(v) return rl.Vector2Length(v) end
function vec.rotate(v, angle) return rl.Vector2Rotate(v, angle) end

function vec.floor(v) return vec.v2(math.floor(v.x), math.floor(v.y)) end
function vec.abs(v) return vec.v2(math.abs(v.x), math.abs(v.y)) end
function vec.eq(a, b) return rl.Vector2Equals(a, b) == 1 end

function vec.x(v) return v.x end
function vec.y(v) return v.y end
-- function vec.dim(v, d) return d == 1 and v.x or v.y end

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
function b2i(exp) return exp and 1 or 0 end
function clamp(x, min, max) return rl.Clamp(x, min, max) end
function lerp(a, b, t) return rl.Lerp(a, b, t) end
function identity(x) return x end

function rlerp(a, b, v)
    return (v - a) / (b - a)
end

function findf(t, x, comp)
    for _, v in pairs(t) do
        if comp ~= nil and comp(x, v) or x == v then
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

function minf(f, init, t)
    return foldl(function (k, v, r) return f(v) < f(r) and v or r end, init, t)
end

function maxf(f, init, t)
    return foldl(function (k, v, r) return f(v) > f(r) and v or r end, init, t)
end

function partition(pred, t)
    local r1, r2 = {}, {}
    for k, v in pairs(t) do
        table.insert(pred(k, v) and r1 or r2, v)
    end
    return r1, r2
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
local FREE_MOVEMENT_SPEED = 2

rl.SetConfigFlags(rl.FLAG_VSYNC_HINT)
rl.InitWindow(SCREEN_WIDTH * TILE_SIZE * SCALE, SCREEN_HEIGHT * TILE_SIZE * SCALE, "witch game")
rl.SetTargetFPS(60)

local buffer = rl.LoadRenderTexture(SCREEN_WIDTH * TILE_SIZE, SCREEN_HEIGHT * TILE_SIZE)

local camera = rl.new("Camera2D",
    vec.v2(SCREEN_WIDTH, SCREEN_HEIGHT) * TILE_SIZE / 2, vec.v2(0, 0), 0, 1)

function get_normal(a, b)
    -- assumes a and b are in counter-clockwise order
    return vec.normalize(vec.rotate(a - b, -math.pi/2))
end

function slope(origin, p1, p2, p3)
    return {
        origin = origin,
        points = { p1, p2, p3 },
        normal = get_normal(p1, p2)
    }
end

-- store info about a tile here, such as color, shape, normals, etc.
-- (there are other ways to structure this data, such as struct-of-arrays, but
-- this way the quickest to code)
local tile_info = {
    [1]  = { color = rl.WHITE, },
    [2]  = { color = rl.RED, },
    [3]  = { color = rl.WHITE, slope = slope(vec.v2( 0,  0), vec.v2(1, 1), vec.v2(0, 0), vec.v2(0, 1)) }, -- |\
    [4]  = { color = rl.WHITE, slope = slope(vec.v2( 0,  0), vec.v2(1, 0), vec.v2(0, 1), vec.v2(1, 1)) }, -- /|
    [5]  = { color = rl.WHITE, slope = slope(vec.v2( 0,  0), vec.v2(0, 0), vec.v2(1, 1), vec.v2(1, 0)) }, -- \|
    [6]  = { color = rl.WHITE, slope = slope(vec.v2( 0,  0), vec.v2(0, 1), vec.v2(1, 0), vec.v2(0, 0)) }, -- |/
    [7]  = { color = rl.WHITE, slope = slope(vec.v2( 0,  0), vec.v2(1, 0), vec.v2(0, 2), vec.v2(1, 2)) }, --  /|
    [8]  = { color = rl.WHITE, slope = slope(vec.v2( 0,  1), vec.v2(1, 0), vec.v2(0, 2), vec.v2(1, 2)) }, -- / |
    [9]  = { color = rl.WHITE, slope = slope(vec.v2( 0,  0), vec.v2(1, 2), vec.v2(0, 0), vec.v2(0, 2)) }, -- |\
    [10] = { color = rl.WHITE, slope = slope(vec.v2( 0,  1), vec.v2(1, 2), vec.v2(0, 0), vec.v2(0, 2)) }, -- | \
    [11] = { color = rl.WHITE, slope = slope(vec.v2( 0,  0), vec.v2(0, 2), vec.v2(1, 0), vec.v2(0, 0)) }, -- | /
    [12] = { color = rl.WHITE, slope = slope(vec.v2( 0,  1), vec.v2(0, 2), vec.v2(1, 0), vec.v2(0, 0)) }, -- |/
    [13] = { color = rl.WHITE, slope = slope(vec.v2( 0,  0), vec.v2(0, 0), vec.v2(1, 2), vec.v2(1, 0)) }, -- \ |
    [14] = { color = rl.WHITE, slope = slope(vec.v2( 0,  1), vec.v2(0, 0), vec.v2(1, 2), vec.v2(1, 0)) }, --  \|
    [15] = { color = rl.WHITE, slope = slope(vec.v2( 0,  0), vec.v2(2, 0), vec.v2(0, 1), vec.v2(2, 1)) }, --  /
    [16] = { color = rl.WHITE, slope = slope(vec.v2( 1,  0), vec.v2(2, 0), vec.v2(0, 1), vec.v2(2, 1)) }, -- /_
}

local tilemap = {
    {  1,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0 },
    {  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0 },
    {  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0 },
    {  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0 },
    {  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0 },
    {  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0 },
    {  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0 },
    {  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  4 },
    {  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  4,  0 },
    {  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  6,  0,  0,  0,  0,  0,  0,  0,  0,  4,  0,  0 },
    {  0,  0,  0,  0,  0,  1,  1,  1,  1,  0,  0,  0,  6,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0 },
    {  0,  0,  0,  7,  9,  0,  0,  0,  0,  1,  0,  6,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0 },
    {  0,  0,  0,  8, 10,  0,  0,  0,  0,  2,  1,  0,  0,  0,  0,  0,  0,  0,  0,  4,  0,  0,  0,  0,  0 },
    {  0,  0,  0, 13, 11,  0,  0,  0,  0,  1,  1,  0,  0,  0,  0,  0,  0,  0,  4,  0,  0,  0,  0,  0,  0 },
    {  0,  0,  0, 14, 12,  1,  1,  1,  1,  2,  1,  0,  0,  0,  0,  0,  0,  4,  0,  0,  0,  0,  0,  0,  0 },
    {  0,  0,  0,  4,  3,  1,  0,  0,  0,  1,  1,  0,  9,  0,  0,  0,  7,  0,  0,  0,  0,  0,  0,  0,  0 },
    {  0,  0,  0,  5,  6,  1,  0,  0,  0,  2,  1,  0, 10,  0,  0,  0,  8,  0,  0,  1,  0,  1,  0,  1,  0 },
    {  1,  1,  1,  1,  1,  1,  0,  0,  0,  1,  1,  3,  0,  0, 15, 16,  1,  1,  1,  0,  1,  0,  1,  0,  1 },
    {  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  1,  1,  1,  1,  1,  1,  0,  0,  0,  0,  0,  0,  0,  0 },
    {  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0 },
}

function is_air(t)
    return tilemap[t.y] == nil or tilemap[t.y][t.x] == nil or tilemap[t.y][t.x] == 0
end

function is_slope(ti)
    return ti ~= nil and ti >= 3
end

function get_triangle_points(t)
    return map(function (_, p) return p * TILE_SIZE + t2p(t) end,
                tile_info[tilemap[t.y][t.x]].slope.points)
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

local PLAYER_COLLISION_HITBOXES = {
    {
        { vec.v2( 0,  4), vec.v2( 1, 28) }, -- left
        { vec.v2(15,  4), vec.v2(16, 28) }, -- right
    },
    {
        { vec.v2( 0,  0), vec.v2(15,  1) }, -- up
        { vec.v2( 0, 31), vec.v2(15, 32) }, -- down
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
        ) * FREE_MOVEMENT_SPEED
    end

    tprint("oldpos = " .. tostring(old_pos))
    tprint("pos    = " .. tostring(player.pos))
    tprint("vel    = " .. tostring(player.vel))
    tprint("accel  = " .. tostring(accel))

    -- collision with ground
    local old_on_ground = player.on_ground
    player.on_ground = false
    local callbacks = {
        function () end,
        function () end,
        function () end,
        function () player.on_ground = true end
    }

    function get_tiles(box)
        local ts = {}
        local start = p2t(box[1])
        local endd  = p2t(box[2])
        for y = start.y, endd.y do
            for x = start.x, endd.x do
                t = vec.v2(x, y)
                if not is_air(t) then
                    table.insert(ts, t)
                end
            end
        end
        return ts
    end

    function get_hitboxes(hitbox, from)
        return map(function (_, axis)
            return map(function (_, dir)
                return map(function (_, p) return hitbox[1] + p end, dir)
            end, axis)
        end, from)
    end

    -- remember that we shouldn't collide if vel vector and slope normal
    -- don't cross each other (check dot of them)
    -- if in our list of tiles we have at least one slope, then eliminate any tile
    -- that is left or right to the higher end of a slope
    -- 0 = up, left
    -- 1 = down, right
    for axis = 0, 1 do
        local fns = { vec.x, vec.y }
        local dim = fns[axis+1]
        local move = sign(dim(player.pos - old_pos))
        for move = 0, 1 do
        --if move ~= 0 then
            --move = move == -1 and 0 or 1
            local hitbox = map(function (_, v) return v + player.pos end, PLAYER_HITBOX)
            local boxes = get_hitboxes(hitbox, PLAYER_COLLISION_HITBOXES)
            local possible_tiles = get_tiles(boxes[axis+1][move+1])
            local tiles = possible_tiles
            -- local ops, inits = {maxf, minf}, { -vec.huge, vec.huge }
            -- local min_tile = ops[move+1](dim, inits[move+1], possible_tiles)
            -- local tiles = filter(function (_, t) return dim(t) == dim(min_tile) end, possible_tiles)
            if #tiles > 0 then
                function get_tile_dim(tile, has_slopes)
                    local tl = t2p(tile)
                    local index = tilemap[tile.y][tile.x]
                    local info = tile_info[index]
                    if not (axis == 0 and is_slope(tilemap[tile.y][tile.x-1])) then
                        local points = { vec.one, vec.zero }
                        local diff = { 0, dim(PLAYER_HITBOX[1]) - dim(PLAYER_HITBOX[2]) }
                        local point = tl + points[move+1] * TILE_SIZE
                        return dim(point) + diff[move+1] - dim(PLAYER_HITBOX[1])
                    end
                end

                function get_slope_dim(tile)
                    if tile == nil then
                        return nil
                    end
                    local tl = t2p(tile)
                    local index = tilemap[tile.y][tile.x]
                    local info = tile_info[index]
                    if axis == 1 then
                        local to = tl - info.slope.origin * TILE_SIZE
                        local slope_size  = vec.abs(info.slope.points[1] - info.slope.points[2])
                        local normal = info.slope.normal
                        local x = hitbox[1].x + (hitbox[2].x - hitbox[1].x)/2 - to.x

                        local t = rlerp(info.slope.points[1].x, info.slope.points[2].x, x / 16)
                        local y =  lerp(info.slope.points[1].y, info.slope.points[2].y, t)
                        y = normal.y < 0 and math.max(y, 0)
                         or normal.y > 0 and math.min(y, slope_size.y)
                         or y
                        if normal.y < 0 and y > slope_size.y or normal.y > 0 and y < 0 then
                            return nil
                        end

                        local d = to.y + y * TILE_SIZE
                        -- check if the player is actually inside the slope
                        if normal.y < 0 and player.pos.y + PLAYER_HITBOX[2].y - PLAYER_HITBOX[1].y > d
                        or normal.y > 0 and player.pos.y                                           < d then
                            return d - TILE_SIZE * 2 * b2i(normal.y < 0)
                        end
                    end
                end

                function is_on_center(tile)
                    local tl = t2p(tile)
                    local index = tilemap[tile.y][tile.x]
                    local info = tile_info[index]
                    local to = tl - info.slope.origin * TILE_SIZE
                    local x = hitbox[1].x + (hitbox[2].x - hitbox[1].x)/2 - to.x
                    return x > 0 and x < hitbox[2].x - hitbox[1].x
                end

                local slopes, others = partition(function (_, t) return is_slope(tilemap[t.y][t.x]) end, tiles)
                local slope_d = #slopes > 1 and get_slope_dim(filter(function (_, t) return is_on_center(t) end, slopes)[1])
                             or #slopes > 0 and get_slope_dim(slopes[1])
                             or math.huge
                local dims = filter(
                    function (_, v) return v ~= nil end,
                    map(function (_, tile) return get_tile_dim(tile) end, others))
                table.insert(dims, slope_d)
                local ops, inits = {maxf, minf}, { -math.huge, math.huge }
                local d = ops[move+1](identity, inits[move+1], dims)
                if math.abs(d) ~= math.huge then
                    player.vel = vec.set_dim(player.vel, axis, 0)
                    player.pos = vec.set_dim(player.pos, axis, d)
                end
                callbacks[axis * 2 + move + 1]()
            end
        end
    end

    tprint("pos (adjusted) = " .. tostring(player.pos))
    tprint("on ground = " .. tostring(player.on_ground))

    player.coyote_time = (old_on_ground and not player.on_ground and player.vel.y > 0) and COYOTE_TIME_FRAMES
                      or (player.on_ground) and 0
                      or math.max(0, player.coyote_time - 1)
    tprint("coyote = " .. tostring(player.coyote_time))

    if rl.IsKeyPressed(rl.KEY_Z) and not player.on_ground and player.vel.y > 0 then
        local hitbox = map(function (_, v) return v + player.pos end, PLAYER_HITBOX)
        local hitboxes = get_hitboxes(hitbox, PLAYER_COLLISION_HITBOXES)
        local h = map(function (_, v) return v + vec.v2(0, JUMP_BUF_WINDOW) end, hitboxes[2][2])
        if #get_tiles(h) > 0 then
            player.jump_buf = true
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
                if info.slope == nil then
                    rl.DrawRectangleV(orig, vec.v2(TILE_SIZE, TILE_SIZE), info.color)
                elseif vec.eq(info.slope.origin, vec.zero) then
                    local points = map(function (_, p)
                        return orig + p * TILE_SIZE
                    end, info.slope.points)
                    rl.DrawTriangle(points[1], points[2], points[3], info.color)
                end
            end
        end
    end

    local hitbox = map(function (_, v) return v + player.pos end, PLAYER_HITBOX)
    local hitboxes = get_hitboxes(hitbox, PLAYER_COLLISION_HITBOXES)
    rl.DrawRectangleLinesEx(rec.new(player.pos, PLAYER_DRAW_SIZE), 1.0, rl.RED)

    for _, axis in ipairs(hitboxes) do
        for _, hitbox in ipairs(axis) do
            rl.DrawRectangleLinesEx(rec.new(hitbox[1], hitbox[2] - hitbox[1]), 1.0, rl.BLUE)
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

    tprint("")
end

