---@diagnostic disable

package.preload["mocks"] = function() return dofile("spec/mocks.lua") end
package.preload["tiling"] = function() return dofile("tiling.lua") end
package.preload["windows"] = function() return dofile("windows.lua") end
package.preload["state"] = function() return dofile("state.lua") end
package.preload["floating"] = function() return dofile("floating.lua") end

describe("PaperWM.tiling", function()
    local Mocks = require("mocks")
    Mocks.init_mocks()

    local Tiling = require("tiling")
    local Windows = require("windows")
    local State = require("state")
    local Floating = require("floating")

    local mock_paperwm = Mocks.get_mock_paperwm({ Tiling = Tiling, Windows = Windows, State = State, Floating = Floating })
    local mock_window = Mocks.mock_window

    local focused_window

    before_each(function()
        -- Reset state before each test
        State.init(mock_paperwm)
        Windows.init(mock_paperwm)
        Floating.init(mock_paperwm)
        Tiling.init(mock_paperwm)
        hs.window.focusedWindow = function() return focused_window end
    end)

    describe("tileSpace", function()
        it("should tile a single window to fit in the screen with external_bar", function()
            mock_paperwm.external_bar = { top = 40 }
            local win = mock_window(101, "Test Window", { x = 0, y = 0, w = 100, h = 100 })
            Windows.addWindow(win)
            focused_window = win

            Tiling.tileSpace(1)

            local frame = win:frame()
            assert.are.equal(8, frame.x)
            assert.are.equal(48, frame.y)
            assert.are.equal(100, frame.w)
            assert.are.equal(644, frame.h)
        end)
        it("should tile two windows side-by-side with external_bar", function()
            mock_paperwm.external_bar = { top = 40 }
            local win1 = mock_window(101, "Window 1", { x = 0, y = 0, w = 100, h = 100 })
            local win2 = mock_window(102, "Window 2", { x = 200, y = 0, w = 100, h = 100 })
            Windows.addWindow(win1)
            Windows.addWindow(win2)
            focused_window = win1

            Tiling.tileSpace(1)

            local frame1 = win1:frame()
            assert.are.equal(8, frame1.x)
            assert.are.equal(48, frame1.y)
            assert.are.equal(100, frame1.w)
            assert.are.equal(644, frame1.h)

            local frame2 = win2:frame()
            assert.are.equal(108, frame2.x)
            assert.are.equal(48, frame2.y)
            assert.are.equal(100, frame2.w)
            assert.are.equal(692, frame2.y2) -- tileColumn sets y2
        end)
        it("should tile a single window to fit in the screen", function()
            mock_paperwm.external_bar = nil
            local win = mock_window(101, "Test Window", { x = 0, y = 0, w = 100, h = 100 })
            Windows.addWindow(win)
            focused_window = win

            Tiling.tileSpace(1)

            local frame = win:frame()
            assert.are.equal(8, frame.x)
            assert.are.equal(40, frame.y)
            assert.are.equal(100, frame.w)
            assert.are.equal(652, frame.h)
        end)

        it("should tile two windows side-by-side", function()
            mock_paperwm.external_bar = nil
            local win1 = mock_window(101, "Window 1", { x = 0, y = 0, w = 100, h = 100 })
            local win2 = mock_window(102, "Window 2", { x = 200, y = 0, w = 100, h = 100 })
            Windows.addWindow(win1)
            Windows.addWindow(win2)
            focused_window = win1

            Tiling.tileSpace(1)

            local frame1 = win1:frame()
            assert.are.equal(8, frame1.x)
            assert.are.equal(40, frame1.y)
            assert.are.equal(100, frame1.w)
            assert.are.equal(652, frame1.h)

            local frame2 = win2:frame()
            assert.are.equal(108, frame2.x)
            assert.are.equal(40, frame2.y)
            assert.are.equal(100, frame2.w)
            assert.are.equal(692, frame2.y2) -- tileColumn sets y2
        end)
    end)

    describe("tileColumn stacked", function()
        it("should give all windows full height when stacked", function()
            local win1 = mock_window(101, "Window 1", { x = 0, y = 0, w = 100, h = 100 })
            local win2 = mock_window(102, "Window 2", { x = 0, y = 0, w = 100, h = 100 })
            local bounds = { x = 10, y = 20, x2 = 110, y2 = 780 }

            Tiling.tileColumn({ win1, win2 }, bounds, nil, nil, nil, nil, true)

            local frame1 = win1:frame()
            assert.are.equal(10, frame1.x)
            assert.are.equal(20, frame1.y)
            assert.are.equal(760, frame1.h)
            assert.are.equal(100, frame1.w)

            local frame2 = win2:frame()
            assert.are.equal(10, frame2.x)
            assert.are.equal(20, frame2.y)
            assert.are.equal(760, frame2.h)
            assert.are.equal(100, frame2.w)
        end)

        it("should not advance bounds.y when stacked", function()
            local win1 = mock_window(101, "Window 1", { x = 0, y = 0, w = 100, h = 100 })
            local win2 = mock_window(102, "Window 2", { x = 0, y = 0, w = 100, h = 100 })
            local bounds = { x = 10, y = 20, x2 = 110, y2 = 780 }

            Tiling.tileColumn({ win1, win2 }, bounds, nil, nil, nil, nil, true)

            -- bounds.y should not have been advanced
            assert.are.equal(20, bounds.y)
        end)
    end)

    describe("tileSpace stacked", function()
        it("should tile stacked anchor column with full height windows", function()
            mock_paperwm.external_bar = nil
            local win1 = mock_window(101, "Window 1", { x = 0, y = 0, w = 100, h = 100 })
            local win2 = mock_window(102, "Window 2", { x = 0, y = 108, w = 100, h = 100 })
            Windows.addWindow(win1)
            table.insert(State.windowList(1, 1), win2)
            focused_window = win1

            -- stack the column
            State.toggleColumnStack(1, 1)

            Tiling.tileSpace(1)

            local frame1 = win1:frame()
            local frame2 = win2:frame()
            -- both should have full canvas height
            assert.are.equal(frame1.y, frame2.y)
            assert.are.equal(frame1.h, frame2.h)
        end)

        it("should not affect other columns when one is stacked", function()
            mock_paperwm.external_bar = nil
            local win1 = mock_window(101, "Window 1", { x = 0, y = 0, w = 100, h = 100 })
            local win2 = mock_window(102, "Window 2", { x = 0, y = 108, w = 100, h = 100 })
            local win3 = mock_window(103, "Window 3", { x = 200, y = 0, w = 100, h = 100 })
            local win4 = mock_window(104, "Window 4", { x = 200, y = 108, w = 100, h = 100 })

            -- column 1: win1, win2 (stacked)
            Windows.addWindow(win1)
            table.insert(State.windowList(1, 1), win2)
            -- column 2: win3, win4 (normal)
            table.insert(State.windowList(1), { win3, win4 })

            focused_window = win1
            State.toggleColumnStack(1, 1)

            Tiling.tileSpace(1)

            -- stacked column: both full height
            local frame1 = win1:frame()
            local frame2 = win2:frame()
            assert.are.equal(frame1.y, frame2.y)
            assert.are.equal(frame1.h, frame2.h)

            -- normal column: different y positions
            local frame3 = win3:frame()
            local frame4 = win4:frame()
            assert.are_not.equal(frame3.y, frame4.y)
        end)
    end)

    describe("tileColumn", function()
        it("should tile a single window to fit in the bounds", function()
            local win = mock_window(101, "Test Window", { x = 0, y = 0, w = 100, h = 100 })
            local bounds = { x = 10, y = 20, w = 100, h = 760, x2 = 110, y2 = 780 }

            Tiling.tileColumn({ win }, bounds)

            local frame = win:frame()
            assert.are.equal(10, frame.x)
            assert.are.equal(20, frame.y)
            assert.are.equal(100, frame.w)
            assert.are.equal(780, frame.y2)
        end)

        it("should tile two windows top to bottom in bounds", function()
            local win1 = mock_window(101, "Test Window", { x = 0, y = 0, w = 100, h = 100 })
            local win2 = mock_window(102, "Test Window", { x = 200, y = 0, w = 100, h = 100 })
            local bounds = { x = 10, y = 20, w = 100, h = 760, x2 = 110, y2 = 780 }

            Tiling.tileColumn({ win1, win2 }, bounds)

            local frame1 = win1:frame()
            assert.are.equal(10, frame1.x)
            assert.are.equal(20, frame1.y)
            assert.are.equal(100, frame1.w)
            assert.are.equal(100, frame1.y2)

            local frame2 = win2:frame()
            assert.are.equal(10, frame2.x)
            assert.are.equal(108, frame2.y)
            assert.are.equal(100, frame2.w)
            assert.are.equal(780, frame2.y2)
        end)
    end)
end)
