local fmt = require "fmt"

local vec = {}

vec.one  = rl.new("Vector2", 1, 1)
vec.zero = rl.new("Vector2", 0, 0)

function vec.v2(x, y) return rl.new("Vector2", x, y) end
function vec.normalize(v) return rl.Vector2Normalize(v) end
function vec.rotate(v, angle) return rl.Vector2Rotate(v, angle) end
function vec.dot(a, b) return rl.Vector2DotProduct(a, b) end
function vec.floor(v) return vec.v2(math.floor(v.x), math.floor(v.y)) end
function vec.abs(v) return vec.v2(math.abs(v.x), math.abs(v.y)) end
function vec.eq(a, b) return rl.Vector2Equals(a, b) == 1 end

function vec.x(v) return v.x end
function vec.y(v) return v.y end
function vec.dim(v, d) return d == 1 and v.x or v.y end

function vec.set_dim(v, d, x)
    return vec.v2(d == 1 and x or v.x, d == 2 and x or v.y)
end

function rec(pos, size)
    return rl.new("Rectangle", pos.x, pos.y, size.x, size.y)
end

-- general utilities starting here
function identity(x) return x end
function lt(a, b) return a < b end
function gt(a, b) return a > b end
function lteq(a, b) return a < b or rl.FloatEquals(a, b) == 1 end
function gteq(a, b) return a > b or rl.FloatEquals(a, b) == 1 end
function sign(x) return x < 0 and -1 or x > 0 and 1 or 0 end
function b2i(exp) return exp and 1 or 0 end
function flip(x) return bit.bxor(x, 1) end
function clamp(x, min, max) return rl.Clamp(x, min, max) end
function lerp(a, b, t) return rl.Lerp(a, b, t) end
function rlerp(a, b, v) return rl.Normalize(v, a, b) end
function aabb(p, s) return { p, p + s } end

function find(t, value, comp)
    for i, v in ipairs(t) do
        if comp ~= nil and comp(value, v) or value == v then
            return i
        end
    end
    return false
end

function findf(proc, t)
    for _, v in ipairs(t) do
        if proc(v) then
            return v
        end
    end
    return false
end

function map(fn, t)
    local r = {}
    for i, v in ipairs(t) do
        table.insert(r, fn(v, i))
    end
    return r
end

function filter(pred, t)
    local r = {}
    for i, v in ipairs(t) do
        if pred(v, i) then
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

function append(...)
    local r = {}
    for _, t in ipairs({...}) do
        for _, v in ipairs(t) do
            table.insert(r, v)
        end
    end
    return r
end

function minf(f, t)
    return foldl(function (k, v, r) return math.min(f(v), r) and v or r end,  math.huge, t)
end

function maxf(f, t)
    return foldl(function (k, v, r) return math.max(f(v), r) and v or r end, -math.huge, t)
end

function partition(pred, t)
    local r1, r2 = {}, {}
    for k, v in pairs(t) do
        table.insert(pred(v) and r1 or r2, v)
    end
    return r1, r2
end

function all_eq(t)
    return #t == 0 or not findf(function (v) return not vec.eq(v, t[1]) end, t)
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
rl.InitWindow(
    SCREEN_WIDTH  * TILE_SIZE * SCALE,
    SCREEN_HEIGHT * TILE_SIZE * SCALE,
    "2d platformer physics"
)
rl.SetTargetFPS(60)

local buffer = rl.LoadRenderTexture(SCREEN_WIDTH * TILE_SIZE, SCREEN_HEIGHT * TILE_SIZE)

local camera = rl.new("Camera2D",
    vec.v2(SCREEN_WIDTH, SCREEN_HEIGHT) * TILE_SIZE / 2, vec.v2(0, 0), 0, 1)

-- assumes a and b are in counter-clockwise order
function get_normal(a, b)
    return vec.normalize(vec.rotate(a - b, -math.pi/2))
end

function slope(origin, p1, p2, p3)
    return {
        slope = {
            origin = origin,
            points = { p1, p2, p3 },
            size   = vec.abs(p1 - p2)
        },
        normals = { get_normal(p1, p2) }
    }
end

-- store info about a tile here, such as color, shape, normals, etc.
local tile_info = {
    [1]  = { normals = { vec.v2(1, 0), vec.v2(-1, 0), vec.v2(0, 1), vec.v2(0, -1) } }, -- box
    [2]  = { normals = { vec.v2( 0, -1) } }, -- -
    [23] = { normals = { vec.v2( 0,  1) } }, -- _
    [24] = { normals = { vec.v2(-1,  0) } }, -- |
    [25] = { normals = { vec.v2( 1,  0) } }, --  |
    [3]  = slope(vec.v2( 0,  0), vec.v2(1, 1), vec.v2(0, 0), vec.v2(0, 1)), -- |\
    [4]  = slope(vec.v2( 0,  0), vec.v2(1, 0), vec.v2(0, 1), vec.v2(1, 1)), -- /|
    [5]  = slope(vec.v2( 0,  0), vec.v2(0, 0), vec.v2(1, 1), vec.v2(1, 0)), -- \|
    [6]  = slope(vec.v2( 0,  0), vec.v2(0, 1), vec.v2(1, 0), vec.v2(0, 0)), -- |/
    [7]  = slope(vec.v2( 0,  0), vec.v2(1, 0), vec.v2(0, 2), vec.v2(1, 2)), --  /|
    [8]  = slope(vec.v2( 0,  1), vec.v2(1, 0), vec.v2(0, 2), vec.v2(1, 2)), -- / |
    [9]  = slope(vec.v2( 0,  0), vec.v2(1, 2), vec.v2(0, 0), vec.v2(0, 2)), -- |\
    [10] = slope(vec.v2( 0,  1), vec.v2(1, 2), vec.v2(0, 0), vec.v2(0, 2)), -- | \
    [11] = slope(vec.v2( 0,  0), vec.v2(0, 2), vec.v2(1, 0), vec.v2(0, 0)), -- | /
    [12] = slope(vec.v2( 0,  1), vec.v2(0, 2), vec.v2(1, 0), vec.v2(0, 0)), -- |/
    [13] = slope(vec.v2( 0,  0), vec.v2(0, 0), vec.v2(1, 2), vec.v2(1, 0)), -- \ |
    [14] = slope(vec.v2( 0,  1), vec.v2(0, 0), vec.v2(1, 2), vec.v2(1, 0)), --  \|
    [15] = slope(vec.v2( 0,  0), vec.v2(2, 0), vec.v2(0, 1), vec.v2(2, 1)), --  /
    [16] = slope(vec.v2( 1,  0), vec.v2(2, 0), vec.v2(0, 1), vec.v2(2, 1)), -- /_
    [17] = slope(vec.v2( 0,  0), vec.v2(2, 1), vec.v2(0, 0), vec.v2(0, 1)), -- \
    [18] = slope(vec.v2( 1,  0), vec.v2(2, 1), vec.v2(0, 0), vec.v2(0, 1)), -- _\
    [19] = slope(vec.v2( 0,  0), vec.v2(0, 0), vec.v2(2, 1), vec.v2(2, 0)), -- \-
    [20] = slope(vec.v2( 1,  0), vec.v2(0, 0), vec.v2(2, 1), vec.v2(2, 0)), --  \
    [21] = slope(vec.v2( 0,  0), vec.v2(0, 1), vec.v2(2, 0), vec.v2(0, 0)), -- -/
    [22] = slope(vec.v2( 1,  0), vec.v2(0, 1), vec.v2(2, 0), vec.v2(0, 0)), -- /
}

local tilemap = {
    {  1,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0 },
    {  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0 },
    {  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0, 24,  0,  0,  0,  0,  0,  0,  0 },
    {  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0, 24,  0,  0,  0,  0,  0,  0,  0 },
    {  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0, 24,  0,  0,  0,  0,  0,  0,  0 },
    {  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0, 24,  0,  0,  0,  0,  0,  0,  0 },
    {  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0, 24,  0,  0,  0,  0,  0,  0,  0 },
    {  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0, 24,  0,  0,  0,  0,  0,  0,  0 },
    {  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  0,  3,  0,  0, 15, 16 },
    {  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  1,  0,  0,  6,  0,  0, 17, 18,  0,  0,  0,  0,  4,  0,  0 },
    {  0,  0,  0,  0,  0,  1,  0,  1,  3,  0,  0,  0,  6,  0,  0,  0,  1,  2,  0,  0,  0,  4,  0,  0,  0 },
    {  0,  0,  0,  7,  9,  0,  1,  0,  0,  1,  1,  6,  0,  0,  0,  0,  0,  0,  0,  0,  4,  0,  0,  0,  0 },
    {  0,  0,  0,  8, 10,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  4,  0,  0,  0,  0,  0 },
    {  0,  0,  0, 13, 11,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  4,  0,  0,  0,  0,  0,  0 },
    {  0,  0,  0, 14, 12,  1,  1,  1,  1,  1,  0,  0,  0,  0,  0,  0,  0,  7,  0,  0,  0,  0,  0,  0,  0 },
    {  0,  0,  0,  4,  3,  1,  0,  0,  0,  1,  1,  1,  2,  2,  0,  0,  0,  8,  0, 17, 18,  0,  3,  0,  0 },
    {  1,  1,  1,  5,  6,  1,  0,  0,  0,  1,  0,  0,  0,  0,  0,  0,  0,  1,  0, 21, 22,  0,  6,  0,  0 },
    {  1,  1,  1,  1,  1,  1,  0,  0,  0,  1,  1,  3,  0,  0,  0,  4,  1,  1,  1,  1,  1,  1,  1,  1,  0 },
    {  0,  0, 13,  0,  0,  0,  0,  0,  0,  0,  0,  1,  1, 15, 16,  0,  1, 19, 20,  0,  0,  0,  0,  0,  0 },
    {  0,  0, 14,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  1,  1,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0 },
}

function p2t(p) return vec.floor(p / TILE_SIZE) + vec.one end
function t2p(t) return (t - vec.one) * TILE_SIZE end

function info_of(t) return tile_info[tilemap[t.y][t.x]] end

function is_air(t)
    return tilemap[t.y] == nil or tilemap[t.y][t.x] == nil or tilemap[t.y][t.x] == 0
end

function is_slope(t)
    if is_air(t) then
        return false
    end
    local ti = tilemap[t.y][t.x]
    return ti ~= nil and ti >= 3 and ti <= 22
end

-- check if t is a slope and its highest point is left (sgn = -1) or right (sgn = 1)
function is_slope_facing(t, sgn)
    return is_slope(t) and sign(info_of(t).normals[1].x) == sgn
end

function same_slope(t, n)
    return vec.eq(t - info_of(t).slope.origin,
                  n - info_of(n).slope.origin)
end

function slope_diag_point(to, info, value, dim, dim_to)
    local u = value - dim(to)
    local t = rlerp(   dim(info.slope.points[1]),    dim(info.slope.points[2]), u / TILE_SIZE)
    return     lerp(dim_to(info.slope.points[1]), dim_to(info.slope.points[2]), t)
end

function slope_diag_point_y(to, info, value)
    local yu = slope_diag_point(to, info, value, vec.x, vec.y)
    return (yu < 0 or yu > info.slope.size.y) and math.huge
        or to.y + yu * TILE_SIZE
end

function slope_tiles(t)
    local res = {}
    local origin = t - info_of(t).slope.origin
    function loop(t)
        table.insert(res, t)
        for _, n in ipairs{ vec.v2(0, -1), vec.v2(0, 1), vec.v2(-1, 0), vec.v2(1, 0) } do
            if is_slope(t+n)
            and vec.eq(t+n - info_of(t+n).slope.origin, origin)
            and not find(res, t+n, vec.eq) then
                loop(t+n)
            end
        end
    end
    loop(t)
    return res
end

function inside_slope(tile, box, count_line)
    local info = info_of(tile)
    local dir  = b2i(info.normals[1].y < 0)
    local to   = t2p(tile - info.slope.origin)
    local yu   = slope_diag_point(to, info, box[1].x + (box[2].x - box[1].x)/2, vec.x, vec.y)
    local y    = to.y + yu * TILE_SIZE
    local fns  = count_line and { gteq, lteq } or { gt, lt }
    local lt   = fns[dir+1]
    return not lt(box[dir+1].y, y) and y or false
end

-- tiles have a "border" where collisions register. this constant controls how big it is
local TILE_TOLLERANCE = 5
local SLOPE_TOLLERANCE = 2

function generate_collision_hitboxes(hb, offs)
    return {
        {
            { vec.v2(hb[1].x  , hb[1].y + offs[1]), vec.v2(hb[1].x+1, hb[2].y - offs[1]) }, -- left
            { vec.v2(hb[2].x-1, hb[1].y + offs[1]), vec.v2(hb[2].x  , hb[2].y - offs[1]) }, -- right
        }, {
            { vec.v2(hb[1].x + offs[2], hb[1].y   ), vec.v2(hb[2].x - offs[2], hb[1].y+10) }, -- up
            { vec.v2(hb[1].x + offs[2], hb[2].y-10), vec.v2(hb[2].x - offs[2], hb[2].y   ) }, -- down
        }, {
            { vec.v2(hb[1].x  , hb[1].y), vec.v2(hb[1].x+1, hb[2].y) }, -- left, for slopes
            { vec.v2(hb[2].x-1, hb[1].y), vec.v2(hb[2].x  , hb[2].y) }, -- right, for slopes
        }
    }
end

function get_hitboxes(hitbox, from)
    return map(function (axis)
        return map(function (dir)
            return map(function (p) return hitbox[1] + p end, dir)
        end, axis)
    end, from)
end

local ENTITY = {
    PLAYER = 1,
    MOVING_PLATFORM = 2,
    BOULDER = 3,
}

-- info about entities is stored here. it's all constant data.
local entity_info = {
    [ENTITY.PLAYER] = {
        draw_size          = vec.v2(TILE_SIZE, TILE_SIZE * 2),
        hitbox             = { vec.zero, vec.v2(TILE_SIZE, TILE_SIZE*2) },
        collision_hitboxes = generate_collision_hitboxes({ vec.zero, vec.v2(TILE_SIZE, TILE_SIZE*2) }, { TILE_TOLLERANCE, 4 })
    },
    [ENTITY.MOVING_PLATFORM] = {
        normals     = { vec.v2(0, -1), vec.v2(0, 1), vec.v2(1, 0), vec.v2(-1, 0) },
        size        = vec.v2(3, 1) * TILE_SIZE,
        path_length = vec.v2(10, 0) * TILE_SIZE,
    },
    [ENTITY.BOULDER] = {
        hitbox               = { vec.zero, vec.v2(2, 2) * TILE_SIZE },
        normals            = { vec.v2(0, -1), vec.v2(0, 1), vec.v2(1, 0), vec.v2(-1, 0) },
        collision_hitboxes = generate_collision_hitboxes({ vec.zero, vec.v2(2, 2) * TILE_SIZE }, { 5, 0 })
    },
}

function player(pos)
    return {
        type          = ENTITY.PLAYER,
        pos           = pos,
        old_pos       = pos,
        vel           = vec.zero,
        on_ground     = false,
        coyote_time   = 0,
        jump_buf      = false,
        collisions    = {},
    }
end

function moving_platform(pos, dir)
    return {
        type      = ENTITY.MOVING_PLATFORM,
        start_pos = t2p(pos),
        pos       = t2p(pos),
        old_pos   = t2p(pos),
        dir       = dir * TILE_SIZE,
        carrying  = {},
    }
end

function boulder(pos)
    return {
        type      = ENTITY.BOULDER,
        old_pos   = t2p(pos),
        pos       = t2p(pos),
        vel       = vec.v2(0, 0),
        on_ground = false,
        carrying  = {},
    }
end

-- entities buffer, entity[1] is always the player
local entities = {
    player(vec.v2(SCREEN_WIDTH, SCREEN_HEIGHT) * TILE_SIZE / 2
         + vec.v2(TILE_SIZE/2 - 8 * TILE_SIZE, -8 * TILE_SIZE)),
    moving_platform(vec.v2(-3, 7), vec.v2(6, 0)),
    -- boulder(vec.v2(1, 0)),
    -- boulder(vec.v2(4, 7)),
    -- moving_platform(vec.v2(10, 7), vec.v2(-6, 0)),
    moving_platform(vec.v2(0, 22), vec.v2(6, 0)),
}

-- physics constant for the player, change these to control the "feel" of the game

local ACCEL = 700
local DECEL = 300

-- the cap is in tiles, but you'd probably want to know how many pixels
-- you're traveling each frame. the formulas are:
--
--  p = cap / fps, cap = p * fps
--
-- where is the pixels traveled each frame and fps is a target fps (i.e.
-- the minimum fps the game can have).
-- in practice, only caps with a p >= 16 get really problematic (as that's where
-- you start skipping tiles)

local VEL_X_CAP = 10*30
local VEL_Y_CAP = 15*30
local GRAVITY = 400
-- used when pressing the jump button while falling
local SLOW_GRAVITY = 300
local JUMP_HEIGHT_MAX1 = 5 -- tiles
local JUMP_HEIGHT_MAX2 = 6 -- tiles, max height is interpolated between 1 and 2
local JUMP_HEIGHT_MIN  = 0.2 -- tiles
local JUMP_VEL_MIN = -math.sqrt(2 * GRAVITY * JUMP_HEIGHT_MIN * TILE_SIZE)
local COYOTE_TIME_FRAMES = 10
-- how many pixels over the ground should a jump be registered?
local JUMP_BUF_WINDOW = 16
-- how many pixels over the ground should we check for slopes to stick on?
-- (fixes a problem where going downward slopes is erratic)
local SLOPE_ADHERENCE_WINDOW = 10

local gravity_dir = 1

local logfile = io.open("log.txt", "w")

while not rl.WindowShouldClose() do
    local dt = rl.GetFrameTime()

    -- debug facilities
    local cur_line = 5
    local lines_to_print = {}
    function tprint(s)
        table.insert(lines_to_print, { s, cur_line })
        cur_line = cur_line + 10
        logfile:write(s .. "\n")
    end

    tprint(tostring(rl.GetFPS()) .. " FPS")
    tprint("dt = " .. tostring(dt))

    if rl.IsKeyReleased(rl.KEY_R) then
        gravity_dir = -gravity_dir
    end

    function carry_entities(ids, movement)
        for _, id in ipairs(ids) do
            entities[id].pos = entities[id].pos + movement
            if entities[id].carrying ~= nil then
                carry_entities(entities[id].carrying, movement)
            end
        end
    end

    -- first step entities that can carry stuff, but can't be carried
    for id, entity in ipairs(entities) do
        local info = entity_info[entity.type]
        if entity.type == ENTITY.MOVING_PLATFORM then
            entity.old_pos = entity.pos
            entity.pos = entity.pos + entity.dir * dt
            -- handle carried entities
            carry_entities(entity.carrying, entity.dir * dt)
            -- handle direction change
            for _, axis in ipairs{1,2} do
                if math.abs(vec.dim(entity.pos, axis) - vec.dim(entity.start_pos, axis)) >= vec.dim(info.path_length, axis) then
                    entity.start_pos = vec.set_dim(entity.start_pos, axis, vec.dim(entity.start_pos, axis)
                                     + vec.dim(info.path_length, axis) * sign(vec.dim(entity.dir, axis)))
                    entity.dir = vec.set_dim(entity.dir, axis, -vec.dim(entity.dir, axis))
                end
            end
            entity.carrying = {}
        end
    end

    -- handle the rest of the entities
    for id, entity in ipairs(entities) do
        local info = entity_info[entity.type]
        if entity.type == ENTITY.BOULDER then
            entity.vel = entity.vel + vec.v2(0, GRAVITY) * dt
            entity.old_pos = entity.pos
            entity.pos = entity.pos + entity.vel * dt
            entity.carrying = {}
        elseif entity.type == ENTITY.PLAYER then
            local accel_hor = (rl.IsKeyDown(rl.KEY_LEFT)  and -ACCEL or 0)
                            + (rl.IsKeyDown(rl.KEY_RIGHT) and  ACCEL or 0)
            local decel_hor = entity.vel.x > 0 and -DECEL
                           or entity.vel.x < 0 and  DECEL
                           or 0
            local gravity = rl.IsKeyDown(rl.KEY_Z) and not entity.on_ground and sign(entity.vel.y) == gravity_dir
                        and SLOW_GRAVITY or GRAVITY
            gravity = gravity * gravity_dir
            local accel = vec.v2(accel_hor + decel_hor, gravity)

            entity.vel = entity.vel + accel * dt
            entity.vel.x = clamp(entity.vel.x, -VEL_X_CAP, VEL_X_CAP)
            if math.abs(entity.vel.x) < 4 then
                entity.vel.x = 0
            end
            entity.vel.y = clamp(entity.vel.y, -VEL_Y_CAP, VEL_Y_CAP)

            -- jump control
            if (rl.IsKeyPressed(rl.KEY_Z) or entity.jump_buf) and (entity.on_ground or entity.coyote_time > 0) then
                local h = lerp(JUMP_HEIGHT_MAX1, JUMP_HEIGHT_MAX2, math.abs(entity.vel.x / VEL_X_CAP))
                local jump_vel = -math.sqrt(2 * GRAVITY * h * TILE_SIZE)
                entity.vel.y = jump_vel * gravity_dir
                entity.jump_buf = false
            end

            -- when jumping, if the player stops pressing the jump key, quickly change
            -- his velocity to simulate variable jump height
            if not rl.IsKeyDown(rl.KEY_Z) and not entity.on_ground
               and (gravity_dir > 0 and entity.vel.y < JUMP_VEL_MIN * gravity_dir
                 or gravity_dir < 0 and entity.vel.y > JUMP_VEL_MIN * gravity_dir) then
                entity.vel.y = JUMP_VEL_MIN * gravity_dir
            end

            entity.old_pos = entity.pos
            if not FREE_MOVEMENT then
                entity.pos = entity.pos + entity.vel * dt
            else
                entity.pos = entity.pos + vec.v2(
                    rl.IsKeyDown(rl.KEY_LEFT) and -1 or rl.IsKeyDown(rl.KEY_RIGHT) and 1 or 0,
                    rl.IsKeyDown(rl.KEY_UP)   and -1 or rl.IsKeyDown(rl.KEY_DOWN)  and 1 or 0
                ) * FREE_MOVEMENT_SPEED
            end

            tprint("oldpos = " .. tostring(entity.old_pos))
            tprint("pos    = " .. tostring(entity.pos))
            tprint("vel    = " .. tostring(entity.vel))
            tprint("accel  = " .. tostring(accel))
        end
    end

    -- collisions
    function get_tiles(box, fn)
        local res, start, endd = {}, p2t(box[1]), p2t(box[2])
        for y = start.y, endd.y do
            for x = start.x, endd.x do
                t = vec.v2(x, y)
                if not is_air(t) and fn(t) then
                    table.insert(res, t)
                end
            end
        end
        return res
    end

    -- compute collision point of box a against box b, with b's normals
    function box_collision(a, old_a, b, old_b, axis, side_a, normals)
        local v = side_a == 0 and 1 or -1
        local normal = vec.set_dim(vec.zero, axis+1, v)
        local ref = axis == 0 and vec.x or vec.y
        local a_dir = a[1] - old_a[1]
        local b_dir = b[1] - old_b[1]
        if not find(normals, normal, vec.eq)
        or vec.dot(a_dir, normal) >= 0 and ref(a_dir) ~= 0
           and math.abs(ref(a_dir)) >= math.abs(ref(b_dir)) then
            return math.huge
        end
        local side_b = flip(side_a)
        local ap = ref(old_a[side_a+1])
        local bp = ref(    b[side_b+1])
        local lteq = side_a == 0 and gteq or lteq
        return lteq(ap, bp + TILE_TOLLERANCE * -v) and bp or math.huge
    end

    function collide_tiles(hitbox, old_hitbox, boxes, axis, side)
        local tiles = get_tiles(boxes[axis+1][side+1], identity)
        if axis == 0 and boxes[3] ~= nil then
            tiles = append(tiles, get_tiles(boxes[3][side+1], is_slope))
        end
        if #tiles == 0 then
            return {}, {}
        end
        local size = hitbox[2] - hitbox[1]
        local dir = vec.set_dim(vec.zero, axis+1, side == 0 and -1 or 1)

        function ignore_tile(tile, slopes)
            if axis == 0 then
                local dir = side == 0 and -1 or 1
                return is_slope_facing(tile + vec.v2(-dir, 0), -dir)
                   and not inside_slope(tile + vec.v2(-dir, 0), old_hitbox, true)
            end
            function check(t, sgn)
                local info = info_of(t)
                return is_slope(t, sgn)
                   and sign(info.normals[1].x) == sgn
                   and side == b2i(info.normals[1].y < 0)
                   and find(slopes, t, vec.eq)
            end
            return check(tile + vec.v2(-1, 0), -1)
                or check(tile + vec.v2( 1, 0),  1)
        end

        function get_tile_dim(tile)
            local hb = aabb(t2p(tile), vec.v2(TILE_SIZE, TILE_SIZE))
            return box_collision(hitbox, old_hitbox, hb, hb, axis, side, info_of(tile).normals)
        end

        function get_slope_dim(tile)
            local info = info_of(tile)
            local dir = b2i(info.normals[1].y < 0)
            if dir ~= side or vec.dot(hitbox[1] - old_hitbox[1], info.normals[1]) >= 0 then
                return math.huge
            end
            local to    = t2p(tile - info.slope.origin)
            local y     = slope_diag_point_y(to, info,     hitbox[1].x + size.x/2)
            local old_y = slope_diag_point_y(to, info, old_hitbox[1].x + size.x/2)
            if y == math.huge then
                return math.huge
            end
            local lteq = dir == 0 and gteq or lteq
            local toll = SLOPE_TOLLERANCE * -sign(info.normals[1].y)
            if (old_y == math.huge or lteq(old_hitbox[dir+1].y, old_y + toll))
            and not lteq(hitbox[dir+1].y, y) then
                return y
            end
            return math.huge
        end

        function get_slope_y(slopes)
            return #slopes > 0 and get_slope_dim(slopes[1]) or math.huge
        end

        function get_slope_x(slopes)
            if #slopes < 2 then
                return math.huge
            end
            local old_slopes = slopes
            slopes = filter(function (t)
                local neighbor = t + vec.v2(side == 0 and 1 or -1, 0)
                return b2i(info_of(t).normals[1].x < 0) == side
                   and not (is_slope(neighbor) and same_slope(t, neighbor))
            end, old_slopes)
            local origs = map(function (s)
                return s - info_of(s).slope.origin
            end, slopes)
            if #origs < 2 or all_eq(origs) then
                return math.huge
            end
            local old_center = old_hitbox[1].x + size.x/2
            local center     =     hitbox[1].x + size.x/2
            local tp = t2p(slopes[1]).x
            local p = tp + (side == 0 and TILE_SIZE or 0)
            local lteq = side == 0 and gteq or lteq
            local toll = SLOPE_TOLLERANCE * -sign(info_of(slopes[1]).normals[1].x)
            if lteq(old_center, p+toll) and not lteq(center, p) then
                return tp + size.x/2
            end
            return math.huge
        end

        local all_slopes, all_tiles = partition(is_slope, tiles)
        local slopes = filter(function (t)
            return t.x == p2t(hitbox[1] + size/2).x
        end, all_slopes)
        local tiles = filter(function (t)
            return not ignore_tile(t, slopes) end,
        all_tiles)
        local points = map(get_tile_dim, tiles)
        table.insert(points, axis == 0 and get_slope_x(slopes) or get_slope_y(slopes))
        points = filter(function (v) return v ~= math.huge end, points)
        if #points == 0 then
            return {}, {}
        end
        local result = {}
        for _, ts in ipairs({tiles, slopes}) do
            for _, t in ipairs(ts) do
                table.insert(result, { tile = t, dir = dir })
            end
        end
        return points, result
    end

    function get_entities(pos, size, entity_id)
        local r = rec(pos, size)
        -- dumb loop over every entity. this is where one could use
        -- something smarter, e.g. quadtrees
        return filter(function (e)
            local info = entity_info[e.entity.type]
            return entity_id ~= e.id
               and rl.CheckCollisionRecs(r, rec(e.entity.pos, info.size))
        end, map(function (e, i) return { id = i, entity = e } end, entities))
    end

    function player_collision(pos, old_pos, hitbox_unit, collision_boxes, entity_id)
        local size = hitbox_unit[2] - hitbox_unit[1]
        local result = {}
        for axis = 0, 1 do
            for side = 0, 1 do
                local old_hitbox = map(function (v) return v + old_pos end, hitbox_unit)
                local     hitbox = map(function (v) return v +     pos end, hitbox_unit)
                local boxes = get_hitboxes(hitbox, collision_boxes)
                local points = {}

                -- collision with entities
                for _, e in ipairs(get_entities(hitbox[1], size, entity_id)) do
                    local info = entity_info[e.entity.type]
                    local p = box_collision(
                        hitbox, old_hitbox,
                        aabb(e.entity.pos, info.hitbox[2] - info.hitbox[1]),
                        aabb(e.entity.old_pos, info.hitbox[2] - info.hitbox[1]),
                        axis, side, info.normals
                    )
                    if p ~= math.huge then
                        local dir = vec.set_dim(vec.zero, axis+1, side == 0 and -1 or 1)
                        table.insert(points, p)
                        table.insert(result, { entity_id = e.id, dir = dir })
                    end
                end

                -- collision with tiles
                local ps, res = collide_tiles(hitbox, old_hitbox, boxes, axis, side)
                points = append(points, ps)
                result = append(result, res)

                if #points > 0 then
                    local minf = side == 0 and maxf or minf
                    local p = minf(identity, points)
                    pos = vec.set_dim(pos, axis+1, p - vec.dim(size, axis+1) * side)
                end
            end
        end
        return pos, result
    end

    local calculated_vel = entities[1].vel -- used only for drawing

    -- handle entities that collide with ground
    for id, entity in ipairs(entities) do
        local info = entity_info[entity.type]
        if entity.type == ENTITY.BOULDER or entity.type == ENTITY.PLAYER then
            pos, collisions = player_collision(entity.pos, entity.old_pos, info.hitbox, info.collision_hitboxes, id)
            entity.pos = pos
            tprint(fmt.tostring("collisions = ", collisions))

            -- setup ground flag so it behaves well with gravity
            local old_on_ground = entity.on_ground
            entity.on_ground = findf(function (v)
                return vec.eq(v.dir, vec.v2(0, gravity_dir))
            end, collisions)
                and true or false
            tprint("on ground = " .. tostring(entity.on_ground))
            tprint("old ground = " .. tostring(old_on_ground))

            -- slope adherence
            if old_on_ground and not entity.on_ground and sign(entity.vel.y) == gravity_dir then
                function make_box(x, ya, yb)
                    return { vec.v2(x, math.min(ya, yb)), vec.v2(x, math.max(ya, yb)) }
                end
                local hitbox = map(function (v) return v + entity.pos end, info.hitbox)
                local xdir = sign(entity.pos.x - entity.old_pos.x)
                local center = hitbox[1] + (hitbox[2] - hitbox[1]) / 2
                local side = gravity_dir == 1 and 1 or 0
                local box = make_box(center.x, hitbox[side+1].y, hitbox[side+1].y + SLOPE_ADHERENCE_WINDOW * gravity_dir)
                local tiles = get_tiles(box, function (t) return is_slope_facing(t, xdir) end)
                if #tiles > 0 then
                    local y = inside_slope(tiles[1], box)
                    if y then
                        entity.pos.y = y - info.hitbox[2].y * side
                        entity.on_ground = true
                        table.insert(collisions, { tile = tiles[1], dir = vec.v2(0, 1) })
                    end
                end
            end
            tprint("pos (adjusted) = " .. tostring(entity.pos))

            for _, axis in ipairs{ 0, 1 } do
                if findf(function (v)
                    local d = vec.dim(v.dir, axis+1)
                    -- make sure the entity isn't blocked when pushed from behind
                    return d ~= 0 and sign(d) == sign(vec.dim(entity.vel, axis+1))
                end, collisions) then
                    entity.vel = vec.set_dim(entity.vel, axis+1, 0)
                end
            end
            tprint("vel (adjusted) = " .. tostring(entity.vel))

            for _, c in ipairs(collisions) do
                if c.entity_id and entities[c.entity_id].carrying ~= nil
                and vec.eq(c.dir, vec.v2(0, gravity_dir)) then
                    table.insert(entities[c.entity_id].carrying, id)
                end
            end

            if entity.type == ENTITY.PLAYER then
                entity.collisions = collisions

                entity.coyote_time =
                    (old_on_ground and not entity.on_ground and sign(entity.vel.y) == gravity_dir) and COYOTE_TIME_FRAMES
                    or entity.on_ground and 0
                    or math.max(0, entity.coyote_time - 1)
                tprint("coyote = " .. tostring(entity.coyote_time))

                if rl.IsKeyPressed(rl.KEY_Z) and not entity.on_ground and sign(entity.vel.y) == gravity_dir then
                    local hitbox = map(function (v) return v + entity.pos end, PLAYER_HITBOX)
                    local hitboxes = get_hitboxes(hitbox, info.collision_hitboxes)
                    local side = gravity_dir == 1 and 1 or 0
                    local h = map(function (v)
                        return v + vec.v2(0, JUMP_BUF_WINDOW * gravity_dir)
                    end, hitboxes[2][side+1])
                    if #get_tiles(h, identity) > 0 then
                        entity.jump_buf = true
                    end
                end
                tprint("jump buf = " .. tostring(entity.jump_buf))
            end
        end
    end

    camera.target = entities[1].pos

    -- drawing time!
    rl.BeginDrawing()
    rl.BeginTextureMode(buffer)
    rl.ClearBackground(rl.BLACK)

    rl.BeginMode2D(camera)

    function n2ps(n)
        return vec.eq(n, vec.v2( 0, -1)) and { vec.v2(0, 0), vec.v2(1, 0) }
            or vec.eq(n, vec.v2( 0,  1)) and { vec.v2(0, 1), vec.v2(1, 1) }
            or vec.eq(n, vec.v2(-1,  0)) and { vec.v2(0, 0), vec.v2(0, 1) }
            or                               { vec.v2(1, 0), vec.v2(1, 1) }
    end

    for y = 1, SCREEN_HEIGHT do
        for x = 1, SCREEN_WIDTH do
            local index = tilemap[y][x]
            if index ~= 0 then
                local tile = vec.v2(x, y)
                local info = tile_info[index]
                local orig = t2p(vec.v2(x, y))
                if info.slope == nil then
                    local color = findf(function (v)
                        return v.tile ~= nil and vec.eq(v.tile, tile)
                    end, entities[1].collisions) and rl.RED or rl.WHITE
                    for _, n in ipairs(info.normals) do
                        local ps = n2ps(n)
                        rl.DrawLineV(orig + ps[1] * TILE_SIZE, orig + ps[2] * TILE_SIZE, color)
                    end
                elseif vec.eq(info.slope.origin, vec.zero) then
                    local tiles = slope_tiles(tile)
                    local color = findf(function (v)
                        return v.tile ~= nil and findf(function (s)
                            return vec.eq(v.tile, s)
                        end, tiles)
                    end, entities[1].collisions) and rl.RED or rl.WHITE
                    local points = map(function (p) return orig + p * TILE_SIZE end, info.slope.points)
                    rl.DrawTriangle(points[1], points[2], points[3], color)
                end
            end
        end
    end

    for _, entity in ipairs(entities) do
        local info = entity_info[entity.type]
        if entity.type == ENTITY.MOVING_PLATFORM then
            rl.DrawRectangleRec(rec(entity.pos, info.hitbox[2]), rl.YELLOW)
        elseif entity.type == ENTITY.BOULDER then
            rl.DrawRectangleRec(rec(entity.pos, info.hitbox[2]), rl.GRAY)
        elseif entity.type == ENTITY.PLAYER then
            rl.DrawRectangleLinesEx(rec(entities[1].pos, info.draw_size), 1.0, rl.RED)
            local hitbox = map(function (v) return v + entity.pos end, info.hitbox)
            local hitboxes = get_hitboxes(hitbox, info.collision_hitboxes)
            for _, axis in ipairs(hitboxes) do
                for _, hitbox in ipairs(axis) do
                    rl.DrawRectangleLinesEx(rec(hitbox[1], hitbox[2] - hitbox[1]), 1.0, rl.BLUE)
                end
            end

            local center = hitbox[1] + (hitbox[2] - hitbox[1])/2
            rl.DrawLineV(center, center + vec.normalize(entity.pos - entity.old_pos) * 50, rl.YELLOW)
            rl.DrawLineV(center, center + vec.normalize(calculated_vel) * 50, rl.GREEN)
        end
    end

    rl.EndMode2D()

    for _, line in ipairs(lines_to_print) do
        rl.DrawText(line[1], 5, line[2], 10, rl.GREEN)
    end

    rl.EndTextureMode()

    rl.DrawTexturePro(
        buffer.texture,
        rec(vec.zero, vec.v2(SCREEN_WIDTH * TILE_SIZE        , -SCREEN_HEIGHT * TILE_SIZE        )),
        rec(vec.zero, vec.v2(SCREEN_WIDTH * TILE_SIZE * SCALE,  SCREEN_HEIGHT * TILE_SIZE * SCALE)),
        vec.zero, 0,
        rl.WHITE
    )

	rl.EndDrawing()

    tprint("")
end

