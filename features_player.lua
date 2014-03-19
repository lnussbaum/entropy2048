-- Entropy 2048, an artificial player for 2048.
-- Copyright (C) 2014 Christophe Thiéry
-- This program is free software; you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation; either version 3 of the License, or
-- (at your option) any later version.
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
-- You should have received a copy of the GNU General Public License
-- along with this program; if not, write to the Free Software Foundation,
-- Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301  USA


-- Artificial player that maximizes a weighted sum of features
-- with a depth of 1.
-- Two of the features are inspired from
-- http://stackoverflow.com/questions/22342854/what-is-the-optimal-algorithm-for-the-game-2048

local game_manager = require("game_manager")
local player = {}
local verbose = false

-- Weights below were obtained using the cross-entropy method
-- (see cross_entropy.lua).

-- Using immediate evaluation without spawned tile:
--[[
local weights = {
  -4.93,
  -10.91,
  85.84,
  18.52,
  -24.71,
  0.0,
}
--]]

-- Taking spawned tile into account:
local weights = {

  -- Best score: 102700
  --[[
  -7.22,
  -69.03,
  174.75,
  -0.17,
  37.36,
  0.0,
  --]]

  -- Best score: 78960
  -1.07,
  -8.32,
  15.28,
  19.18,
  2.93,
  18.54,

}

local logs = {}
local function log2(n)
  assert(n > 0)
  local cached = logs[n]
  if cached ~= nil then
    return cached
  end

  local result = math.log(n) / math.log(2)
  logs[n] = result
  return result
end

-- Measures how monotonic (increasing or decreasing) rows and columns are.
local function monotonicity(game)

  local result = 0
  local board = game:get_board()
  local num_cells = game:get_num_cells()
  local num_columns = game:get_num_columns()

  local left_increase = 0
  local right_increase = 0
  local top_increase = 0
  local bottom_increase = 0

  for i = 1, num_cells do
    local tile = board[i] or 0

    local right_tile
    if i % num_columns ~= 0 then
      right_tile = board[i + 1] or 0
      if right_tile > tile then
        right_increase = right_increase + log2(right_tile - tile)
      elseif tile > right_tile then
        left_increase = left_increase + log2(tile - right_tile)
      end
    end

    local bottom_tile
    if i + num_columns <= num_cells then
      bottom_tile = board[i + num_columns] or 0
      if bottom_tile > tile then
        bottom_increase = bottom_increase + log2(bottom_tile - tile)
      elseif tile > bottom_tile then
        top_increase = top_increase + log2(tile - bottom_tile)
      end
    end
  end

  return math.min(left_increase, right_increase) + math.min(top_increase, bottom_increase)
end

-- Sum of differences between adjacent tiles.
local function smoothness(game)

  local result = 0
  local board = game:get_board()
  local num_cells = game:get_num_cells()
  local num_columns = game:get_num_columns()

  for i = 1, num_cells do
    local tile = board[i] or 0

    local right_tile
    if i % num_columns ~= 0 then
      right_tile = board[i + 1] or 0
      if right_tile ~= nil then
        local diff = tile - right_tile
        if diff ~= 0 then
          result = result + log2(math.abs(diff))
        end
      end
    end

    local bottom_tile
    if i + num_columns <= num_cells then
      bottom_tile = board[i + num_columns] or 0
      if bottom_tile ~= nil then
        local diff = tile - bottom_tile
        if diff ~= 0 then
          result = result + log2(math.abs(diff))
        end
      end
    end
  end

  return result
end

-- Number of empty cells.
local function num_free_cells(game)

  local board = game:get_board()
  local num_free_cells = 0
  for i = 1, game:get_num_cells() do
    if board[i] == nil then
      num_free_cells = num_free_cells + 1
    end
  end

  return num_free_cells
end

-- Number of free cells plus number of paired tiles (two adjacent tiles with
-- the same value).
-- This feature tries to capture if several moves are possibles,
-- in order to avoid game over.
local function num_free_or_paired_cells(game)

  local result = 0

  local board = game:get_board()
  local num_columns = game:get_num_columns()
  local num_cells = game:get_num_cells()
  for i = 1, num_cells do

    local tile = board[i]
    if tile == nil then
      result = result + 1
    else

      local right_tile
      if i % num_columns ~= 0 then
        right_tile = board[i + 1] or 0
        if right_tile == tile then
          result = result + 1
        end
      end

      local bottom_tile
      if i + num_columns <= num_cells then
        bottom_tile = board[i + num_columns] or 0
        if bottom_tile == tile then
          result = result + 1
        end
      end

    end
  end

  return result
end

-- Maximum tile of the board.
local function max_tile(game)
  return game:get_best_tile()
end

-- 1 if we can move in both directions, 0 otherwise.
-- This feature tries to avoid situations where the player is forced to do
-- one action that would move big tiles away from their side.
local function freedom_degree(game)

  local board = game:get_board()
  local num_cells = game:get_num_cells()
  local num_columns = game:get_num_columns()

  local can_move_horizontally = false
  local can_move_vertically = false

  for i = 1, num_cells do
    local tile = board[i]

    -- Find a horizontal empty/full or full/empty transition,
    -- or two horizontally adjacent tiles.
    local right_tile
    if not can_move_horizontally then
      if i % num_columns ~= 0 then
        right_tile = board[i + 1]
        can_move_horizontally = ((right_tile == nil) ~= (tile == nil))  -- Full near empty.
            or (tile ~= nil and right_tile == tile)  -- Adjacent tiles.
      end
    end

    -- Find a vertical empty/full or full/empty transition,
    -- or two vertically adjacent tiles.
    local bottom_tile
    if not can_move_vertically then
      if i + num_columns <= num_cells then
        bottom_tile = board[i + num_columns]
        can_move_vertically = ((bottom_tile == nil) ~= (tile == nil))  -- Full near empty.
            or (tile ~= nil and bottom_tile == tile)  -- Adjacent tiles.
      end
    end

    if can_move_horizontally and can_move_vertically then
      return 1
    end
  end

  return 0
end

local features = {
  monotonicity,
  smoothness,
  num_free_cells,
  max_tile,
  freedom_degree,
  num_free_or_paired_cells,
}

-- Returns the evaluation of a game state.
local function evaluate(game)

  local value = 0
  for i = 1, #features do
    value = value + features[i](game) * weights[i]
  end

  if verbose then
    game:print()
    print("Monotonicity: " .. monotonicity(game))
    print("Difference between adjacent cells: " .. smoothness(game))
    print("Number of free cells: " .. num_free_cells(game))
    print("Freedom: " .. freedom_degree(game))
    print("Number of free or paired cells: " .. num_free_or_paired_cells(game))
    print("Evaluation: " .. value)
  end

  return value
end

-- Returns the evaluation of a game state, taking into acocunt
-- all possible spawning positions for the new tile.
local function evaluate_with_spawns(game)

  -- Try all possible spawning cases.
  local board = game:get_board()
  local mean_value = 0.0
  local num_empty_cells = 0
  local tiles = { [2] = 0.9, [4] = 0.1 }
  for index = 1, game:get_num_cells() do
    if board[index] == nil then
      num_empty_cells = num_empty_cells + 1

      for tile, tile_proba in pairs(tiles) do

        board[index] = tile

        local value = 0
        for i = 1, #features do
          value = value + features[i](game) * weights[i]
        end
        mean_value = mean_value + value * tile_proba

        board[index] = nil

        if verbose then
          game:print()
          print("Monotonicity: " .. monotonicity(game))
          print("Difference between adjacent cells: " .. smoothness(game))
          print("Number of free cells: " .. num_free_cells(game))
          print("Freedom: " .. freedom_degree(game))
          print("Number of free or paired cells: " .. num_free_or_paired_cells(game))
          print("Evaluation: " .. value)
          print()
        end
      end
    end
  end

  assert(num_empty_cells > 0)

  return mean_value / num_empty_cells
end

local absmin = -1000000;
local absmax = 1000000;

local function mean(arr)
  s = 0.0
  n = 0
  for _, elem in ipairs(arr) do
    s = s + elem
  end
  return s/#arr
end

local eiverbose = false

local function expectimax(game, depth, player)
  if eiverbose then
    io.stdout:write(string.format("EI entering depth=%d player=%s\n", depth, tostring(player)))
  end
  if depth == 0 then
    local e = evaluate(game)
    if eiverbose then
      io.stdout:write(string.format("EI returning depth=%d val=%f\n", depth, e))
    end
    return e, nil
  else
    local ngame = game_manager:new()
    if player == true then -- maximizing player
      local best_value = absmin
      local best_move = nil
      for i = 1, 4 do
        ngame:load_from(game)
        if ngame:move(i, false) then
          if best_move == nil then
            best_move = i -- use first possible move
          end
          if eiverbose then
            io.stdout:write(string.format("- MAX trying move %d at depth %d...\n", i, depth))
          end
          local value, move = expectimax(ngame, depth - 1, false)
          if eiverbose then
            io.stdout:write(string.format("- MAX returning from move %d at depth %d: %f\n", i, depth, value))
          end
          if value > best_value then
            best_value = value
            best_move = i
          end
        end
      end
      if eiverbose then
        io.stdout:write(string.format("EI returning after MAX depth=%d val=%f\n", depth, best_value))
      end
      return best_value, best_move
    else
      local values = {}
      values[2] = {}
      values[4] = {}
      local best_value = absmax
      local best_move
      local evaluated = 0
      for i = 1, game:get_num_cells() do
        if game:get_tile(i) == nil then
          ngame:load_from(game)
          for val = 2, 4, 2 do
            ngame:set_tile(i, val)
            if eiverbose then
              io.stdout:write(string.format("EXPECT trying set_tile(%d, %d) at depth %d...\n", i, val, depth))
            end
            local value, move = expectimax(ngame, depth - 1, true)
            if eiverbose then
              io.stdout:write(string.format("EXPECT returning from set_tile(%d, %d) at depth %d: %f\n", i, val, depth, value))
            end
            values[val][#values[val]+1] = value
          end
        end
      end
      local m = 0.9*mean(values[2]) + 0.1*mean(values[4])
      if eiverbose then
        io.stdout:write(string.format("EI returning after EXPECT depth=%d avg=%f #val=%d\n", depth, m, #values[2]))
      end
      return m
    end
  end
end

function player:get_action(game)

  local depth
  if num_free_cells(game) < 3 then
    depth = 9
  elseif num_free_cells(game) < 5 then
    depth = 7
  else
    depth = 5
  end

  local best_value, best_move = expectimax(game, depth, true)
  if verbose then
    io.stdout:write(string.format("Best move: %d (val = %f)\n", best_move, best_value))
  end
  return best_move
end

function player:get_weights()
  return weights
end

function player:set_weights(w)
  weights = w
end

return player

