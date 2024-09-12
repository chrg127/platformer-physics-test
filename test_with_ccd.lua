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

-- find maximum element of t, with fn as a mapper function
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

-- our game uses 16x16 tiles
local TILE_SIZE = 16
-- a screen will always be 20x16 tiles
-- smw is 16x14, so this viewport is slightly larger
local SCREEN_WIDTH = 25
local SCREEN_HEIGHT = 20
-- scale window up to this number
local SCALE = 1

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
    { 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    { 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    { 0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    { 0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1, 0, 1, 0, 1, 0 },
    { 1, 1, 1, 1, 1, 1, 0, 0, 0, 1, 1, 1, 0, 0, 0, 0, 1, 1, 1, 0, 1, 0, 1, 0, 1 },
    { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0 },
    { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
}

function p2t(p)
    return vec.floor(p / TILE_SIZE) + vec.v2(1, 1)
end

function t2p(t)
    return (t - vec.v2(1, 1)) * TILE_SIZE
end

local player = {
    pos = vec.v2(SCREEN_WIDTH * TILE_SIZE / 2, SCREEN_HEIGHT * TILE_SIZE / 2) - vec.v2(8, 0),
    draw_size = vec.v2(TILE_SIZE, TILE_SIZE * 2),
    hitbox = { vec.v2(0, 0), vec.v2(TILE_SIZE, TILE_SIZE*2) },
    vel = vec.v2(0, 0),
    on_ground = false,
}

local logfile = io.open("log.txt", "w")

while not rl.WindowShouldClose() do
    local dt = rl.GetFrameTime()

    cur_line = 15
    function tprint(s)
        rl.DrawText(s, 5, cur_line, 10, rl.GREEN)
        cur_line = cur_line + 10
        logfile:write(s .. "\n")
    end

    tprint("new frame")

    -- physics
    local DECEL = 200
    local ACCEL = 400
    local VEL_CAP = 150
    local GRAVITY = 400

    local accel = vec.v2(
        (rl.IsKeyDown(rl.KEY_LEFT)  and -ACCEL or 0)
      + (rl.IsKeyDown(rl.KEY_RIGHT) and  ACCEL or 0),
        ((rl.IsKeyPressed(rl.KEY_Z) and player.on_ground) and -15000 or 0)
    )

    local decel = player.vel.x > 0 and -DECEL
               or player.vel.x < 0 and  DECEL
               or 0

    local gravity = vec.v2(0, GRAVITY)

    local old_vel = player.vel
    player.vel = player.vel + (accel + vec.v2(decel, 0) + gravity) * dt
    if player.vel.x > VEL_CAP then
        player.vel.x = VEL_CAP
    elseif player.vel.x < -VEL_CAP then
        player.vel.x = -VEL_CAP
    end
    if math.abs(player.vel.x) < 1 then
        player.vel.x = 0
    end

    local old_pos = player.pos
    -- player.pos = player.pos + player.vel * dt
    player.pos = player.pos + vec.v2(
        rl.IsKeyDown(rl.KEY_LEFT) and -1 or rl.IsKeyDown(rl.KEY_RIGHT) and 1 or 0,
        rl.IsKeyDown(rl.KEY_UP)   and -1 or rl.IsKeyDown(rl.KEY_DOWN)  and 1 or 0
    ) * 4

	rl.BeginDrawing()

    rl.BeginTextureMode(buffer)
	rl.ClearBackground(rl.BLACK)

    tprint("oldpos= " .. tostring(old_pos))
    tprint("pos   = " .. tostring(player.pos))
    tprint("vel   = " .. tostring(player.vel))
    tprint("accel = " .. tostring(accel))
    tprint("decel = " .. tostring(decel))

    -- collision with ground
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

    local aabb = map(function (_, v) return v + player.pos end, player.hitbox)
    tprint(fmt.tostring("aabb =", aabb))

    -- move: left = 1, right = 2; dim = vec.x or vec.y
    -- function get_tiles(points, move, dim)
    --     local ts = {}
    --     for _, p in ipairs(points) do
    --         local t = p2t(p)
    --         if  tilemap[t.y] ~= nil and tilemap[t.y][t.x] ~= nil
    --         and tilemap[t.y][t.x] ~= 0 then
    --             local p = t2p(t)
    --             table.insert(ts, p)
    --             table.insert(ts, p + vec.v2(TILE_SIZE-1, TILE_SIZE-1))
    --         end
    --     end
    --     return ts
    -- end

    -- local points = {
    --     {
    --         {
    --             aabb[1]                      + vec.v2( 0,  8), -- top left
    --             aabb[1]                      + vec.v2( 0, 16), -- middle left
    --             vec.v2(aabb[1].x, aabb[2].y) + vec.v2( 0, -8), -- bottom left
    --         }, {
    --             vec.v2(aabb[2].x, aabb[1].y) + vec.v2( 0,  8), -- top right
    --             aabb[2]                      + vec.v2( 0,-16), -- middle right
    --             aabb[2]                      + vec.v2( 0, -8), -- bottom right
    --         }
    --     }, {
    --         {
    --             aabb[1]                      + vec.v2( 1,  0), -- top left
    --             vec.v2(aabb[2].x, aabb[1].y) + vec.v2(-1,  0), -- top right
    --         }, {
    --             vec.v2(aabb[1].x, aabb[2].y) + vec.v2( 1,  0), -- bottom left
    --             aabb[2]                      + vec.v2(-1,  0), -- bottom right
    --         }
    --     }
    -- }

    -- for d = 1, 0, -1 do
    --     local dim = d == 0 and vec.x or vec.y
    --     for dir = 0, 1 do
    --         local move = dir
    --         local tiles = get_tiles(points[d+1][move+1], move+1, dim)
    --         local ops = {maxf, minf}
    --         local tile = ops[move+1](dim, tiles)
    --         if math.abs(tile) ~= math.huge then
    --             tprint(fmt.tostring("(d = ", d, ") move =", move))
    --             tprint(fmt.tostring("(d = ", d, ") tile =", tile))
    --             player.vel = vec.set_dim(player.vel, d, 0)
    --             local diff = { 1, dim(aabb[1]) - dim(aabb[2]) }
    --             player.pos = vec.set_dim(player.pos, d, tile + diff[move+1] - dim(player.hitbox[1]))
    --             callbacks[d * 2 + move + 1]()
    --         end
    --     end
    -- end

    local aabb_old = map(function (_, v) return v + old_pos end, player.hitbox)
    local tile_points = {}
    local start = p2t(aabb[1])
    local endd  = p2t(aabb[2])
    for y = start.y, endd.y do
        for x = start.x, endd.x do
            if  tilemap[y] ~= nil and tilemap[y][x] ~= nil
            and tilemap[y][x] ~= 0 then
                local tl = t2p(vec.v2(x, y))
                local tr = tl + vec.v2(TILE_SIZE,         0) - vec.v2(1, 0)
                local br = tl + vec.v2(TILE_SIZE, TILE_SIZE) - vec.v2(1, 1)
                local bl = tl + vec.v2(        0, TILE_SIZE) - vec.v2(0, 1)
                local tps = { tl, tr, br, bl }
                for _, p in ipairs(filter(function (k, p)
                    return aabb_point_inside(aabb, p)
                end, tps)) do
                    table.insert(tile_points, p)
                end
            end
        end
    end

    if #tile_points > 0 then
        local whatever = function () return math.huge end
        local ops = { maxf, whatever, minf }

        function get_t(dim)
            local move = sign(dim(player.pos) - dim(old_pos))
            local op = ops[move+2]
            local nearest_tile_dim = op(dim, tile_points)
            local index = move == -1 and 1 or 2
            tprint(fmt.tostring("rlerp between ", dim(aabb_old[index]), dim(aabb[index])))
            local t = rlerp(dim(aabb_old[index]), dim(aabb[index]), nearest_tile_dim)
            tprint(fmt.tostring("d =", nearest_tile_dim))
            return t
        end

        function get()
            local tx = get_t(vec.x)
            local ty = get_t(vec.y)
            tprint(fmt.tostring("tx = ", tx, ", ty = ", ty))
            if (tx < 0.0 or tx > 1.0) and (ty < 0.0 or ty > 1.0) then
                return nil, nil
            end
            if (tx < 0.0 or tx > 1.0) then
                return nil, ty
            end
            if (ty < 0.0 or ty > 1.0) then
                return tx, nil
            end
            if tx < ty then
                return tx, nil
            end
            return nil, ty
        end

        local tx, ty = get()
        tprint(fmt.tostring("new tx = ", tx, ", new ty = ", ty))

        if tx ~= nil then
            player.pos.x = lerp(aabb_old[1].x, aabb[1].x, tx)
            player.vel.x = 0
        end
        if ty ~= nil then
            player.pos.y = lerp(aabb_old[1].y, aabb[1].y, ty)
            player.vel.y = 0
        end

        -- -- local t = math.min(tx, ty)
        -- function get_t2(tx, ty)
        --     if (tx < 0.0 or tx > 1.0) and (ty < 0.0 or ty > 1.0) then return 0.0
        --     elseif tx < 0.0 or tx > 1.0 then return ty
        --     elseif ty < 0.0 or ty > 1.0 then return tx
        --     else return math.min(tx, ty) end
        -- end

        -- local t = get_t2(tx, ty)
        -- local new_x = lerp(aabb_old[1].x, aabb[1].x, t)
        -- local new_y = lerp(aabb_old[1].y, aabb[1].y, t)
        -- tprint(fmt.tostring("t = ", t, ", newx = ", new_x, ", newy = ", new_y))
        -- tprint(fmt.tostring("newx = lerp(", aabb_old[1].x, ", ", aabb[1].x, ", ", t, ")"))
        -- player.pos.x = new_x
        -- player.pos.y = new_y
        -- player.vel.x = 0
        -- player.vel.y = 0
        player.on_ground = true
    end

    tprint("pos (adjusted) = " .. tostring(player.pos))

    camera.target = player.pos

    rl.BeginMode2D(camera)

    for y = 1, SCREEN_HEIGHT do
        for x = 1, SCREEN_WIDTH do
            if tilemap[y][x] ~= 0 then
                if ground_tile ~= nil and vec.eq(ground_tile, vec.v2(x, y)) then
                    rl.DrawRectangleV(vec.v2(x-1, y-1) * TILE_SIZE, vec.v2(TILE_SIZE, TILE_SIZE), rl.RED)
                else
                    rl.DrawRectangleV(vec.v2(x-1, y-1) * TILE_SIZE, vec.v2(TILE_SIZE, TILE_SIZE), rl.WHITE)
                end
            end
        end
    end

    if points ~= nil then
        for _, ps1 in ipairs(points) do
            for _, ps2 in ipairs(ps1) do
                for _, p in ipairs(ps2) do
                    rl.DrawPixelV(p, rl.BLUE)
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

    --rl.DrawFPS(10, 10)
	rl.EndDrawing()
end

