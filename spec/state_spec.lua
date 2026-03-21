---@diagnostic disable

package.preload["mocks"] = function() return dofile("spec/mocks.lua") end
package.preload["state"] = function() return dofile("state.lua") end

describe("PaperWM.state", function()
    local Mocks = require("mocks")
    Mocks.init_mocks()

    local State = require("state")

    local mock_paperwm = Mocks.get_mock_paperwm({ State = State })

    before_each(function()
        -- Reset state before each test
        State.init(mock_paperwm)
    end)

    describe("column stack", function()
        it("should not be stacked by default", function()
            local space = 1
            local win = Mocks.mock_window(123, "Window")
            State.windowList(space)[1] = { win }

            assert.is_false(State.isColumnStacked(space, 1))
        end)

        it("should toggle stack on and off", function()
            local space = 1
            local win1 = Mocks.mock_window(101, "Window 1")
            local win2 = Mocks.mock_window(102, "Window 2")
            State.windowList(space)[1] = { win1, win2 }

            State.toggleColumnStack(space, 1)
            assert.is_true(State.isColumnStacked(space, 1))

            State.toggleColumnStack(space, 1)
            assert.is_false(State.isColumnStacked(space, 1))
        end)

        it("should clear stacked flag for a specific window", function()
            local space = 1
            local win1 = Mocks.mock_window(101, "Window 1")
            local win2 = Mocks.mock_window(102, "Window 2")
            State.windowList(space)[1] = { win1, win2 }

            State.toggleColumnStack(space, 1)
            assert.is_true(State.isColumnStacked(space, 1))

            State.clearStacked(101)
            State.clearStacked(102)
            assert.is_false(State.isColumnStacked(space, 1))
        end)

        it("should set stacked flag for a specific window", function()
            local space = 1
            local win = Mocks.mock_window(101, "Window")
            State.windowList(space)[1] = { win }

            State.setStacked(101)
            assert.is_true(State.isColumnStacked(space, 1))
        end)

        it("should return false for non-existent column", function()
            assert.is_false(State.isColumnStacked(1, 99))
        end)

        it("should be cleared on State.clear()", function()
            local space = 1
            local win = Mocks.mock_window(101, "Window")
            State.windowList(space)[1] = { win }
            State.toggleColumnStack(space, 1)
            assert.is_true(State.isColumnStacked(space, 1))

            State.clear()
            State.windowList(space)[1] = { win }
            assert.is_false(State.isColumnStacked(space, 1))
        end)

        it("should include stacked_windows in get() output", function()
            local space = 1
            local win = Mocks.mock_window(101, "Window")
            State.windowList(space)[1] = { win }
            State.toggleColumnStack(space, 1)

            local state = State.get()
            assert.is_not_nil(state.stacked_windows)
            assert.is_true(state.stacked_windows[101])
        end)
    end)

    describe("isTiled", function()
        it("should return true for a tiled window and false for a floating window", function()
            -- To add a window to index_table, we need to add it to window_list
            local space = 1
            local win = Mocks.mock_window(123, "Tiled Window")
            local window_list = State.windowList(space)
            window_list[1] = { win }

            assert.is_true(State.isTiled(123))
            assert.is_false(State.isTiled(456))
        end)
    end)
end)
