-- various code snippets that i've needed earlier but in the end were deleted.
-- might still be useful, however.

local PLAYER_COLLISION_POINTS = {
    {
        { vec.v2(  0,  4), vec.v2(  0, 16), vec.v2(  0, 28), }, -- left
        { vec.v2(  0,-28), vec.v2(  0,-16), vec.v2(  0, -4), }  -- right
    }, {
        { vec.v2(  0,  0), vec.v2( 15,  0), }, -- top
        { vec.v2(-16,  0), vec.v2( -1,  0), }  -- bottom
    }
}

function get_tiles(points)
        local ts = {}
        for _, p in ipairs(points) do
            local t = p2t(p)
            if not is_air(t) then
                local tile = tilemap[t.y][t.x]
                if not is_slope(tile)
                   or triangle_point_collision(get_triangle_points(t), p) then
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

local PLAYER_COLLISION_POINTS = {
    {
        { vec.v2(  0,  4), vec.v2(  0, 16), vec.v2(  0, 28), }, -- left
        { vec.v2(  0,-28), vec.v2(  0,-16), vec.v2(  0, -4), }  -- right
    }, {
        { vec.v2(  0,  0), vec.v2( 15,  0), }, -- top
        { vec.v2(-16,  0), vec.v2( -1,  0), }  -- bottom
    }
}

function triangle_point_collision(t, p)
    function heron(t)
        return math.abs((t[2].x - t[1].x) * (t[3].y - t[1].y)
                      - (t[3].x - t[1].x) * (t[2].y - t[1].y))
    end
    local area = heron(t)
    local area1 = heron({p, t[1], t[2]})
    local area2 = heron({p, t[2], t[3]})
    local area3 = heron({p, t[3], t[1]})
    return area1 + area2 + area3 == area
end

function aabb_point_inside(aabb, p)
    return rl.CheckCollisionPointRec(p, rec.new(aabb[1], aabb[2] - aabb[1]))
end

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

function identity(x) return x end

                    local normal = info.slope.normal
                    local slope_width  = math.abs(info.slope.points[1].x - info.slope.points[2].x)
                    local slope_height = math.abs(info.slope.points[1].y - info.slope.points[2].y)
                    local line_orig = orig + vec.v2(TILE_SIZE * slope_width, TILE_SIZE * slope_height) / 2
                    rl.DrawLineV(line_orig, line_orig + normal * TILE_SIZE, rl.RED)

            local sgn = -sign(normal.x * normal.y)

-- local y = math.max((TILE_SIZE * slope_width * i2b(sgn == -1) + x * sgn) * slope_height/slope_width, 0)

function append(...)
    local r = {}
    for _, t in ipairs({...}) do
        for _, v in ipairs(t) do
            table.insert(r, v)
        end
    end
    return r
end

                        -- rl.DrawLineV(
                        --     orig + vec.v2(TILE_SIZE, TILE_SIZE) / 2 + vec.rotate(n * math.sqrt(2)/2 * TILE_SIZE,  math.pi/4),
                        --     orig + vec.v2(TILE_SIZE, TILE_SIZE) / 2 + vec.rotate(n * math.sqrt(2)/2 * TILE_SIZE, -math.pi/4),
                        --     rl.RED
                        -- )

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

