local FakeCache = {}
local DirtyTables = {}


local resourceName = GetCurrentResourceName()

onResourceStart(function()
    resourceName = GetCurrentResourceName()
end, true)

onResourceStop(function()

    for tableName, data in pairs(FakeCache) do
        local serialized = "return " .. SerializeTable(data) .. "\n"
        local filePath = "database/" .. tableName .. ".lua"

        local success, err = SaveResourceFile(resourceName, filePath, serialized, -1)
        if success then
            print("[FakeSQL] Saved table on shutdown:", tableName)
        else
            print("[FakeSQL] ERROR saving table on shutdown:", tableName, err)
        end
    end

end, true)


local function SerializeTable(tbl, indent)
    indent = indent or 0
    local lines = {}
    local prefix = string.rep("  ", indent)
    table.insert(lines, "{")
    local keys = {}
    for k in pairs(tbl) do table.insert(keys, k) end
    table.sort(keys, function(a, b)
        if type(a) == type(b) then return a < b end
        return tostring(a) < tostring(b)
    end)
    for i, k in ipairs(keys) do
        local v = tbl[k]
        local key
        if type(k) == "string" then
            key = string.format("[%q]", k)
        else
            key = "[" .. tostring(k) .. "]"
        end

        local value

        if type(v) == "table" then
            if v.x and v.y and v.z and
               type(v.x) == "number" and
               type(v.y) == "number" and
               type(v.z) == "number" then
                value = string.format("{x=%f,y=%f,z=%f}", v.x, v.y, v.z)
            else
                value = SerializeTable(v, indent + 1)
            end

        elseif type(v) == "userdata" then
            value = "nil --[[userdata serialization not implemented yet]]"

        elseif type(v) == "string" then
            value = string.format("%q", v)

        elseif type(v) == "number" or type(v) == "boolean" then
            value = tostring(v)

        elseif type(v) == "vector2" then
            value = string.format("vector2(%f, %f)", v.x, v.y)
        elseif type(v) == "vector3" then
            value = string.format("vector3(%f, %f, %f)", v.x, v.y, v.z)
        elseif type(v) == "vector4" then
            value = string.format("vector4(%f, %f, %f, %f)", v.x, v.y, v.z, v.w)

        else
            value = "nil --[[unsupported type: " .. type(v) .. "]]"
        end

        local comma = i < #keys and "," or ""
        table.insert(lines, prefix .. "  " .. key .. " = " .. value .. comma)
    end
    table.insert(lines, prefix .. "}")
    return table.concat(lines, "\n")
end

CreateThread(function()
    local interval = 300 -- Every 5 minutes
    while true do
        Wait(interval * 1000)
        for tableName, _ in pairs(DirtyTables) do
            if FakeCache[tableName] then
                local serialized = "return " .. SerializeTable(FakeCache[tableName]) .. "\n"
                local filePath = "database/" .. tableName .. ".lua"

                local success, err = SaveResourceFile(resourceName, filePath, serialized, -1)
                if success then
                    print("[FakeSQL] Auto-saved table:", tableName)
                    DirtyTables[tableName] = nil
                else
                    print("[FakeSQL] Auto-save ERROR:", tableName, err)
                end
            end
        end
    end
end)


-- Exports

--- Usage:
--- exports['tss-fakesql']:CreateTable("vehicles")
exports("CreateTable", function(tableName)
    local filePath = "database/" .. tableName .. ".lua"

    local content = LoadResourceFile(resourceName, filePath)
    if content then
        print("[FakeSQL] Table already exists:", tableName)
        return
    end

    local emptyTable = "return {}\n"
    local success, err = SaveResourceFile(resourceName, filePath, emptyTable, -1)
    if not success then
        print("[FakeSQL] ERROR creating table:", tableName, err)
        return
    end

    print("[FakeSQL] Created table:", tableName)
end)

--- Usage:
--- local vehicles = exports['tss-fakesql']:LoadTable("vehicles")
exports("LoadTable", function(tableName)
    if FakeCache[tableName] then
        return FakeCache[tableName]
    end

    local filePath = "database/" .. tableName .. ".lua"

    local content = LoadResourceFile(resourceName, filePath)
    if not content then
        print("[FakeSQL] Could not find table file:", tableName)
        return nil
    end

    local chunk, err = load(content, filePath)
    if not chunk then
        print("[FakeSQL] Load error for table:", tableName, err)
        return nil
    end

    local ok, result = pcall(chunk)
    if not ok then
        print("[FakeSQL] Execution error for table:", tableName, result)
        return nil
    end

    if type(result) == "table" then
        FakeCache[tableName] = result
        return result
    else
        print("[FakeSQL] Unexpected result type for table:", tableName, type(result))
        return nil
    end
end)


--- Usage:
--- exports['tss-fakesql']:SaveTable("vehicles", vehicles)
exports("SaveTable", function(tableName, data)
    local filePath = "database/" .. tableName .. ".lua"

    local serialized = "return " .. SerializeTable(data) .. "\n"
    local success, err = SaveResourceFile(resourceName, filePath, serialized, -1)
    if not success then
        print("[FakeSQL] ERROR saving table:", tableName, err)
    end
end)

--- Deletes the ENTIRE Table (only use when you want to clear EVERYTHING)
--- Usage:
--- exports['tss-fakesql']:DeleteTable("vehicles")
exports("DeleteTable", function(tableName)
    local filePath = "database/" .. tableName .. ".lua"

    local absPath = GetResourcePath(resourceName) .. "/" .. filePath
    local success, err = os.remove(absPath)
    if success then
        print("[FakeSQL] Deleted table:", tableName)
    else
        print("[FakeSQL] Failed to delete table:", tableName, err)
    end
end)

--- Usage:
--- exports['tss-fakesql']:InsertRow("vehicles", { plate = "ABC123", owner = "citizenid123", model = "adder", coords = vector3(0,0,0) })
exports("InsertRow", function(tableName, row)
    local data = exports['tss-fakesql']:LoadTable(tableName)
    if not data then
        print("[FakeSQL] InsertRow aborted: could not load table '" .. tableName .. "'")
        return
    end

    table.insert(data, row)
    DirtyTables[tableName] = true
end)


--- Usage:
--- exports['tss-fakesql']:UpdateRows("vehicles", function(row) 
---     return row.plate == "ABC123" 
--- end, function(row) 
---     row.owner = "newownerid" 
--- end)
exports("UpdateRows", function(tableName, conditionFunc, updateFunc)
    local data = exports['tss-fakesql']:LoadTable(tableName)
    if not data then
        print("[FakeSQL] UpdateRows aborted: could not load table '" .. tableName .. "'")
        return
    end

    for i, row in ipairs(data) do
        if conditionFunc(row) then
            updateFunc(row)
            DirtyTables[tableName] = true
        end
    end
end)


--- Usage:
--- local plate = "ABC123"
--- exports['tss-fakesql']:DeleteRows("vehicles", function(row)
---     return row.plate == plate 
--- end)
exports("DeleteRows", function(tableName, conditionFunc)
    local data = exports['tss-fakesql']:LoadTable(tableName)
    if not data then
        print("[FakeSQL] DeleteRows aborted: could not load table '" .. tableName .. "'")
        return
    end

    local newData = {}
    for _, row in ipairs(data) do
        if not conditionFunc(row) then
            table.insert(newData, row)
        else
            DirtyTables[tableName] = true
        end
    end

    -- Replace cached data
    FakeCache[tableName] = newData
end)


--- Usage example:
--- exports['tss-fakesql']:Query("vehicles", "owner", "citizenid123", function(results)
---     if results and #results > 0 then
---         for _, vehicle in ipairs(results) do
---             print("Vehicle plate:", vehicle.plate)
---         end
---     else
---         print("No vehicles found for that owner")
---     end
--- end)

exports("Query", function(tableName, rowName, expectedValue, cb)
    local data = exports['tss-fakesql']:LoadTable(tableName)
    if not data then
        print("[FakeSQL] Query error: table '" .. tableName .. "' not found")
        cb({})
        return
    end

    local results = {}
    for _, row in ipairs(data) do
        if row[rowName] == expectedValue then
            table.insert(results, row)
        end
    end

    cb(results)
end)
