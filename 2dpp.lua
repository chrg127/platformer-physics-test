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
function vec.dim(v, d) return d == 0 and v.x or v.y end

function vec.set_dim(v, d, x)
    return vec.v2(d == 0 and x or v.x, d == 1 and x or v.y)
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
    for _, v in pairs(t) do
        if pred(v) then
            table.insert(r, v)
        end
    end
    return r
end

function filter_not(pred, t)
    return filter(function (v) return not pred(v) end, t)
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
    [1]  = { normals = { vec.v2(1, 0), vec.v2(-1, 0), vec.v2(0, 1), vec.v2(0, -1) } },
    [2]  = { normals = { vec.v2(0, -1) } },
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
    {  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  1,  0,  0,  6,  0,  0,  0,  0,  0,  0,  0,  0,  4,  0,  0 },
    {  0,  0,  0,  0,  0,  1,  0,  1,  3,  0,  0,  0,  6,  0,  0,  0,  1,  2,  0,  0,  0,  0,  0,  0,  0 },
    {  0,  0,  0,  7,  9,  0,  1,  0,  0,  1,  1,  6,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0 },
    {  0,  0,  0,  8, 10,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  4,  0,  0,  0,  0,  0 },
    {  0,  0,  0, 13, 11,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  4,  0,  0,  0,  0,  0,  0 },
    {  0,  0,  0, 14, 12,  1,  1,  1,  1,  1,  0,  0,  0,  0,  0,  0,  0,  7,  0,  0,  0,  0,  0,  0,  0 },
    {  0,  0,  0,  4,  3,  1,  0,  0,  0,  1,  0,  1,  2,  2,  0,  0,  0,  8,  0,  0,  0,  0,  0,  0,  0 },
    {  1,  1,  1,  5,  6,  1,  0,  0,  0,  1,  0,  0,  0,  0,  0,  0,  0,  1,  1,  1,  1,  1,  0,  1,  0 },
    {  1,  1,  1,  1,  1,  1,  0,  0,  0,  1,  1,  3,  0,  0,  0,  4,  1,  1,  1,  0,  1,  0,  1,  0,  1 },
    {  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  1,  1, 15, 16,  1,  1,  0,  0,  0,  0,  0,  0,  0,  0 },
    {  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  1,  1,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0 },
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
    return ti ~= nil and ti >= 3
end

-- check if t is a slope and its highest point is left (sgn = -1) or right (sgn = 1)
function is_slope_facing(t, sgn)
    return is_slope(t) and sign(info_of(t).normals[1].x) == sgn
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
            if is_slope(t+n) and vec.eq(t + n - info_of(t).slope.origin, origin)
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
                  - vec.v2(TILE_SIZE/2, -TILE_SIZE),
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
        { vec.v2( 0,  0), vec.v2(15, 10) }, -- up
        { vec.v2( 0, 22), vec.v2(15, 32) }, -- down
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
    local old_vel = player.vel
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

    function get_tiles(box)
        local res, start, endd = {}, p2t(box[1]), p2t(box[2])
        for y = start.y, endd.y do
            for x = start.x, endd.x do
                t = vec.v2(x, y)
                if not is_air(t) then
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

    function collide_tiles(pos, vel, old_pos, hitbox_unit, collision_boxes)
        local size = hitbox_unit[2] - hitbox_unit[1]
        local result = {}
        for axis = 0, 1 do
            local direction = vec.normalize(pos - old_pos)
            local dim = axis == 0 and vec.x or vec.y
            local move = sign(dim(player.pos - old_pos))
            for move = 0, 1 do
                local old_hitbox = map(function (v) return v + old_pos end, hitbox_unit)
                local hitbox = map(function (v) return v + pos end, hitbox_unit)
                local boxes = get_hitboxes(hitbox, collision_boxes)
                local tiles = get_tiles(boxes[axis+1][move+1])
                if #tiles > 0 then
                    local minf = move == 0 and function (t) return maxf(identity, -math.huge, t) end
                                           or  function (t) return minf(identity,  math.huge, t) end

                    function ignore_tile(tile)
                        local side = move == 0 and -1 or 1
                        if axis == 0 and is_slope_facing(tile + vec.v2(-side, 0), -side) then
                            return true
                        end
                        local center = vec.v2(hitbox[1].x + size.x/2, hitbox[move+1].y)
                        function check(t, where)
                            return is_slope_facing(t, where)
                               and vec.eq(p2t(center), t)
                               and move == b2i(info_of(t).normals[1].y < 0)
                        end
                        return check(tile + vec.v2(-1, 0), -1)
                            or check(tile + vec.v2( 1, 0),  1)
                    end

                    function get_tile_dim(tile)
                        local normals = info_of(tile).normals
                        local res = filter(function (n)
                            return vec.dot(direction, n) < 0
                        end, normals)
                        if #res == 0 then
                            return math.huge
                        end
                        -- tprint(fmt.tostring("p2t(old_pos) = ", p2t(old_pos), "tile = ", tile))
                        -- if p2t(old_pos) == tile then
                        --     return math.huge
                        -- end
                        tprint(fmt.tostring("normals = ", res))
                        local points = { vec.one, vec.zero }
                        local point = t2p(tile) + points[move+1] * TILE_SIZE
                        return dim(point) - dim(size) * move - dim(hitbox_unit[1])
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
                        if (old_y == math.huge or lteq(old_hitbox[dir+1].y, old_y))
                        and not lteq(hitbox[dir+1].y, y) then
                            return y - size.y * dir
                        end
                        return math.huge
                    end

                    function get_slope_y(slopes)
                        function is_on_center(tile)
                            local info = info_of(tile)
                            local x = hitbox[1].x + size.x/2 - t2p(tile - info.slope.origin).x
                            return x > 0 and x < info.slope.size.x * TILE_SIZE
                        end
                        local slope = #slopes == 1 and slopes[1] or findf(is_on_center, slopes)
                        return slope and get_slope_dim(slope) or math.huge
                    end

                    function get_slope_dim_x(tile)
                        local info       = info_of(tile)
                        local to         = t2p(tile - info.slope.origin)
                        local diry       = b2i(info.normals[1].y < 0)
                        local hitbox_y   = hitbox[diry+1].y
                        -- lowest y of normal slopes, highest y of upside-down slopes
                        local lowest_y   = to.y + diry * info.slope.size.y * TILE_SIZE
                        local min        = diry == 1 and math.min or math.max
                        local y          = min(hitbox_y, lowest_y)
                        local xu         = slope_diag_point(to, info, y, vec.y, vec.x)
                        local x          = to.x + xu * TILE_SIZE
                        local lt         = info.normals[1].x < 0 and lt or gt
                        return lt(hitbox[move+1].x, x) and math.huge
                            or x - size.x/2
                    end

                    function get_slope_x(slopes)
                        slopes = filter(function (v)
                            return v.x == p2t(hitbox[1] + size/2).x
                        end, slopes)
                        if #slopes < 2 then
                            return math.huge
                        end
                        local origs = map(function (s)
                            return s - info_of(s).slope.origin
                        end, slopes)
                        if #origs < 2 or all_eq(origs) then
                            return math.huge
                        end
                        local contact_points =
                            filter(function (v) return v ~= math.huge end,
                                map(get_slope_dim_x, slopes))
                        return #contact_points < 2 and math.huge
                            or minf(contact_points)
                    end

                    local slopes, others = partition(is_slope, tiles)
                    local dims = map(get_tile_dim, filter_not(ignore_tile, others))
                    table.insert(dims, axis == 0 and get_slope_x(slopes) or get_slope_y(slopes))
                    local d = minf(filter(function (v) return v ~= math.huge end, dims))
                    if math.abs(d) ~= math.huge then
                        pos = vec.set_dim(pos, axis, d)
                        local dir = vec.set_dim(vec.zero, axis, move == 0 and -1 or 1)
                        for _, ts in ipairs({others, slopes}) do
                            for _, t in ipairs(ts) do
                                table.insert(result, { tile = t, dir = dir })
                            end
                        end
                    end
                end
            end
        end
        return pos, result
    end

    local pos, collision_tiles = collide_tiles(
        player.pos, player.vel, old_pos, PLAYER_HITBOX, PLAYER_COLLISION_HITBOXES
    )
    player.pos = pos
    for _, dim in ipairs{ 0, 1 } do
        if findf(function (v) return vec.dim(v.dir, dim) ~= 0 end, collision_tiles) then
            player.vel = vec.set_dim(player.vel, dim, 0)
        end
    end
    if findf(function (v) return vec.eq(v.dir, vec.v2(0, 1)) end, collision_tiles) then
        player.on_ground = true
    end

    tprint("pos (adjusted) = " .. tostring(player.pos))
    tprint("on ground = " .. tostring(player.on_ground))

    player.coyote_time = (old_on_ground and not player.on_ground and player.vel.y > 0) and COYOTE_TIME_FRAMES
                      or (player.on_ground) and 0
                      or math.max(0, player.coyote_time - 1)
    tprint("coyote = " .. tostring(player.coyote_time))

    if rl.IsKeyPressed(rl.KEY_Z) and not player.on_ground and player.vel.y > 0 then
        local hitbox = map(function (v) return v + player.pos end, PLAYER_HITBOX)
        local hitboxes = get_hitboxes(hitbox, PLAYER_COLLISION_HITBOXES)
        local h = map(function (v) return v + vec.v2(0, JUMP_BUF_WINDOW) end, hitboxes[2][2])
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
                        return vec.eq(v.tile, tile)
                    end, collision_tiles) and rl.RED or rl.WHITE
                    for _, n in ipairs(info.normals) do
                        local ps = n2ps(n)
                        rl.DrawLineV(orig + ps[1] * TILE_SIZE, orig + ps[2] * TILE_SIZE, color)
                    end
                elseif vec.eq(info.slope.origin, vec.zero) then
                    local tiles = slope_tiles(tile)
                    local color = findf(function (v)
                        return findf(function (s) return vec.eq(v.tile, s) end, tiles)
                    end, collision_tiles) and rl.RED or rl.WHITE
                    local points = map(function (p) return orig + p * TILE_SIZE end, info.slope.points)
                    rl.DrawTriangle(points[1], points[2], points[3], color)
                end
            end
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

    rl.EndMode2D()

    for _, line in ipairs(lines_to_print) do
        rl.DrawText(line[1], 5, line[2], 10, rl.GRAY)
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

