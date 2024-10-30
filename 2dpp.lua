local ffi = require "ffi"
local fmt = require "fmt"

local vec = {}

vec.one  = rl.new("Vector2", 1, 1)
vec.zero = rl.new("Vector2", 0, 0)
vec.huge = rl.new("Vector2", math.huge, math.huge)

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

local rec = {}

function rec.new(pos, size)
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
function clamp(x, min, max) return rl.Clamp(x, min, max) end
function lerp(a, b, t) return rl.Lerp(a, b, t) end
function rlerp(a, b, v) return rl.Normalize(v, a, b) end

function findf(proc, t)
    for _, v in ipairs(t) do
        if proc(v) then
            return v
        end
    end
    return false
end

function index_of(t, value, comp)
    for i, v in ipairs(t) do
        if comp ~= nil and comp(value, v) or value == v then
            return i
        end
    end
    return false
end

function map(fn, t)
    local r = {}
    for _, v in pairs(t) do
        table.insert(r, fn(v))
    end
    return r
end

function filter(pred, t)
    local r = {}
    for _, v in ipairs(t) do
        if pred(v) then
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
    if #t == 0 then
        return true
    end
    for i = 2, #t do
        if not vec.eq(t[i], t[1]) then
            return false
        end
    end
    return true
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

function get_normal(a, b)
    -- assumes a and b are in counter-clockwise order
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

function are_same_slope(t, n)
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
            and not index_of(res, t+n, vec.eq) then
                loop(t+n)
            end
        end
    end
    loop(t)
    return res
end

local player = {
    pos           = vec.v2(SCREEN_WIDTH, SCREEN_HEIGHT) * TILE_SIZE / 2
                  + vec.v2(TILE_SIZE/2 - 8 * TILE_SIZE, -8 * TILE_SIZE),
    vel           = vec.zero,
    on_ground     = false,
    coyote_time   = 0,
    jump_buf      = false,
    slope_dir     = 0,
    platforms_standing = {}
}

local PLAYER_DRAW_SIZE = vec.v2(TILE_SIZE, TILE_SIZE * 2)
local PLAYER_HITBOX = { vec.v2(0, 0), vec.v2(TILE_SIZE-0, TILE_SIZE*2) }

local PLAYER_COLLISION_HITBOXES = {
    {
        { vec.v2( 0,  6), vec.v2( 1, 26) }, -- left
        { vec.v2(15,  6), vec.v2(16, 26) }, -- right
    }, {
        { vec.v2( 4,  0), vec.v2(11, 10) }, -- up
        { vec.v2( 4, 22), vec.v2(11, 32) }, -- down
    }, {
        { vec.v2( 0,  0), vec.v2( 1, 31) }, -- left
        { vec.v2(15,  0), vec.v2(16, 31) }, -- right
    }
}

-- tiles have a "border" where collisions register. this constant controls how big it is
local TILE_TOLLERANCE = 5
local SLOPE_TOLLERANCE = 2

-- physics constant for the player, change these to control the "feel" of the game

local ACCEL = 700
local DECEL = 300

-- the cap is in tiles, but you'd probably want to know how many pixels
-- you're traveling each frame. the formula is dependent on FPS, so set a
-- maximum target FPS, then use p = cap * (1/fps). if you'd like to know the cap
-- from a set pixels, reverse the formula: cap = p/(1/fps)
-- this is especially important for the y cap: the result of the above formula
-- should stay lower than the dead zone on the x axis.
-- the tile tollerance plays a factor on this too. put your cap too high, and
-- you might notice the player getting inside tiles at high speed.

-- i've found x velocity can be really large. only when p >= 16 it starts being
-- problematic. might be more problematic for slopes.
local VEL_X_CAP = 40 * TILE_SIZE -- i've found this one can be really large.
local VEL_Y_CAP = 22 * TILE_SIZE -- just under 6 pixels at 60 FPS
local GRAVITY = 400
-- used when pressing the jump button while falling
local SLOW_GRAVITY = 300
local JUMP_HEIGHT_MAX1 = 5 -- tiles
local JUMP_HEIGHT_MAX2 = 6 -- tiles, max height is interpolated between 1 and 2
local JUMP_HEIGHT_MIN  = 0.2 -- tiles
local COYOTE_TIME_FRAMES = 10
-- how many pixels over the ground should a jump be registered?
local JUMP_BUF_WINDOW = 16
-- when going on slopes downwards, y velocity is set so that the player stays
-- on the slope. angle controls the angle the velocity makes, while speed start
-- controls the initial speed when the player falls down a slope, into the air.
local SLOPE_DOWN_ANGLE = 65
local SLOPE_DOWN_SPEED_START = 100

local JUMP_VEL_MIN = -math.sqrt(2 * GRAVITY * JUMP_HEIGHT_MIN * TILE_SIZE)

local ENTITY_MOVING_PLATFORM = 1
local ENTITY_BOULDER = 2

function generate_collision_hitboxes(size)
    return {
        {
            { vec.v2(       0,        0), vec.v2(     1, size.y) },
            { vec.v2(size.x-1,        0), vec.v2(size.x, size.y) },
        }, {
            { vec.v2(       0,        0), vec.v2(size.x,      1) },
            { vec.v2(       0, size.y-1), vec.v2(size.x, size.y) },
        }
    }
end

-- store here entities such as moving platforms and boulders
local entity_info = {
    [ENTITY_MOVING_PLATFORM] = {
        -- normals = { vec.v2(0, -1) },
        normals = { vec.v2(0, -1), vec.v2(0, 1), vec.v2(1, 0), vec.v2(-1, 0) },
        size = vec.v2(3, 1) * TILE_SIZE,
        path_length = vec.v2(10, 0) * TILE_SIZE
    },
    [ENTITY_BOULDER] = {
        size = vec.v2(2, 2) * TILE_SIZE,
        normals = { vec.v2(0, -1), vec.v2(0, 1), vec.v2(1, 0), vec.v2(-1, 0) },
        collision_hitboxes = generate_collision_hitboxes(vec.v2(2, 2) * TILE_SIZE)
    },
}

local entities = {
    {
        type = ENTITY_MOVING_PLATFORM,
        start_pos = t2p(vec.v2(1, 5)),
        pos = t2p(vec.v2(1, 5)),
        old_pos = t2p(vec.v2(1, 5)),
        dir = vec.v2(6, 0) * TILE_SIZE
    },
    {
        type = ENTITY_BOULDER,
        old_pos = t2p(vec.v2(4, 0)),
        pos = t2p(vec.v2(4, 0)),
        vel = vec.v2(0, 0)
    }
}

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

    -- handle entities first
    for id, entity in ipairs(entities) do
        local info = entity_info[entity.type]
        if entity.type == ENTITY_MOVING_PLATFORM then
            entity.old_pos = entity.pos
            entity.pos = entity.pos + entity.dir * dt
            if index_of(player.platforms_standing, id) then
                player.pos = player.pos + (entity.pos - entity.old_pos)
            end
            for _, axis in ipairs{1,2} do
                if math.abs(vec.dim(entity.pos, axis) - vec.dim(entity.start_pos, axis)) >= vec.dim(info.path_length, axis) then
                    entity.start_pos = vec.set_dim(entity.start_pos, axis, vec.dim(entity.start_pos, axis)
                                     + vec.dim(info.path_length, axis) * sign(vec.dim(entity.dir, axis)))
                    entity.dir = vec.set_dim(entity.dir, axis, -vec.dim(entity.dir, axis))
                end
            end
        elseif entity.type == ENTITY_BOULDER then
            entity.vel = entity.vel + vec.v2(0, GRAVITY) * dt
            entity.pos = entity.pos + entity.vel * dt
        end
    end

    if rl.IsKeyReleased(rl.KEY_R) then
        gravity_dir = -gravity_dir
    end

    -- player physics
    local accel_hor = (rl.IsKeyDown(rl.KEY_LEFT)  and -ACCEL or 0)
                    + (rl.IsKeyDown(rl.KEY_RIGHT) and  ACCEL or 0)
    local decel_hor = player.vel.x > 0 and -DECEL
                   or player.vel.x < 0 and  DECEL
                   or 0
    local gravity = rl.IsKeyDown(rl.KEY_Z) and not player.on_ground and player.vel.y > 0
                and SLOW_GRAVITY or GRAVITY
    gravity = gravity * gravity_dir
    local accel = vec.v2(accel_hor + decel_hor, gravity)

    player.vel = player.vel + accel * dt
    player.vel.x = clamp(player.vel.x, -VEL_X_CAP, VEL_X_CAP)
    if math.abs(player.vel.x) < 4 then
        player.vel.x = 0
    end
    player.vel.y = clamp(player.vel.y, -VEL_Y_CAP, VEL_Y_CAP)
    if player.slope_dir ~= 0 and sign(player.vel.x) == player.slope_dir then
        -- likely would be better using vel.x * tan(some_angle), but still fine
        -- player.vel.y = VEL_Y_CAP * gravity_dir
        player.vel.y = math.min(math.abs(player.vel.x) * math.tan(math.rad(SLOPE_DOWN_ANGLE)), VEL_Y_CAP) * gravity_dir
    end

    -- jump control
    if (rl.IsKeyPressed(rl.KEY_Z) or player.jump_buf) and (player.on_ground or player.coyote_time > 0) then
        local h = lerp(JUMP_HEIGHT_MAX1, JUMP_HEIGHT_MAX2, math.abs(player.vel.x / VEL_X_CAP))
        local jump_vel = -math.sqrt(2 * GRAVITY * h * TILE_SIZE)
        player.vel.y = jump_vel * gravity_dir
        player.jump_buf = false
    end

    -- when jumping, if the player stops pressing the jump key, quickly change
    -- his velocity to simulate variable jump height
    if not rl.IsKeyDown(rl.KEY_Z) and not player.on_ground
       and (gravity_dir > 0 and player.vel.y < JUMP_VEL_MIN * gravity_dir
         or gravity_dir < 0 and player.vel.y > JUMP_VEL_MIN * gravity_dir) then
        player.vel.y = JUMP_VEL_MIN * gravity_dir
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

    function get_hitboxes(hitbox, from)
        return map(function (axis)
            return map(function (dir)
                return map(function (p) return hitbox[1] + p end, dir)
            end, axis)
        end, from)
    end

    function box_collision(hb, old_hb, axis, move, box, normals)
        local normal = vec.set_dim(vec.zero, axis+1, move == 0 and 1 or -1)
        local box_size = box[2] - box[1]
        if not index_of(normals, normal, vec.eq)
        or vec.dot(hb[1] - old_hb[1], normal) >= 0 then
            return math.huge
        end
        local side  = move == 0 and 1 or 0
        local lteq  = move == 0 and gteq or lteq
        local old_p = vec.dim(old_hb[move+1], axis+1)
        local box_p = vec.dim(   box[side+1], axis+1)
        return lteq(old_p, box_p + TILE_TOLLERANCE * -vec.dim(normal, axis+1))
           and box_p
           or  math.huge
    end

    function collide_tiles(hitbox, old_hitbox, boxes, size, axis, move)
        local direction = vec.normalize(hitbox[1] - old_hitbox[1])
        local dim = axis == 0 and vec.x or vec.y
        local tiles = get_tiles(boxes[axis+1][move+1], identity)
        if axis == 0 and boxes[3] ~= nil then
            tiles = append(tiles, get_tiles(boxes[3][move+1], is_slope))
        end
        if #tiles == 0 then
            return {}, {}
        end

        function is_over_slope(tile)
            local info  = info_of(tile)
            local dir   = b2i(info.normals[1].y < 0)
            local to    = t2p(tile - info.slope.origin)
            local yu    = slope_diag_point(
                to, info, old_hitbox[1].x + size.x/2, vec.x, vec.y)
            local y     = to.y + yu * TILE_SIZE
            local lteq = dir == 0 and gteq or lteq
            return lteq(old_hitbox[dir+1].y, y)
        end

        function ignore_tile(tile, slopes)
            if axis == 0 then
                local side = move == 0 and -1 or 1
                return is_slope_facing(tile + vec.v2(-side, 0), -side)
                   and is_over_slope(tile + vec.v2(-side, 0))
            end
            function check(t, sgn)
                local info = info_of(t)
                return is_slope(t, sgn)
                   and sign(info.normals[1].x) == sgn
                   and index_of(slopes, t, vec.eq)
                   and move == b2i(info.normals[1].y < 0)
            end
            return check(tile + vec.v2(-1, 0), -1)
                or check(tile + vec.v2( 1, 0),  1)
        end

        function get_tile_dim(tile)
            local pos = t2p(tile)
            local tile_hitbox = { pos, pos + vec.v2(TILE_SIZE, TILE_SIZE) }
            return box_collision(
                hitbox, old_hitbox, axis, move, tile_hitbox, info_of(tile).normals
            )
        end

        function get_slope_dim(tile)
            local info = info_of(tile)
            local dir = b2i(info.normals[1].y < 0)
            if dir ~= move or vec.dot(direction, info.normals[1]) >= 0 then
                return math.huge
            end
            local to    = t2p(tile - info.slope.origin)
            local y     = slope_diag_point_y(to, info,     hitbox[1].x + size.x/2)
            local old_y = slope_diag_point_y(to, info, old_hitbox[1].x + size.x/2)
            if y == math.huge then
                return math.huge
            end
            -- check if the player is inside the slope
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
                local neighbor = t + vec.v2(move == 0 and 1 or -1, 0)
                return b2i(info_of(t).normals[1].x < 0) == move
                   and not (is_slope(neighbor) and are_same_slope(t, neighbor))
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
            local p = tp + (move == 0 and TILE_SIZE or 0)
            local lteq = move == 0 and gteq or lteq
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
        local dir = vec.set_dim(vec.zero, axis+1, move == 0 and -1 or 1)
        local result = {}
        for _, ts in ipairs({tiles, slopes}) do
            for _, t in ipairs(ts) do
                table.insert(result, { tile = t, dir = dir })
            end
        end
        return points, result
    end

    function player_collision(pos, old_pos, hitbox_unit, collision_boxes, entity_id)
        local size = hitbox_unit[2] - hitbox_unit[1]
        local result = {}
        for axis = 0, 1 do
            for move = 0, 1 do
                local old_hitbox = map(function (v) return v + old_pos end, hitbox_unit)
                local hitbox = map(function (v) return v + pos end, hitbox_unit)
                local boxes = get_hitboxes(hitbox, collision_boxes)

                local points = {}

                -- collision with entities
                for id, entity in ipairs(entities) do
                    local info = entity_info[entity.type]
                    if entity_id ~= id then
                        if entity.type == ENTITY_MOVING_PLATFORM then
                            if rl.CheckCollisionRecs(
                                rec.new(entity.pos, info.size),
                                rec.new(hitbox[1], hitbox[2] - hitbox[1])
                            ) then
                                local p = box_collision(
                                    hitbox, old_hitbox, axis, move,
                                    { entity.pos, entity.pos + info.size },
                                    info.normals
                                )
                                if p ~= math.huge then
                                    local dir = vec.set_dim(vec.zero, axis+1, move == 0 and -1 or 1)
                                    table.insert(points, p)
                                    table.insert(result, { entity_id = id, dir = dir })
                                end
                            end
                        elseif entity.type == ENTITY_BOULDER then
                            if rl.CheckCollisionRecs(
                                rec.new(entity.pos, info.size),
                                rec.new(hitbox[1], hitbox[2] - hitbox[1])
                            ) then
                                local p = box_collision(
                                    hitbox, old_hitbox, axis, move,
                                    { entity.pos, entity.pos + info.size },
                                    info.normals
                                )
                                if p ~= math.huge then
                                    local dir = vec.set_dim(vec.zero, axis+1, move == 0 and -1 or 1)
                                    table.insert(points, p)
                                    table.insert(result, { entity_id = id, dir = dir })
                                end
                            end
                        end
                    end
                end

                -- collision with tiles
                local ps, res = collide_tiles(hitbox, old_hitbox, boxes, size, axis, move)
                points = append(points, ps)
                if #points > 0 then
                    local minf = move == 0 and maxf or minf
                    local p = minf(identity, points)
                    local dim = axis == 0 and vec.x or vec.y
                    pos = vec.set_dim(pos, axis+1, p - dim(size) * move)
                    result = append(result, res)
                end
            end
        end
        return pos, result
    end

    -- first handle entities that collide with ground
    for id, entity in ipairs(entities) do
        local info = entity_info[entity.type]
        if entity.type == ENTITY_BOULDER then
            pos, collisions = player_collision(
                entity.pos, entity.old_pos, { vec.zero, info.size },
                info.collision_hitboxes, id
            )
            entity.pos = pos
            for _, axis in ipairs{ 0, 1 } do
                if findf(function (v) return vec.dim(v.dir, axis+1) ~= 0 end, collisions) then
                    entity.vel = vec.set_dim(entity.vel, axis+1, 0)
                end
            end
        end
    end

    local pos, collision_tiles = player_collision(
        player.pos, old_pos, PLAYER_HITBOX, PLAYER_COLLISION_HITBOXES
    )
    tprint(fmt.tostring("collision tiles = ", collision_tiles))

    player.pos = pos
    tprint("pos (adjusted) = " .. tostring(player.pos))

    -- setup ground flag so it behaves well with gravity
    local old_on_ground = player.on_ground
    player.on_ground = findf(function (v)
        return vec.eq(v.dir, vec.v2(0, gravity_dir))
    end, collision_tiles)
        and true or false
    tprint("on ground = " .. tostring(player.on_ground))
    tprint("old ground = " .. tostring(old_on_ground))

    -- going downwards a slope, then into the air, creates a frame where
    -- the player is going down with lots of speed
    -- this code tries to physically fix it by undoing earlier calculations
    if  old_on_ground and not player.on_ground and sign(player.vel.y) == gravity_dir
    and player.slope_dir ~= 0 and sign(player.vel.x) == player.slope_dir then
        player.pos.y = player.pos.y - math.min(math.abs(player.vel.x) * math.tan(math.rad(SLOPE_DOWN_ANGLE)), VEL_Y_CAP) * gravity_dir * dt
        player.vel.y = SLOPE_DOWN_SPEED_START
    end

    local calculated_vel = player.vel -- used only for drawing
    for _, axis in ipairs{ 0, 1 } do
        if findf(function (v) return vec.dim(v.dir, axis+1) ~= 0 end, collision_tiles) then
            player.vel = vec.set_dim(player.vel, axis+1, 0)
        end
    end

    local collided_slope = findf(function (v)
        return v.tile ~= nil and is_slope(v.tile) and vec.dim(v.dir, 2) ~= 0
    end, collision_tiles)
    player.slope_dir = collided_slope and sign(info_of(collided_slope.tile).normals[1].x) or 0
    tprint("slope_dir = " .. tostring(player.slope_dir))

    player.coyote_time = (old_on_ground and not player.on_ground and player.vel.y > 0) and COYOTE_TIME_FRAMES
                      or (player.on_ground) and 0
                      or math.max(0, player.coyote_time - 1)
    tprint("coyote = " .. tostring(player.coyote_time))

    if rl.IsKeyPressed(rl.KEY_Z) and not player.on_ground and player.vel.y > 0 then
        local hitbox = map(function (v) return v + player.pos end, PLAYER_HITBOX)
        local hitboxes = get_hitboxes(hitbox, PLAYER_COLLISION_HITBOXES)
        local h = map(function (v) return v + vec.v2(0, JUMP_BUF_WINDOW) end, hitboxes[2][2])
        if #get_tiles(h, identity) > 0 then
            player.jump_buf = true
        end
    end
    tprint("jump buf = " .. tostring(player.jump_buf))

    player.platforms_standing = map(function (v) return v.entity_id end, filter(function (v) return v.entity_id end, collision_tiles))

    camera.target = player.pos

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
                    end, collision_tiles) and rl.RED or rl.WHITE
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
                    end, collision_tiles) and rl.RED or rl.WHITE
                    local points = map(function (p) return orig + p * TILE_SIZE end, info.slope.points)
                    rl.DrawTriangle(points[1], points[2], points[3], color)
                end
            end
        end
    end

    for _, entity in ipairs(entities) do
        local info = entity_info[entity.type]
        if entity.type == ENTITY_MOVING_PLATFORM then
            rl.DrawRectangleRec(rec.new(entity.pos, info.size), rl.YELLOW)
        elseif entity.type == ENTITY_BOULDER then
            rl.DrawRectangleRec(rec.new(entity.pos, info.size), rl.GRAY)
        end
    end

    rl.DrawRectangleLinesEx(rec.new(player.pos, PLAYER_DRAW_SIZE), 1.0, rl.RED)

    local hitbox = map(function (v) return v + player.pos end, PLAYER_HITBOX)
    local hitboxes = get_hitboxes(hitbox, PLAYER_COLLISION_HITBOXES)
    for _, axis in ipairs(hitboxes) do
        for _, hitbox in ipairs(axis) do
            rl.DrawRectangleLinesEx(rec.new(hitbox[1], hitbox[2] - hitbox[1]), 1.0, rl.BLUE)
        end
    end

    local center = player.pos + (hitbox[2] - hitbox[1])/2
    tprint(fmt.tostring("player.pos = ", player.pos, "old_pos = ", old_pos))
    tprint(fmt.tostring("diff = ", player.pos - old_pos))
    rl.DrawLineV(center, center + vec.normalize(player.pos - old_pos) * 50, rl.YELLOW)
    rl.DrawLineV(center, center + vec.normalize(calculated_vel) * 50, rl.GREEN)

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

