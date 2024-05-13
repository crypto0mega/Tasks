-- Initializing global variables to store the latest game state and game host process.
LatestGameState = LatestGameState or nil
InAction = InAction or false -- Prevents the agent from taking multiple actions at once.
Logs = Logs or {}

colors = {
    red = "\27[31m",
    green = "\27[32m",
    blue = "\27[34m",
    reset = "\27[0m",
    gray = "\27[90m"
}

function addLog(msg, text) -- Function definition commented for performance, can be used for debugging
    Logs[msg] = Logs[msg] or {}
    table.insert(Logs[msg], text)
end

-- Checks if two points are within a given range.
-- @param x1, y1: Coordinates of the first point.
-- @param x2, y2: Coordinates of the second point.
-- @param range: The maximum allowed distance between the points.
-- @return: Boolean indicating if the points are within the specified range.
function inRange(x1, y1, x2, y2, range)
    return math.abs(x1 - x2) <= range and math.abs(y1 - y2) <= range
end

function findWeakestPlayer()
    local weakestPlayer = nil
    local weakestHealth = math.huge

    for target, state in pairs(LatestGameState.Players) do
        if target == ao.id then
            goto continue
        end

        local opponent = state;

        if opponent.health < weakestHealth then
            weakestPlayer = opponent
            weakestHealth = opponent.health
        end

        ::continue::
    end

    return weakestPlayer
end

function findStrongestPlayer()
    local strongestPlayer = nil
    local strongestEnergy = -1

    for target, state in pairs(LatestGameState.Players) do
        if target == ao.id then
            goto continue
        end

        local opponent = state;

        if opponent.energy > strongestEnergy then
            strongestPlayer = opponent
            strongestEnergy = opponent.energy
        end

        ::continue::
    end

    return strongestPlayer
end

function isPlayerInAttackRange(player)
    local me = LatestGameState.Players[ao.id]

    if inRange(me.x, me.y, player.x, player.y, 1) then
        return true;
    end

    return false;
end

function attackWeakestPlayer()
    local weakestPlayer = findWeakestPlayer()

    if weakestPlayer then
        print(colors.red .. "Attacking weakest player." .. colors.reset)
        ao.send({ Target = Game, Action = "PlayerAttack", Player = ao.id, AttackEnergy = tostring(LatestGameState.Players[ao.id].energy * 0.5) }) -- Attack with 50% energy
        InAction = false -- Reset InAction after attacking
        return true
    end

    return false
end

-- Decides the next action based on player proximity and energy.
-- If any player is within range, it initiates an attack; otherwise, moves towards the weakest opponent.
function decideNextAction()
    local me = LatestGameState.Players[ao.id]

    local weakestPlayer = findWeakestPlayer()
    local strongestPlayer = findStrongestPlayer()

    if strongestPlayer and strongestPlayer.energy > me.energy then
        -- Move away from stronger opponent
        local avoidDirection = { x = strongestPlayer.x - me.x, y = strongestPlayer.y - me.y }
        avoidDirection = normalizeDirection(avoidDirection)
        print(colors.blue .. "Moving away from stronger opponent." .. colors.reset)
        ao.send({ Target = Game, Action = "PlayerMove", Player = ao.id, Direction = avoidDirection })
        InAction = false -- Reset InAction after moving
        return -- Exit function early
    end

    if weakestPlayer then
        local approachDirection = { x = weakestPlayer.x - me.x, y = weakestPlayer.y - me.y }
        approachDirection = normalizeDirection(approachDirection)
        print(colors.blue .. "Approaching weakest opponent." .. colors.reset)
        ao.send({ Target = Game, Action = "PlayerMove", Player = ao.id, Direction = approachDirection })
        InAction = false -- Reset InAction after moving
        return -- Exit function early
    else
        print("No opponents found.")
    end
end

function normalizeDirection(direction)
    local length = math.sqrt(direction.x * direction.x + direction.y * direction.y)
    return { x = direction.x / length, y = direction.y / length }
end

-- Handler to print game announcements and trigger game state updates.
Handlers.add(
    "PrintAnnouncements",
    Handlers.utils.hasMatchingTag("Action", "Announcement"),
    function(msg)
        if msg.Event == "Started-Waiting-Period" then
            ao.send({ Target = ao.id, Action = "AutoPay" })
        elseif (msg.Event == "Tick" or msg.Event == "Started-Game") and not InAction then
            InAction = true  -- InAction logic added
            ao.send({ Target = Game, Action = "GetGameState" })
        elseif InAction then -- InAction logic added
            print("Previous action still in progress. Skipping.")
        end

        print(colors.green .. msg.Event .. ": " .. msg.Data .. colors.reset)
    end
)

-- Handler to trigger game state updates.
Handlers.add(
    "GetGameStateOnTick",
    Handlers.utils.hasMatchingTag("Action", "Tick"),
    function()
        if not InAction then -- InAction logic added
            InAction = true  -- InAction logic added
            print(colors.gray .. "Getting game state..." .. colors.reset)
            ao.send({ Target = Game, Action = "GetGameState" })
        else
            print("Previous action still in progress. Skipping.")
        end
    end
)

-- Handler to automate payment confirmation when waiting period starts.
Handlers.add(
    "AutoPay",
    Handlers.utils.hasMatchingTag("Action", "AutoPay"),
    function(msg)
        print("Auto-paying confirmation fees.")
        ao.send({ Target = Game, Action = "Transfer", Recipient = Game, Quantity = "1000" })
    end
)

-- Handler to update the game state upon receiving game state information.
Handlers.add(
    "UpdateGameState",
    Handlers.utils.hasMatchingTag("Action", "GameState"),
    function(msg)
        local json = require("json")
        LatestGameState = json.decode(msg.Data)
        ao.send({ Target = ao.id, Action = "UpdatedGameState" })
        print("Game state updated. Print \'LatestGameState\' for detailed view.")
        print("energy:" .. LatestGameState.Players[ao.id].energy)
    end
)

-- Handler to decide the next best action.
Handlers.add(
    "decideNextAction",
    Handlers.utils.hasMatchingTag("Action", "UpdatedGameState"),
    function()
        if LatestGameState.GameMode ~= "Playing" then
            print("game not start")
            InAction = false -- InAction logic added
            return
        end
        print("Deciding next action.")
        decideNextAction()
        ao.send({ Target = ao.id, Action = "Tick" })
    end
)

-- Handler to automatically attack when hit by another player.
Handlers.add(
    "ReturnAttack",
    Handlers.utils.hasMatchingTag("Action", "Hit"),
    function(msg)
        if not InAction then -- InAction logic added
            InAction = true  -- InAction logic added
            local playerEnergy = LatestGameState.Players[ao.id].energy
            if playerEnergy == undefined then
                print(colors.red .. "Unable to read energy." .. colors.reset)
                ao.send({ Target = Game, Action = "Attack-Failed", Reason = "Unable to read energy." })
            elseif playerEnergy == 0 then
                print(colors.red .. "Player has insufficient energy." .. colors.reset)
                ao.send({ Target = Game, Action = "Attack-Failed", Reason = "Player has no energy." })
            else
                print(colors.red .. "Returning attack." .. colors.reset)
                ao.send({ Target = Game, Action = "PlayerAttack", Player = ao.id, AttackEnergy = tostring(playerEnergy * 0.4) }) -- Attack with 40% energy
            end
            InAction = false -- InAction logic added
            ao.send({ Target = ao.id, Action = "Tick" })
        else
            print("Previous action still in progress. Skipping.")
        end
    end
)

-- Handler to simulate deceptive behavior.
Handlers.add(
    "SimulateDeception",
    Handlers.utils.hasMatchingTag("Action", "SimulateDeception"),
    function()
        simulateDeception()
    end
)
