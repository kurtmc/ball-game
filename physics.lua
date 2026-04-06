local G = require("grid")

local physics = {}

local EPSILON = 1e-6

-- Cast a ray from (ox, oy) in direction (dx, dy) and find the first collision
-- with walls or blocks. Returns: hit_time, hit_type, hit_data
-- hit_type: "wall_left", "wall_right", "wall_top", "floor", "block"
-- hit_data for block: {col, row, face} where face is "left","right","top","bottom"
function physics.castRay(ox, oy, dx, dy, grid_data, max_time, ball_radius)
    max_time = max_time or 999
    ball_radius = ball_radius or G.BALL_RADIUS

    local best_t = max_time
    local best_type = nil
    local best_data = nil

    -- Wall collisions (treating ball as point, walls inset by ball_radius)
    local left_wall  = G.GRID_LEFT + ball_radius
    local right_wall = G.GRID_RIGHT - ball_radius
    local top_wall   = G.GRID_TOP + ball_radius
    local floor_line = G.FLOOR_Y

    -- Left wall
    if dx < -EPSILON then
        local t = (left_wall - ox) / dx
        if t > EPSILON and t < best_t then
            best_t = t
            best_type = "wall_left"
            best_data = nil
        end
    end

    -- Right wall
    if dx > EPSILON then
        local t = (right_wall - ox) / dx
        if t > EPSILON and t < best_t then
            best_t = t
            best_type = "wall_right"
            best_data = nil
        end
    end

    -- Top wall
    if dy < -EPSILON then
        local t = (top_wall - oy) / dy
        if t > EPSILON and t < best_t then
            best_t = t
            best_type = "wall_top"
            best_data = nil
        end
    end

    -- Floor
    if dy > EPSILON then
        local t = (floor_line - oy) / dy
        if t > EPSILON and t < best_t then
            best_t = t
            best_type = "floor"
            best_data = nil
        end
    end

    -- Block collisions using Minkowski-expanded AABB
    if grid_data then
        for r = 1, G.ROWS + 1 do
            if grid_data[r] then
                for c = 1, G.COLS do
                    local block = grid_data[r][c]
                    if block then
                        local bx, by, bw, bh = G.blockRect(c, r)
                        -- Expand by ball radius (Minkowski sum)
                        local ex = bx - ball_radius
                        local ey = by - ball_radius
                        local ew = bw + 2 * ball_radius
                        local eh = bh + 2 * ball_radius

                        -- Slab test
                        local t_x_enter, t_x_exit, t_y_enter, t_y_exit

                        if math.abs(dx) < EPSILON then
                            if ox >= ex and ox <= ex + ew then
                                t_x_enter = -math.huge
                                t_x_exit = math.huge
                            else
                                goto continue
                            end
                        else
                            local inv_dx = 1 / dx
                            local t1 = (ex - ox) * inv_dx
                            local t2 = (ex + ew - ox) * inv_dx
                            t_x_enter = math.min(t1, t2)
                            t_x_exit  = math.max(t1, t2)
                        end

                        if math.abs(dy) < EPSILON then
                            if oy >= ey and oy <= ey + eh then
                                t_y_enter = -math.huge
                                t_y_exit = math.huge
                            else
                                goto continue
                            end
                        else
                            local inv_dy = 1 / dy
                            local t1 = (ey - oy) * inv_dy
                            local t2 = (ey + eh - oy) * inv_dy
                            t_y_enter = math.min(t1, t2)
                            t_y_exit  = math.max(t1, t2)
                        end

                        local t_enter = math.max(t_x_enter, t_y_enter)
                        local t_exit  = math.min(t_x_exit, t_y_exit)

                        if t_enter < t_exit and t_enter > EPSILON and t_enter < best_t then
                            -- Determine which face was hit
                            local face
                            if t_x_enter > t_y_enter then
                                face = dx > 0 and "left" or "right"
                            elseif t_y_enter > t_x_enter then
                                face = dy > 0 and "top" or "bottom"
                            else
                                face = "corner"
                            end
                            best_t = t_enter
                            best_type = "block"
                            best_data = { col = c, row = r, face = face }
                        end

                        ::continue::
                    end
                end
            end
        end
    end

    return best_t, best_type, best_data
end

-- Resolve a collision: return new vx, vy after reflection
function physics.reflect(vx, vy, hit_type, hit_data)
    if hit_type == "wall_left" or hit_type == "wall_right" then
        return -vx, vy
    elseif hit_type == "wall_top" then
        return vx, -vy
    elseif hit_type == "floor" then
        return vx, vy  -- no reflection, ball collected
    elseif hit_type == "block" then
        local face = hit_data.face
        if face == "left" or face == "right" then
            return -vx, vy
        elseif face == "top" or face == "bottom" then
            return vx, -vy
        else -- corner
            return -vx, -vy
        end
    end
    return vx, vy
end

return physics
