---@diagnostic disable

package.preload["mocks"] = function() return dofile("spec/mocks.lua") end
package.preload["state"] = function() return dofile("state.lua") end

describe("PaperWM.state persistence", function()
    local Mocks = require("mocks")
    Mocks.init_mocks()

    local State = require("state")

    local mock_paperwm = Mocks.get_mock_paperwm({ State = State })
    local mock_window = Mocks.mock_window

    before_each(function()
        State.init(mock_paperwm)
        Mocks.clear_window_registry()
        hs.settings.clear("PaperWM_layout")
    end)

    describe("State.save()", function()
        it("saves empty state", function()
            State.save()
            local data = hs.settings.get("PaperWM_layout")
            assert.is_not_nil(data)
            assert.are.same({}, data.monocle_spaces)
            assert.are.same({}, data.spaces)
        end)

        it("saves monocle spaces", function()
            State.monocle_spaces[1] = true
            State.monocle_spaces[3] = true
            State.save()

            local data = hs.settings.get("PaperWM_layout")
            table.sort(data.monocle_spaces)
            assert.are.same({ 1, 3 }, data.monocle_spaces)
        end)

        it("saves single-column layout", function()
            local win1 = mock_window(101, "Win 1")
            local win2 = mock_window(102, "Win 2")
            State.windowList(1)[1] = { win1, win2 }

            State.save()
            local data = hs.settings.get("PaperWM_layout")
            assert.equals(1, #data.spaces)
            assert.equals(1, #data.spaces[1].columns)
            assert.are.same({ 101, 102 }, data.spaces[1].columns[1].windows)
        end)

        it("saves multi-column layout", function()
            local win1 = mock_window(101, "Win 1")
            local win2 = mock_window(102, "Win 2")
            local win3 = mock_window(103, "Win 3")
            State.windowList(1)[1] = { win1 }
            State.windowList(1)[2] = { win2, win3 }

            State.save()
            local data = hs.settings.get("PaperWM_layout")
            assert.equals(2, #data.spaces[1].columns)
            assert.are.same({ 101 }, data.spaces[1].columns[1].windows)
            assert.are.same({ 102, 103 }, data.spaces[1].columns[2].windows)
        end)

        it("saves stacked column flag", function()
            local win1 = mock_window(101, "Win 1")
            local win2 = mock_window(102, "Win 2")
            State.windowList(1)[1] = { win1, win2 }
            State.toggleColumnStack(1, 1)

            State.save()
            local data = hs.settings.get("PaperWM_layout")
            assert.is_true(data.spaces[1].columns[1].stacked)
        end)

        it("saves multiple spaces", function()
            local win1 = mock_window(101, "Win 1")
            local win2 = mock_window(102, "Win 2")
            State.windowList(1)[1] = { win1 }
            State.windowList(2)[1] = { win2 }

            State.save()
            local data = hs.settings.get("PaperWM_layout")
            assert.equals(2, #data.spaces)
        end)
    end)

    describe("State.restore()", function()
        it("restores monocle spaces", function()
            local win1 = mock_window(101, "Win 1")
            Mocks.register_window(win1)
            State.windowList(1)[1] = { win1 }

            -- Save state with monocle
            State.monocle_spaces[1] = true
            State.save()

            -- Clear and rebuild minimal state
            State.clear()
            State.windowList(1)[1] = { win1 }
            assert.is_false(State.isMonocle(1))

            State.restore()
            assert.is_true(State.isMonocle(1))
        end)

        it("restores column groupings", function()
            local win1 = mock_window(101, "Win 1")
            local win2 = mock_window(102, "Win 2")
            Mocks.register_window(win1)
            Mocks.register_window(win2)

            -- Save: both windows in one column
            State.windowList(1)[1] = { win1, win2 }
            State.save()

            -- Clear and put windows in separate columns
            State.clear()
            State.windowList(1)[1] = { win1 }
            State.windowList(1)[2] = { win2 }

            State.restore()

            -- Should be back in one column
            local columns = State.windowList(1)
            assert.equals(1, #columns)
            assert.equals(2, #State.windowList(1, 1))
        end)

        it("restores stacked flags", function()
            local win1 = mock_window(101, "Win 1")
            local win2 = mock_window(102, "Win 2")
            Mocks.register_window(win1)
            Mocks.register_window(win2)

            State.windowList(1)[1] = { win1, win2 }
            State.toggleColumnStack(1, 1)
            State.save()

            State.clear()
            State.windowList(1)[1] = { win1, win2 }

            State.restore()
            assert.is_true(State.isColumnStacked(1, 1))
        end)

        it("restores window ordering", function()
            local win1 = mock_window(101, "Win 1")
            local win2 = mock_window(102, "Win 2")
            local win3 = mock_window(103, "Win 3")
            Mocks.register_window(win1)
            Mocks.register_window(win2)
            Mocks.register_window(win3)

            -- Save order: col1=[win3], col2=[win1], col3=[win2]
            State.windowList(1)[1] = { win3 }
            State.windowList(1)[2] = { win1 }
            State.windowList(1)[3] = { win2 }
            State.save()

            -- Clear and put windows in different order
            State.clear()
            State.windowList(1)[1] = { win1 }
            State.windowList(1)[2] = { win2 }
            State.windowList(1)[3] = { win3 }

            State.restore()

            -- Should restore saved order
            local idx1 = State.windowIndex(win3)
            local idx2 = State.windowIndex(win1)
            local idx3 = State.windowIndex(win2)
            assert.equals(1, idx1.col)
            assert.equals(2, idx2.col)
            assert.equals(3, idx3.col)
        end)

        it("skips missing windows", function()
            local win1 = mock_window(101, "Win 1")
            local win2 = mock_window(102, "Win 2")
            Mocks.register_window(win1)
            -- win2 NOT registered (simulates closed app)

            State.windowList(1)[1] = { win1, win2 }
            State.save()

            State.clear()
            State.windowList(1)[1] = { win1 }

            State.restore()

            -- win1 should still be tiled
            assert.is_true(State.isTiled(101))
            assert.is_false(State.isTiled(102))
        end)

        it("appends new windows at end", function()
            local win1 = mock_window(101, "Win 1")
            local win2 = mock_window(102, "Win 2 (new)")
            Mocks.register_window(win1)
            Mocks.register_window(win2)

            -- Save with only win1
            State.windowList(1)[1] = { win1 }
            State.save()

            -- Clear and add both windows
            State.clear()
            State.windowList(1)[1] = { win1 }
            State.windowList(1)[2] = { win2 }

            State.restore()

            -- win1 in col 1, win2 appended after
            local idx1 = State.windowIndex(win1)
            local idx2 = State.windowIndex(win2)
            assert.equals(1, idx1.col)
            assert.is_true(idx2.col > idx1.col)
        end)

        it("handles nil saved state", function()
            local win1 = mock_window(101, "Win 1")
            State.windowList(1)[1] = { win1 }

            -- No saved state
            assert.has_no.errors(function() State.restore() end)
            assert.is_true(State.isTiled(101))
        end)

        it("handles empty saved state", function()
            hs.settings.set("PaperWM_layout", {})
            local win1 = mock_window(101, "Win 1")
            State.windowList(1)[1] = { win1 }

            assert.has_no.errors(function() State.restore() end)
            assert.is_true(State.isTiled(101))
        end)

        it("skips empty columns when all windows are gone", function()
            local win1 = mock_window(101, "Win 1")
            local win2 = mock_window(102, "Win 2")
            -- Neither registered (both gone)

            State.windowList(1)[1] = { win1 }
            State.windowList(1)[2] = { win2 }
            State.save()

            State.clear()
            -- No windows to restore into

            State.restore()

            -- No columns should exist
            local columns = State.windowList(1)
            assert.equals(0, #columns)
        end)

        it("clears stacked flag when column has 1 remaining window", function()
            local win1 = mock_window(101, "Win 1")
            local win2 = mock_window(102, "Win 2")
            Mocks.register_window(win1)
            -- win2 NOT registered (gone)

            State.windowList(1)[1] = { win1, win2 }
            State.toggleColumnStack(1, 1)
            State.save()

            State.clear()
            State.windowList(1)[1] = { win1 }

            State.restore()
            assert.is_false(State.isColumnStacked(1, 1))
        end)
    end)

    describe("State.rebuildSpace()", function()
        it("replaces window_list for a space", function()
            local win1 = mock_window(101, "Win 1")
            local win2 = mock_window(102, "Win 2")
            State.windowList(1)[1] = { win1 }

            local new_columns = { { win2 } }
            State.rebuildSpace(1, new_columns)

            local columns = State.windowList(1)
            assert.equals(1, #columns)
            assert.equals(win2, State.windowList(1, 1, 1))
        end)

        it("updates index_table after rebuild", function()
            local win1 = mock_window(101, "Win 1")
            local win2 = mock_window(102, "Win 2")
            State.windowList(1)[1] = { win1 }

            State.rebuildSpace(1, { { win2 } })

            local idx = State.windowIndex(win2)
            assert.is_not_nil(idx)
            assert.equals(1, idx.col)
            assert.equals(1, idx.row)
        end)
    end)

    describe("State.startAutoSave() / State.stopAutoSave()", function()
        it("startAutoSave creates a timer", function()
            State.startAutoSave()
            -- Should not error
            State.stopAutoSave()
        end)

        it("stopAutoSave stops the timer", function()
            State.startAutoSave()
            -- Should not error when stopping
            assert.has_no.errors(function() State.stopAutoSave() end)
        end)

        it("stopAutoSave is safe without prior startAutoSave", function()
            assert.has_no.errors(function() State.stopAutoSave() end)
        end)
    end)
end)
