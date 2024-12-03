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
function vec.ref(v, d) return d == 1 and v.x or v.y end

function vec.set(v, d, x)
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
function bitsign(x) return x < 0 and 1 or 0 end
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

function minf(f, t)
    return foldl(function (k, v, r) return math.min(f(v), r) end,  math.huge, t)
end

function maxf(f, t)
    return foldl(function (k, v, r) return math.max(f(v), r) end, -math.huge, t)
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

function partition(pred, t)
    local r1, r2 = {}, {}
    for k, v in pairs(t) do
        table.insert(pred(v) and r1 or r2, v)
    end
    return r1, r2
end

function copy_table(t)
    local r = {}
    for k, v in pairs(t) do
        r[k] = v
    end
    return r
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

-- draw everything in this buffer, then draw then buffer scaled
local buffer = rl.LoadRenderTexture(SCREEN_WIDTH * TILE_SIZE, SCREEN_HEIGHT * TILE_SIZE)

local camera = rl.new("Camera2D",
    vec.v2(SCREEN_WIDTH, SCREEN_HEIGHT) * TILE_SIZE / 2, vec.v2(0, 0), 0, 1)

-- assumes a and b are in counter-clockwise order
function get_normal(a, b)
    return vec.normalize(vec.rotate(a - b, -math.pi/2))
end

-- a slope is defined by its points and the relative position of the tile with
-- respect to the "origin" (the top left tile of a slope)
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

-- every tile gets a set of normals to perform collision checks on
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

-- a tilemap is a 2d grid of indices into tile_info. a tile is a 2d position into the tilemap.
local tilemap = {
    {  1,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0 },
    {  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0 },
    {  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0, 24,  0,  0,  0,  0,  0,  0,  0 },
    {  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0, 24,  0,  0,  0,  0,  0,  0,  0 },
    {  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0, 24,  0,  0,  0,  0,  0,  0,  0 },
    {  0,  0,  0,  0,  0,  0,  0, 25,  0,  0,  0,  0,  0,  0,  0,  0,  0, 24,  0,  0,  0,  0,  0,  0,  0 },
    {  0,  0,  0,  0,  0,  0,  0, 25,  0,  0,  0,  0,  0,  0,  0,  0,  0, 24,  0,  0,  0,  0,  0,  0,  0 },
    {  0,  0,  0,  0,  0,  0,  0, 25,  0,  0,  0,  0,  0,  0,  0,  0,  0, 24,  0,  0,  0,  0,  0,  0,  0 },
    {  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  0,  3,  0,  0, 15, 16 },
    {  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  1,  0,  0,  6,  0,  0, 17, 18,  0,  0,  0,  0,  4,  0,  0 },
    {  0,  0,  0,  0,  0,  1,  0,  1,  3,  0,  0,  0,  6,  0,  0,  0,  1,  2,  0,  0,  0,  4,  0,  0,  0 },
    {  0,  0,  0,  7,  9,  0,  1,  0,  0,  1,  1,  6,  0,  0,  0,  0,  0,  0,  0,  0,  4,  0,  0,  0,  0 },
    {  0,  0,  0,  8, 10,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  4,  0,  0,  0,  0,  0 },
    {  0,  0,  0, 13, 11,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  4,  0,  0,  0,  0,  0,  0 },
    {  0,  0,  0, 14, 12,  1,  1,  1,  1,  1,  0,  0,  0,  0,  3,  0,  0,  7,  0,  0,  0,  0,  0,  0,  0 },
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

-- check if t is a slope and its highest point is left or right (sgn = -1 or 1)
function is_slope_facing(t, sgn)
    return is_slope(t) and sign(info_of(t).normals[1].x) == sgn
end

function same_slope(t, n)
    return vec.eq(t - info_of(t).slope.origin,
                  n - info_of(n).slope.origin)
end

-- given a x position, find the corresponding y into the slope (or vice-versa)
function slope_diag_point(to, info, value, ref, ref_to)
    local u = value - ref(to) -- put value between 0..slope_size
    local t = rlerp(   ref(info.slope.points[1]),    ref(info.slope.points[2]), u / TILE_SIZE)
    return     lerp(ref_to(info.slope.points[1]), ref_to(info.slope.points[2]), t)
end

-- given a tile, discover all the tiles of a slope
function slope_tiles(tile)
    local res = {}
    function loop(t)
        table.insert(res, t)
        for _, n in ipairs{ vec.v2(0, -1), vec.v2(0, 1),
                            vec.v2(-1, 0), vec.v2(1, 0) } do
            if is_slope(t+n) and same_slope(t+n, tile)
            and not find(res, t+n, vec.eq) then
                loop(t+n)
            end
        end
    end
    loop(tile)
    return res
end

function inside_slope(tile, box, count_line)
    local info   = info_of(tile)
    local dir    = bitsign(info.normals[1].y)
    local to     = t2p(tile - info.slope.origin)
    local center = box[1].x + (box[2].x - box[1].x)/2
    local yu     = slope_diag_point(to, info, center, vec.x, vec.y)
    local y      = to.y + yu * TILE_SIZE
    local fns    = count_line and { gteq, lteq } or { gt, lt }
    local lt     = fns[dir+1]
    return not lt(box[dir+1].y, y) and y or false
end

-- this constant represents the "border" where collisions register in tiles
local TILE_TOLLERANCE = 5
local SLOPE_TOLLERANCE = 2
local ENTITY_TOLLERANCE = 8

local HEIGHT_UP_HB = 16 -- keep high to make slopes work on high speed
local WIDTH_LR_HB = 5

-- collisions are first checked against these hitboxes, one for each cardinal direction
-- (plus two more for an edge-case with slopes...)
function generate_collision_hitboxes(hb, dz)
    return {
        {
            { vec.v2(hb[1].x            , hb[1].y + dz[1]), vec.v2(hb[1].x+WIDTH_LR_HB, hb[2].y - dz[1]) }, -- left
            { vec.v2(hb[2].x-WIDTH_LR_HB, hb[1].y + dz[1]), vec.v2(hb[2].x            , hb[2].y - dz[1]) }, -- right
        }, {
            { vec.v2(hb[1].x + dz[2], hb[1].y             ), vec.v2(hb[2].x - dz[2], hb[1].y+HEIGHT_UP_HB) }, -- up
            { vec.v2(hb[1].x + dz[2], hb[2].y-HEIGHT_UP_HB), vec.v2(hb[2].x - dz[2], hb[2].y             ) }, -- down
        }, {
            { vec.v2(hb[1].x  , hb[1].y), vec.v2(hb[1].x+1, hb[2].y) }, -- left, for slopes
            { vec.v2(hb[2].x-1, hb[1].y), vec.v2(hb[2].x  , hb[2].y) }, -- right, for slopes
        }
    }
end

local ENTITY = {
    PLAYER = 1,
    MOVING_PLATFORM = 2,
    BOULDER = 3,
}

-- constant data for entities
local entity_info = {
    [ENTITY.PLAYER] = {
        hitbox             = { vec.zero, vec.v2(TILE_SIZE, TILE_SIZE*2) },
        collision_hitboxes = generate_collision_hitboxes(
            { vec.zero, vec.v2(TILE_SIZE, TILE_SIZE*2) }, { TILE_TOLLERANCE, 4 }
        ),
        normals            = { vec.v2(-1, 0), vec.v2(1, 0) },
        draw_size          = vec.v2(TILE_SIZE, TILE_SIZE * 2),
    },
    [ENTITY.MOVING_PLATFORM] = {
        hitbox      = { vec.zero, vec.v2(3, 1) * TILE_SIZE },
        normals     = { vec.v2(0, -1), vec.v2(0, 1), vec.v2(1, 0), vec.v2(-1, 0) },
        draw_size   = vec.v2(3, 1) * TILE_SIZE,
        path_length = vec.v2(10, 0) * TILE_SIZE,
    },
    [ENTITY.BOULDER] = {
        hitbox             = { vec.zero, vec.v2(2, 2) * TILE_SIZE },
        collision_hitboxes = generate_collision_hitboxes(
            { vec.zero, vec.v2(2, 2) * TILE_SIZE }, { 5, 4 }
        ),
        normals            = { vec.v2(0, -1), vec.v2(0, 1), vec.v2(1, 0), vec.v2(-1, 0) },
        draw_size          = vec.v2(2, 2) * TILE_SIZE,
    },
}

function player(pos)
    return {
        type           = ENTITY.PLAYER,
        pos            = pos,
        old_pos        = pos,
        vel            = vec.zero,
        on_ground      = false,
        old_collisions = {},
        gravity_dir    = 1,
        coyote_time    = 0,
        jump_buf       = false,
    }
end

function moving_platform(pos, dir)
    return {
        type      = ENTITY.MOVING_PLATFORM,
        pos       = t2p(pos),
        old_pos   = t2p(pos),
        start_pos = t2p(pos),
        dir       = dir * TILE_SIZE,
        carrying  = {},
    }
end

function boulder(pos)
    return {
        type           = ENTITY.BOULDER,
        pos            = pos,
        old_pos        = pos,
        vel            = vec.zero,
        on_ground      = false,
        old_collisions = {},
        gravity_dir    = 1,
        carrying       = {},
    }
end

-- entities buffer, entity[1] is always the player
local entities = {
    player(vec.v2(SCREEN_WIDTH, SCREEN_HEIGHT) * TILE_SIZE / 2
         + vec.v2(TILE_SIZE/2 - 13 * TILE_SIZE, -8 * TILE_SIZE)),
    boulder(t2p(vec.v2(6, 7))),
    boulder(t2p(vec.v2(4, 7))),
    moving_platform(vec.v2(10, 7), vec.v2(6, 0)),
}

-- physics constant for the player

-- when choosing a cap, you'd probably want to know how many pixels
-- you're traveling each frame. the formulas are:
--
--  p = cap / fps, cap = p * fps
--
-- where is the pixels traveled each frame and fps is a target fps (i.e.
-- the minimum fps the game can have).
-- in practice, only caps with a p >= 16 get really problematic (as that's where
-- you start skipping tiles)
local VEL_X_CAP = 15*30
local VEL_Y_CAP = 15*30

-- acceleration is calculated by after how many tiles does the player reach
-- the velocity cap. formula: a = cap**2 / (2*s) (third equation of motion)
local ACCEL = VEL_X_CAP^2 / (2*7*TILE_SIZE)
local DECEL = 300
local GRAVITY = VEL_Y_CAP^2 / (2*10*TILE_SIZE)
-- used when pressing the jump button while falling
local SLOW_GRAVITY = VEL_Y_CAP^2 / (2*20*TILE_SIZE)

local JUMP_HEIGHT_MAX1 = 5 -- tiles
local JUMP_HEIGHT_MAX2 = 6 -- tiles, max height is interpolated between 1 and 2
local JUMP_HEIGHT_MIN  = 0.2 -- tiles
local JUMP_VEL_MIN = -math.sqrt(2 * GRAVITY * JUMP_HEIGHT_MIN * TILE_SIZE)
-- how many frames can you jump after falling from the ground?
local COYOTE_TIME_FRAMES = 10
-- how many pixels over the ground should a jump be registered?
local JUMP_BUF_WINDOW = 16
-- how many pixels over the ground should we check for slopes to stick on?
-- (fixes a problem where going downward slopes is erratic)
local SLOPE_ADHERENCE_WINDOW = 16
-- cap velocity to this value when pushing boulders
local VEL_BOULDER_CAP = 30

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
    tprint("dt = " .. tostring(dt))

    -- we first deal with changing position of carried entities.
    -- an entity may carry 1+ entities which may carry 1+ entities...
    -- this forms a tree. walk it to setup carried entities position correctly
    function carry_entities(ids, movement)
        if vec.eq(movement, vec.zero) then
            return
        end
        for _, id in ipairs(ids) do
            entities[id].pos = entities[id].pos + movement
            if entities[id].carrying ~= nil then
                carry_entities(entities[id].carrying, movement)
            end
        end
    end

    -- save current positions so old_pos may be updated correctly
    local old_positions = map(function (e) return e.pos end, entities)
    for id, entity in ipairs(entities) do
        if entity.type == ENTITY.MOVING_PLATFORM or entity.type == ENTITY.BOULDER then
            carry_entities(entity.carrying, entity.pos - entity.old_pos)
            entity.carrying = {}
        end
        entity.old_pos = old_positions[id]
    end

    -- compute new carried entities
    for id, entity in ipairs(entities) do
        if entity.type == ENTITY.BOULDER or entity.type == ENTITY.PLAYER then
            for _, c in ipairs(entity.old_collisions) do
                if c.entity_id and entities[c.entity_id].carrying ~= nil
                and vec.eq(c.dir, vec.v2(0, entity.gravity_dir)) then
                    table.insert(entities[c.entity_id].carrying, id)
                end
            end
        end
    end

    -- step all entities in this loop
    for id, entity in ipairs(entities) do
        local info = entity_info[entity.type]
        if entity.type == ENTITY.MOVING_PLATFORM then
            entity.pos = entity.pos + entity.dir * dt
            -- handle direction change
            for _, axis in ipairs{1,2} do
                if math.abs(vec.ref(entity.pos, axis) - vec.ref(entity.start_pos, axis)) >= vec.ref(info.path_length, axis) then
                    entity.start_pos = vec.set(entity.start_pos, axis, vec.ref(entity.start_pos, axis)
                                     + vec.ref(info.path_length, axis) * sign(vec.ref(entity.dir, axis)))
                    entity.dir = vec.set(entity.dir, axis, -vec.ref(entity.dir, axis))
                end
            end
        elseif entity.type == ENTITY.BOULDER then
            entity.vel = entity.vel + vec.v2(0, GRAVITY) * dt
            entity.vel.y = clamp(entity.vel.y, -VEL_Y_CAP, VEL_Y_CAP)
            entity.pos = entity.pos + entity.vel * dt
        elseif entity.type == ENTITY.PLAYER then
            if rl.IsKeyReleased(rl.KEY_R) then
                entity.gravity_dir = -entity.gravity_dir
            end

            local accel_hor = (rl.IsKeyDown(rl.KEY_LEFT)  and -ACCEL or 0)
                            + (rl.IsKeyDown(rl.KEY_RIGHT) and  ACCEL or 0)
            local decel_hor = entity.vel.x > 0 and -DECEL
                           or entity.vel.x < 0 and  DECEL
                           or 0
            local gravity = rl.IsKeyDown(rl.KEY_Z) and not entity.on_ground and sign(entity.vel.y) == gravity_dir
                        and SLOW_GRAVITY or GRAVITY
            gravity = gravity * entity.gravity_dir
            local accel = vec.v2(accel_hor + decel_hor, gravity)

            -- we use semi-implicit euler integration: https://gafferongames.com/post/integration_basics
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
                entity.vel.y = jump_vel * entity.gravity_dir
                entity.jump_buf = false
            end

            -- when jumping, if the player stops pressing the jump key, change
            -- his velocity to simulate variable jump height
            if not rl.IsKeyDown(rl.KEY_Z) and not entity.on_ground
               and (entity.gravity_dir > 0 and entity.vel.y < JUMP_VEL_MIN * entity.gravity_dir
                 or entity.gravity_dir < 0 and entity.vel.y > JUMP_VEL_MIN * entity.gravity_dir) then
                entity.vel.y = JUMP_VEL_MIN * entity.gravity_dir
            end

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

    function get_hitboxes(hitbox, from)
        return map(function (axis)
            return map(function (dir)
                return map(function (p) return hitbox[1] + p end, dir)
            end, axis)
        end, from)
    end

    function mkcoll(point, axis, side, tile, entity_id)
        return {
            point = point,
            dir = vec.set(vec.zero, axis+1, side == 0 and -1 or 1),
            tile = tile,
            entity_id = entity_id
        }
    end

    -- gets all tiles under box that aren't air. `fn` is called for additional checks.
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
    function box_collision(a, old_a, b, old_b, axis, side_a, normals, toll)
        local normal = vec.set(vec.zero, axis+1, side_a == 0 and 1 or -1)
        local ref = axis == 0 and vec.x or vec.y
        local a_dir = a[1] - old_a[1]
        local b_dir = b[1] - old_b[1]
        if not find(normals, normal, vec.eq)
        or vec.dot(a_dir, normal) >= 0 and ref(a_dir) ~= 0
           and math.abs(ref(a_dir)) >= math.abs(ref(b_dir)) then
            return nil
        end
        local side_b = flip(side_a)
        local ap = ref(old_a[side_a+1])
        local bp = ref(    b[side_b+1])
        local lteq = side_a == 0 and gteq or lteq
        local toll = toll * (side_b == 0 and 1 or -1)
        return lteq(ap, bp + toll) and bp or nil
    end

    function collide_tiles(hitbox, old_hitbox, boxes, axis, side, on_ground)
        local tiles = get_tiles(boxes[axis+1][side+1], identity)
        -- edge-case with computing slope movement on x axis
        if axis == 0 and boxes[3] ~= nil then
            tiles = append(tiles, get_tiles(boxes[3][side+1], is_slope))
        end
        if #tiles == 0 then
            return {}
        end
        local size = hitbox[2] - hitbox[1]

        -- ignore tiles adjacent to a slope in certain conditions
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
                   and side == bitsign(info.normals[1].y)
                   and find(slopes, t, vec.eq)
            end
            return check(tile + vec.v2(-1, 0), -1)
                or check(tile + vec.v2( 1, 0),  1)
        end

        function tile_collision(tile)
            local hb = aabb(t2p(tile), vec.one * TILE_SIZE - vec.one)
            local p  = box_collision(hitbox, old_hitbox, hb, hb, axis, side, info_of(tile).normals, TILE_TOLLERANCE)
            return p ~= nil and mkcoll(p, axis, side, tile) or nil
        end

        function slope_collision_y(slopes)
            function get(tile)
                local info = info_of(tile)
                local dir = bitsign(info.normals[1].y)
                if dir ~= side or vec.dot(hitbox[1] - old_hitbox[1], info.normals[1]) >= 0 then
                    return {}
                end
                local to = t2p(tile - info.slope.origin)
                local yu = slope_diag_point(to, info, hitbox[1].x + size.x/2, vec.x, vec.y)
                if lteq(yu, 0) or gteq(yu, info.slope.size.y) then
                    return {}
                end
                local y = to.y + yu * TILE_SIZE
                local old_yu = slope_diag_point(to, info, old_hitbox[1].x + size.x/2, vec.x, vec.y)
                local old_y  = to.y + old_yu * TILE_SIZE
                local toll = SLOPE_TOLLERANCE * -sign(info.normals[1].y)
                -- always collide if we were on a slope earlier (fixes a bug with going up slopes),
                -- otherwise compute collision just like box_collision
                local was_on_slope = (lteq(old_yu, 0) or gteq(old_yu, info.slope.size.y)) and on_ground
                local lteq = dir == 0 and gteq or lteq
                if (was_on_slope or lteq(old_hitbox[dir+1].y, old_y + toll))
                and not lteq(hitbox[dir+1].y, y) then
                    return { mkcoll(y, axis, side, tile) }
                end
                return {}
            end
            return #slopes > 0 and get(slopes[1]) or {}
        end

        function slope_collision_x(slopes)
            function all_eq(t)
                return #t == 0 or not findf(function (v)
                    return not vec.eq(v, t[1])
                end, t)
            end

            if #slopes < 2 then
                return {}
            end
            slopes = filter(function (t)
                local neighbor = t + vec.v2(side == 0 and 1 or -1, 0)
                -- ignore slopes not pointing against the direction we're checking
                return side == bitsign(info_of(t).normals[1].x)
                -- and those slopes that extend for 2+ tiles horizontally
                   and not (is_slope(neighbor) and same_slope(t, neighbor))
            end, slopes)
            local origs = map(function (s) return s - info_of(s).slope.origin end, slopes)
            if #origs < 2 or all_eq(origs) then
                return {}
            end
            -- compute collision as if it was a wall
            local old_center = old_hitbox[1].x + size.x/2
            local center     =     hitbox[1].x + size.x/2
            local tp = t2p(slopes[1]).x
            local p = tp + flip(side) * TILE_SIZE
            local lteq = side == 0 and gteq or lteq
            local toll = SLOPE_TOLLERANCE * -sign(info_of(slopes[1]).normals[1].x)
            return lteq(old_center, p+toll) and not lteq(center, p)
               and map(function (s) return mkcoll(tp + size.x/2, axis, side, s) end, slopes)
               or  {}
        end

        local all_slopes, all_tiles = partition(is_slope, tiles)
        -- we only care about slopes on the entity's center
        local slopes = filter(function (t) return t.x == p2t(hitbox[1] + size/2).x end, all_slopes)
        local tiles  = filter(function (t) return not ignore_tile(t, slopes) end, all_tiles)
        local points = map(tile_collision, tiles)
        points = append(points, axis == 0 and slope_collision_x(slopes)
                                          or  slope_collision_y(slopes))
        return filter(function (v) return v ~= nil end, points)
    end

    -- gets each entity that might collide with an entity of specified id.
    -- it's a dumb loop over every entity. this is where one could use
    -- something smarter, e.g. quadtrees
    function get_entities(entity_id, box)
        local r = rec(box[1], box[2] - box[1])
        return filter(function (id)
            local entity = entities[id]
            local info = entity_info[entity.type]
            return entity_id ~= id
               and rl.CheckCollisionRecs(r, rec(entity.pos, info.hitbox[2] - info.hitbox[1]))
        end, map(function (_, id) return id end, entities))
    end

    -- at a high level, collision detection and resolution is done by checking
    -- the collision box associated with each cardinal direction, getting points
    -- from everything that collides with it. the "lowest" point wins and is applied
    -- to the position instantly.
    -- "weak" collisions, i.e. collisions that do not result in a moving
    -- positition, are also computed
    function resolve_collisions(entity_id, pos, old_pos, hitbox_unit, collision_boxes)
        local size = hitbox_unit[2] - hitbox_unit[1]
        local collisions = {}
        local weak_collisions = {}
        for axis = 0, 1 do
            function do_collision(get_points)
                for side = 0, 1 do
                    local old_hitbox = map(function (v) return v + old_pos end, hitbox_unit)
                    local     hitbox = map(function (v) return v +     pos end, hitbox_unit)
                    local boxes = get_hitboxes(hitbox, collision_boxes)
                    local points, weaks = get_points(side, hitbox, old_hitbox, boxes)
                    weak_collisions = append(weak_collisions, weaks)
                    if #points > 0 then
                        local minf = side == 0 and maxf or minf
                        local min_point = minf(function (p) return p.point end, points)
                        pos = vec.set(pos, axis+1, min_point
                                                     - vec.ref(size, axis+1) * side
                                                     - vec.ref(hitbox_unit[1], axis+1))
                        collisions = append(collisions, filter(function (p) return p.point == min_point end, points))
                    end
                end
            end

            function entity_collision(pred)
                return function (side, hitbox, old_hitbox, boxes)
                    local weak_collisions = {}
                    local points = {}
                    local ids = get_entities(entity_id, boxes[axis+1][side+1])

                    function should_collide(a, b, old_hitbox)
                        if axis == 1 then
                            return true
                        end
                        local adir = a.pos.x - a.old_pos.x
                        local bdir = b.pos.x - b.old_pos.x
                        if b.type == ENTITY.MOVING_PLATFORM then
                            -- if collision resolution put something inside a platform,
                            -- make sure it stops trying to collide with it
                            local info = entity_info[b.type]
                            local r1 = rec(old_hitbox[1], old_hitbox[2] - old_hitbox[1])
                            local r2 = rec(b.old_pos, info.hitbox[2] - info.hitbox[1])
                            return not rl.CheckCollisionRecs(r1, r2)
                        end
                        local tmp = side == 0 and -1 or 1
                            -- if you're not moving and you're on the ground, you get pushed
                        return (sign(adir) == 0 and sign(bdir) ~= 0 and b.on_ground and a.on_ground)
                            -- if you're moving, you can only push if the other is on the ground
                            or (sign(adir) ~= 0 and (not b.on_ground or sign(bdir) == 0 and not a.on_ground))
                            -- weird edge-case to make pushing 2+ boulders simultaneously work
                            or (findf(function (c) return vec.eq(c.dir, vec.v2(tmp, 0)) end, b.old_collisions))
                            -- if two entities are pushing against each other, the faster wins (theoretically)
                            or (sign(adir) == -sign(bdir) and adir > bdir)
                    end

                    for _, id in ipairs(filter(function (id) return pred(id, entities[id]) end, ids)) do
                        local entity = entities[id]
                        local info = entity_info[entity.type]

                        if should_collide(entities[entity_id], entity, old_hitbox) then
                            local p = box_collision(
                                hitbox, old_hitbox,
                                aabb(entity.pos,     info.hitbox[2] - info.hitbox[1]),
                                aabb(entity.old_pos, info.hitbox[2] - info.hitbox[1]),
                                axis, side, info.normals, ENTITY_TOLLERANCE
                            )
                            if p ~= nil then
                                local dir = vec.set(vec.zero, axis+1, side == 0 and -1 or 1)
                                table.insert(points, mkcoll(p, axis, side, nil, id))
                            end
                        else
                            local dir = vec.set(vec.zero, axis+1, side == 0 and -1 or 1)
                            table.insert(weak_collisions, { entity_id = id, dir = dir })
                        end
                    end
                    return points, weak_collisions
                end
            end

            -- priority system! the ground is always prioritized first, others
            -- are a combination of what felt right to me
            do_collision(entity_collision(function (id, e) return e.type == ENTITY.MOVING_PLATFORM end))
            do_collision(entity_collision(function (id, e) return e.type ~= ENTITY.MOVING_PLATFORM and (e.pos - e.old_pos).x ~= 0 end))
            do_collision(entity_collision(function (id, e) return e.type ~= ENTITY.MOVING_PLATFORM and (e.pos - e.old_pos).x == 0 end))
            do_collision(function (side, hitbox, old_hitbox, boxes)
                return collide_tiles(hitbox, old_hitbox, boxes, axis, side, entities[entity_id].on_ground), {}
            end)
        end
        return pos, collisions, weak_collisions
    end

    local calculated_vel = entities[1].vel -- used only for drawing

    -- resolve collision for entities that collide with ground
    entities = map(function (_entity, id)
        local entity = copy_table(_entity)
        local info = entity_info[entity.type]
        if entity.type == ENTITY.BOULDER or entity.type == ENTITY.PLAYER then
            local pos, collisions, weak_collisions = resolve_collisions(
                id, entity.pos, entity.old_pos, info.hitbox, info.collision_hitboxes
            )
            entity.pos = pos

            -- setup ground flag so it behaves well with gravity
            local old_on_ground = entity.on_ground
            entity.on_ground = findf(function (v)
                return vec.eq(v.dir, vec.v2(0, entity.gravity_dir))
            end, collisions) and true or false

            function just_fallen()
                return old_on_ground and not entity.on_ground and sign(entity.vel.y) == entity.gravity_dir
            end

            -- slope adherence: makes sure the entity stays on slopes when going down
            if just_fallen() and not findf(function (c) return c.entity_id end, entity.old_collisions) then
                function make_box(x, ya, yb)
                    return { vec.v2(x, math.min(ya, yb)), vec.v2(x, math.max(ya, yb)) }
                end
                local hitbox = map(function (v) return v + entity.pos end, info.hitbox)
                local xdir   = sign(entity.pos.x - entity.old_pos.x)
                local center = hitbox[1] + (hitbox[2] - hitbox[1]) / 2
                local side   = entity.gravity_dir == 1 and 1 or 0
                local box    = make_box(center.x, hitbox[side+1].y, hitbox[side+1].y + SLOPE_ADHERENCE_WINDOW * entity.gravity_dir)
                local tiles  = get_tiles(box, function (t) return is_slope_facing(t, xdir) end)
                if #tiles > 0 then
                    local y = inside_slope(tiles[1], box)
                    if y then
                        entity.pos.y = y - info.hitbox[2].y * side
                        entity.on_ground = true
                        table.insert(collisions, mkcoll(entity.pos.y, 1, entity.gravity_dir, tiles[1]))
                    end
                end
            end

            -- when colliding in some axis, reset velocity to 0
            for _, axis in ipairs{ 0, 1 } do
                if findf(function (v)
                    local d = vec.ref(v.dir, axis+1)
                    -- make sure the entity isn't blocked when pushed from behind
                    return d ~= 0 and sign(d) == sign(vec.ref(entity.vel, axis+1))
                end, collisions) then
                    entity.vel = vec.set(entity.vel, axis+1, 0)
                end
            end

            -- change velocity when pushing stuff
            if math.abs(entity.vel.x) > VEL_BOULDER_CAP and findf(function (c)
                return c.dir.x ~= 0 and entities[c.entity_id].type ~= ENTITY.MOVING_PLATFORM
            end, weak_collisions) then
                entity.vel.x = clamp(entity.vel.x, -VEL_BOULDER_CAP, VEL_BOULDER_CAP)
            end

            entity.old_collisions = collisions

            if entity.type == ENTITY.PLAYER then
                entity.coyote_time = just_fallen() and COYOTE_TIME_FRAMES
                                or entity.on_ground and 0
                                or math.max(0, entity.coyote_time - 1)

                if rl.IsKeyPressed(rl.KEY_Z) and not entity.on_ground and sign(entity.vel.y) == entity.gravity_dir then
                    local hitbox = map(function (v) return v + entity.pos end, info.hitbox)
                    local hitboxes = get_hitboxes(hitbox, info.collision_hitboxes)
                    local side = entity.gravity_dir == 1 and 1 or 0
                    local h = map(function (v)
                        return v + vec.v2(0, JUMP_BUF_WINDOW * entity.gravity_dir)
                    end, hitboxes[2][side+1])
                    if #get_tiles(h, identity) > 0 then
                        entity.jump_buf = true
                    end
                end

                tprint("on ground = " .. tostring(entity.on_ground))
                tprint("old ground = " .. tostring(old_on_ground))
                tprint("pos (adjusted) = " .. tostring(entity.pos))
                tprint("vel (adjusted) = " .. tostring(entity.vel))
                tprint("coyote = " .. tostring(entity.coyote_time))
                tprint("jump buf = " .. tostring(entity.jump_buf))
            end
        end
        return entity
    end, entities)

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
                    end, entities[1].old_collisions) and rl.RED or rl.WHITE
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
                    end, entities[1].old_collisions) and rl.RED or rl.WHITE
                    local points = map(function (p) return orig + p * TILE_SIZE end, info.slope.points)
                    rl.DrawTriangle(points[1], points[2], points[3], color)
                end
            end
        end
    end

    for _, entity in ipairs(entities) do
        local info = entity_info[entity.type]
        if entity.type == ENTITY.MOVING_PLATFORM then
            rl.DrawRectangleRec(rec(entity.pos, info.draw_size), rl.YELLOW)
        elseif entity.type == ENTITY.BOULDER then
            rl.DrawRectangleRec(rec(entity.pos, info.draw_size), rl.GRAY)
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
