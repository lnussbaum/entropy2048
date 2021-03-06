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


-- This is the main script.
-- Plays games using the player whose name is passed as parameter.
-- Usage: lua entropy2048.lua [player_file [num_games]]

local player_file, num_games = ...

local game_manager = require("game_manager")
local verbose = false  -- Set this true to print the board at each move.

player_file = player_file or "random_player"
num_games = num_games or 1
local player = require(player_file)

-- Plays a new game and returns the score and the best tile.
local function play_game()
  local game = game_manager:new()
  assert(game:get_score() == 0)
  -- game:load({nil, nil, nil, nil, 8, 2, 2, nil, 2, 8, nil, nil, 128, 128, 8, nil}, 1548, 128)
  while game:is_alive() do
    if verbose then game:print() end
    local action = player:get_action(game)
    game:move(action)
  end
  if verbose then game:print() end
  return game:get_score(), game:get_best_tile()
end

local seed = os.time()
io.write("Random seed: ", seed, "\n")
math.randomseed(seed)

io.write("Running ", num_games, " games with player '", player_file, "'\n")
local average, max, best_tile, worst_best_tile = 0, 0, 0, nil
for i = 1, num_games do
  local score, current_best_tile = play_game()
  io.write(score .. " ")
  io.flush()
  average = average + score
  if score > max then
    max = score
  end
  if current_best_tile > best_tile then
    best_tile = current_best_tile
  end
  if worst_best_tile == nil or current_best_tile < worst_best_tile then
    worst_best_tile = current_best_tile
  end
end
average = average / num_games

io.write("\nAverage score: " .. average .. "\n")
io.write("Max score: " .. max .. "\n")
io.write("Best tile: " .. best_tile .. "\n")
io.write("Worst Best tile: " .. worst_best_tile .. "\n")

