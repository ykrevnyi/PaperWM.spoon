local Watcher <const> = hs.uielement.watcher

local State = {}
State.__index = State

---private state
local window_list = {} -- 3D array of tiles in order of [space][x][y]
local index_table = {} -- dictionary of {space, x, y} with window id for keys
local ui_watchers = {} -- dictionary of uielement watchers with window id for keys
local x_positions = {} -- dictionary of horizontal positions with [space][id] for keys
local stacked_windows = {} -- dictionary of boolean with window id for keys
---public state
State.is_floating = {} -- dictionary of boolean with window id for keys
State.monocle_spaces = {} -- dictionary of boolean with space id for keys
State.prev_focused_window = nil ---@type Window|nil
State.pending_window = nil ---@type Window|nil

---initialize module with reference to PaperWM
---@param paperwm PaperWM
function State.init(paperwm)
    State.PaperWM = paperwm
    State.clear()
end

---clear all internal state
function State.clear()
    window_list = {}
    index_table = {}
    ui_watchers = {}
    x_positions = {}
    State.is_floating = {}
    State.monocle_spaces = {}
    stacked_windows = {}
    State.prev_focused_window = nil
    State.pending_window = nil
end

---walk through all tiled windows in a space and update the index table
---@param space Space
local function update_index(space)
    for col, rows in ipairs(window_list[space] or {}) do
        for row, window in ipairs(rows) do
            index_table[window:id()] = { space = space, col = col, row = row }
        end
    end
end

---get a proxy table for a space, column, or row of tiled windows
---the proxy table can be used to iterate over, insert, remove, and access
---windows while keeping track of internal state
---@param space Space get a list of columns for a space
---@param column number|nil get a list of windows for a column
---@param row number|nil get a window for a row in a column
---@return Window[][]|Window[]|Window|nil
function State.windowList(space, column, row)
    if space then
        local columns = window_list[space]
        if column then
            local rows = columns and columns[column]
            if row then
                return rows and rows[row]
            end

            return rows and setmetatable({}, {
                __index = function(_, row) return rows[row] end,
                __newindex = function(_, row, window)
                    rows[row] = window
                    if not next(columns[column]) then table.remove(columns, column) end
                    if not next(window_list[space]) then window_list[space] = nil end
                    update_index(space)
                end,
                __len = function(_) return #rows end,
                __pairs = function(_) return pairs(rows) end,
                __ipairs = function(_) return ipairs(rows) end,
            })
        end

        return setmetatable({}, columns and {
            __index = function(_, column) return columns[column] end,
            __newindex = function(_, column, rows)
                -- space is guaranteed to exist here
                columns[column] = rows -- add a new column
                -- handle case where all columns have been removed from a space
                if not next(window_list[space]) then window_list[space] = nil end
                update_index(space)
            end,
            __len = function(_) return #columns end,
            __pairs = function(_) return pairs(columns) end,
            __ipairs = function(_) return ipairs(columns) end,
        } or { -- metatable for a nil space
            __newindex = function(_, column, rows)
                -- space may not exist here so create it
                if not window_list[space] then window_list[space] = {} end
                window_list[space][column] = rows
                update_index(space)
            end,
        })
    end
end

---get the index { space, col, row } of a tiled window
---@param window Window
---@param remove boolean|nil Set to true to remove the entry
---@return table|nil
function State.windowIndex(window, remove)
    local index = index_table[window:id()]
    if remove then index_table[window:id()] = nil end
    return index
end

---create and start a UI watcher for a new window
---@param window Window
function State.uiWatcherCreate(window)
    local id = window:id()
    ui_watchers[id] = window:newWatcher(
        function(window, event, _, self)
            State.PaperWM.events.windowEventHandler(window, event, self)
        end, State.PaperWM)
    State.uiWatcherStart(id)
end

---delete a UI watcher
---@param id number Window ID
function State.uiWatcherDelete(id)
    State.uiWatcherStop(id)
    ui_watchers[id] = nil
end

---start a UI watcher
---@param id number Window ID
function State.uiWatcherStart(id)
    local watcher = ui_watchers[id]
    if watcher then watcher:start({ Watcher.windowMoved, Watcher.windowResized }) end
end

---stop a UI watcher
---@param id number Window ID
function State.uiWatcherStop(id)
    local watcher = ui_watchers[id]
    if watcher then watcher:stop() end
end

---stop all UI watchers
function State.uiWatcherStopAll()
    for _, watcher in pairs(ui_watchers) do watcher:stop() end
end

---return a table that provides accessor methods to x_positions via a metatable
---@param space Space
function State.xPositions(space)
    return setmetatable({}, {
        __index = function(_, id) return (x_positions[space] or {})[id] end,
        __newindex = function(_, id, x)
            if not x_positions[space] then x_positions[space] = {} end
            x_positions[space][id] = x
            if not next(x_positions[space]) then x_positions[space] = nil end
        end,
        __pairs = function(_) return pairs(x_positions[space] or {}) end,
    })
end

---check if monocle mode is enabled for a space
---@param space Space
---@return boolean
function State.isMonocle(space)
    return State.monocle_spaces[space] or false
end

---toggle monocle mode for a space
---@param space Space
function State.toggleMonocle(space)
    State.monocle_spaces[space] = not State.isMonocle(space) or nil
end

---check if a column is in stack mode
---a column is stacked if any window in it has the stacked flag
---@param space Space
---@param col number
---@return boolean
function State.isColumnStacked(space, col)
    local column = State.windowList(space, col)
    if not column then return false end
    for _, window in ipairs(column) do
        if stacked_windows[window:id()] then return true end
    end
    return false
end

---toggle stack mode for all windows in a column
---@param space Space
---@param col number
function State.toggleColumnStack(space, col)
    local column = State.windowList(space, col)
    if not column then return end
    local is_stacked = State.isColumnStacked(space, col)
    for _, window in ipairs(column) do
        if is_stacked then
            stacked_windows[window:id()] = nil
        else
            stacked_windows[window:id()] = true
        end
    end
end

---set the stacked flag for a specific window
---@param id number Window ID
function State.setStacked(id)
    stacked_windows[id] = true
end

---clear the stacked flag for a specific window
---@param id number Window ID
function State.clearStacked(id)
    stacked_windows[id] = nil
end

---check for the presence of a window in the tiled list
---@param id number Window ID
---@return boolean
function State.isTiled(id)
    return index_table[id] ~= nil
end

---return internal state for debugging purposes
function State.get()
    return {
        window_list = window_list,
        index_table = index_table,
        ui_watchers = ui_watchers,
        x_positions = x_positions,
        stacked_windows = stacked_windows,
        is_floating = State.is_floating,
        prev_focused_window = State.prev_focused_window,
        pending_window = State.pending_window,
    }
end

---constants
local LayoutKey <const> = "PaperWM_layout"
local save_timer = nil

---directly set the columns for a space and update the index
---@param space Space
---@param new_columns Window[][]
function State.rebuildSpace(space, new_columns)
    window_list[space] = new_columns
    update_index(space)
end

---save all layout state to hs.settings
function State.save()
    local data = { monocle_spaces = {}, spaces = {} }
    for space, _ in pairs(State.monocle_spaces) do
        table.insert(data.monocle_spaces, space)
    end
    for space, columns in pairs(window_list) do
        local space_data = { space = space, columns = {} }
        for col_idx, column in ipairs(columns) do
            local col_data = {
                stacked = State.isColumnStacked(space, col_idx),
                windows = {},
            }
            for _, window in ipairs(column) do
                table.insert(col_data.windows, window:id())
            end
            table.insert(space_data.columns, col_data)
        end
        table.insert(data.spaces, space_data)
    end
    hs.settings.set(LayoutKey, data)
end

---restore layout state from hs.settings
function State.restore()
    local data = hs.settings.get(LayoutKey)
    if not data then return end

    -- restore monocle flags
    if data.monocle_spaces then
        for _, space in ipairs(data.monocle_spaces) do
            State.monocle_spaces[space] = true
        end
    end

    if not data.spaces then return end

    for _, space_data in ipairs(data.spaces) do
        local space = space_data.space
        local current_columns = window_list[space]
        if not current_columns then goto continue end

        -- collect all currently tiled windows in this space
        local available = {}
        for _, col in ipairs(current_columns) do
            for _, window in ipairs(col) do
                available[window:id()] = window
            end
        end

        -- rebuild columns from saved layout
        local new_columns = {}
        local placed = {}

        for _, col_data in ipairs(space_data.columns) do
            local column = {}
            for _, win_id in ipairs(col_data.windows) do
                local window = available[win_id]
                if window then
                    table.insert(column, window)
                    placed[win_id] = true
                end
            end
            if #column > 0 then
                -- apply stacked flag only if column has multiple windows
                if col_data.stacked and #column > 1 then
                    for _, window in ipairs(column) do
                        stacked_windows[window:id()] = true
                    end
                end
                table.insert(new_columns, column)
            end
        end

        -- append windows not in saved state
        for id, window in pairs(available) do
            if not placed[id] then
                table.insert(new_columns, { window })
            end
        end

        State.rebuildSpace(space, new_columns)
        State.PaperWM:tileSpace(space)

        ::continue::
    end
end

---start periodic auto-save timer
function State.startAutoSave()
    State.stopAutoSave()
    save_timer = hs.timer.doEvery(3, State.save)
end

---stop periodic auto-save timer
function State.stopAutoSave()
    if save_timer then
        save_timer:stop()
        save_timer = nil
    end
end

---pretty print the current state
function State.dump()
    local output = { "--- PaperWM State ---" }

    table.insert(output, "window_list:")
    for space, columns in pairs(window_list) do
        table.insert(output, string.format("  Space %s:", tostring(space)))
        for col_idx, column in ipairs(columns) do
            table.insert(output, string.format("    Column %d:", col_idx))
            for row_idx, window in ipairs(column) do
                table.insert(output, string.format("      Row %d: %s (%d)", row_idx, window:title(), window:id()))
            end
        end
    end

    table.insert(output, "\nindex_table:")
    for id, index in pairs(index_table) do
        table.insert(output, string.format("  Window ID %d: space=%s, col=%d, row=%d",
            id, tostring(index.space), index.col, index.row))
    end

    table.insert(output, "\nis_floating:")
    for id, floating in pairs(State.is_floating) do
        if floating then table.insert(output, string.format("  Window ID %d is floating", id)) end
    end

    table.insert(output, "\nstacked_windows:")
    for id, stacked in pairs(stacked_windows) do
        if stacked then table.insert(output, string.format("  Window ID %d is stacked", id)) end
    end

    table.insert(output, "\nx_positions:")
    for space, positions in pairs(x_positions) do
        table.insert(output, string.format("  Space %s:", tostring(space)))
        for id, x in pairs(positions) do
            table.insert(output, string.format("    Window %s (%d): x=%d", hs.window(id):title(), id, x))
        end
    end

    if State.prev_focused_window then
        table.insert(output, string.format("\nprev_focused_window: %s (%d)",
            State.prev_focused_window:title(),
            State.prev_focused_window:id()))
    else
        table.insert(output, "\nprev_focused_window: nil")
    end

    if State.pending_window then
        table.insert(output, string.format("pending_window: %s (%d)",
            State.pending_window:title(),
            State.pending_window:id()))
    else
        table.insert(output, "pending_window: nil")
    end

    table.insert(output, "---------------------")
    print(table.concat(output, "\n"))
end

return State
