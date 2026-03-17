local FakeCache = {}
local DirtyTables = {}

local RESOURCE_NAME = GetCurrentResourceName()
local AUTOSAVE_SECONDS = 300

local function log(message, ...)
    if select("#", ...) > 0 then
        message = message:format(...)
    end
    print(("[FakeSQL] %s"):format(message))
end

local function validateTableName(tableName)
    if type(tableName) ~= "string" or tableName == "" then
        return false, "tableName must be a non-empty string"
    end

    if not tableName:match("^[%w_-]+$") then
        return false, "tableName can only contain letters, numbers, _ and -"
    end

    return true
end

local function buildFilePath(tableName)
    return ("database/%s.lua"):format(tableName)
end

local function isVectorLike(value)
    local valueType = type(value)
    return valueType == "vector2" or valueType == "vector3" or valueType == "vector4"
end

local function serializeValue(value, indent, seen)
    local valueType = type(value)

    if isVectorLike(value) then
        if valueType == "vector2" then
            return ("vector2(%f, %f)"):format(value.x, value.y)
        elseif valueType == "vector3" then
            return ("vector3(%f, %f, %f)"):format(value.x, value.y, value.z)
        else
            return ("vector4(%f, %f, %f, %f)"):format(value.x, value.y, value.z, value.w)
        end
    end

    if valueType == "string" then
        return string.format("%q", value)
    end

    if valueType == "number" or valueType == "boolean" then
        return tostring(value)
    end

    if value == nil then
        return "nil"
    end

    if valueType == "table" then
        if seen[value] then
            return "nil --[[circular reference removed]]"
        end

        seen[value] = true
        local lines = {}
        local prefix = string.rep("  ", indent)

        lines[#lines + 1] = "{"

        local keys = {}
        for key in pairs(value) do
            keys[#keys + 1] = key
        end

        table.sort(keys, function(a, b)
            if type(a) == type(b) then
                return a < b
            end
            return tostring(a) < tostring(b)
        end)

        for index, key in ipairs(keys) do
            local serializedKey
            if type(key) == "string" then
                serializedKey = string.format("[%q]", key)
            else
                serializedKey = "[" .. tostring(key) .. "]"
            end

            local serialized = serializeValue(value[key], indent + 1, seen)
            local comma = index < #keys and "," or ""
            lines[#lines + 1] = ("%s  %s = %s%s"):format(prefix, serializedKey, serialized, comma)
        end

        lines[#lines + 1] = prefix .. "}"
        seen[value] = nil
        return table.concat(lines, "\n")
    end

    return ("nil --[[unsupported type: %s]]"):format(valueType)
end

local function serializeTable(tbl)
    return "return " .. serializeValue(tbl, 0, {}) .. "\n"
end

local function runtimeEnv()
    return {
        vector2 = vector2,
        vector3 = vector3,
        vector4 = vector4,
        tonumber = tonumber,
        tostring = tostring,
        math = math,
        string = string,
        table = table,
    }
end

local function markDirty(tableName)
    DirtyTables[tableName] = true
end

local function saveTableToFile(tableName, data)
    local filePath = buildFilePath(tableName)
    local serialized = serializeTable(data)
    local success, err = SaveResourceFile(RESOURCE_NAME, filePath, serialized, -1)

    if not success then
        log("ERROR saving table: %s (%s)", tableName, err or "unknown error")
        return false, err
    end

    DirtyTables[tableName] = nil
    return true
end

local function tableExists(tableName)
    local valid, err = validateTableName(tableName)
    if not valid then
        return false, err
    end

    local filePath = buildFilePath(tableName)
    return LoadResourceFile(RESOURCE_NAME, filePath) ~= nil
end

local function createTable(tableName, initialData)
    local valid, err = validateTableName(tableName)
    if not valid then
        log("CreateTable failed: %s", err)
        return false, err
    end

    if tableExists(tableName) then
        return true, "already exists"
    end

    local content = serializeTable(type(initialData) == "table" and initialData or {})
    local success, saveErr = SaveResourceFile(RESOURCE_NAME, buildFilePath(tableName), content, -1)

    if not success then
        log("ERROR creating table: %s (%s)", tableName, saveErr or "unknown error")
        return false, saveErr
    end

    return true
end

local function loadTable(tableName)
    local valid, err = validateTableName(tableName)
    if not valid then
        log("LoadTable failed: %s", err)
        return nil
    end

    if FakeCache[tableName] then
        return FakeCache[tableName]
    end

    local filePath = buildFilePath(tableName)
    local content = LoadResourceFile(RESOURCE_NAME, filePath)

    if not content then
        log("Could not find table file: %s", tableName)
        return nil
    end

    local chunk, loadErr = load(content, ("@%s/%s"):format(RESOURCE_NAME, filePath), "t", runtimeEnv())
    if not chunk then
        log("Load error for table: %s (%s)", tableName, loadErr)
        return nil
    end

    local ok, result = pcall(chunk)
    if not ok then
        log("Execution error for table: %s (%s)", tableName, result)
        return nil
    end

    if type(result) ~= "table" then
        log("Unexpected result type for table: %s (%s)", tableName, type(result))
        return nil
    end

    FakeCache[tableName] = result
    return result
end

local function ensureTable(tableName, initialData)
    if not tableExists(tableName) then
        local created = createTable(tableName, initialData)
        if not created then
            return nil
        end
    end

    return loadTable(tableName)
end

local function cloneShallow(source)
    local copy = {}
    for key, value in pairs(source) do
        copy[key] = value
    end
    return copy
end

local function buildMatcher(condition)
    if condition == nil then
        return function()
            return true
        end
    end

    if type(condition) == "function" then
        return function(row)
            local ok, result = pcall(condition, row)
            return ok and result == true
        end
    end

    if type(condition) == "table" then
        return function(row)
            if type(row) ~= "table" then
                return false
            end

            for key, expected in pairs(condition) do
                if row[key] ~= expected then
                    return false
                end
            end

            return true
        end
    end

    return function()
        return false
    end
end

local function findRows(tableName, condition, options)
    local data = loadTable(tableName)
    if not data then
        return {}
    end

    local matcher = buildMatcher(condition)
    local results = {}

    for _, row in ipairs(data) do
        if matcher(row) then
            results[#results + 1] = row
        end
    end

    if options and type(options) == "table" then
        if type(options.orderBy) == "string" then
            local key = options.orderBy
            local desc = options.desc == true

            table.sort(results, function(a, b)
                local av, bv = a[key], b[key]
                if av == bv then
                    return false
                end
                if av == nil then
                    return false
                end
                if bv == nil then
                    return true
                end

                local at, bt = type(av), type(bv)
                if at ~= bt then
                    av = tostring(av)
                    bv = tostring(bv)
                end

                if desc then
                    return av > bv
                end
                return av < bv
            end)
        end

        local offset = tonumber(options.offset) or 0
        local limit = tonumber(options.limit) or #results

        if offset > 0 or limit < #results then
            local sliced = {}
            for i = offset + 1, math.min(offset + limit, #results) do
                sliced[#sliced + 1] = results[i]
            end
            results = sliced
        end
    end

    return results
end

local function applyUpdate(row, update)
    if type(update) == "function" then
        local ok = pcall(update, row)
        return ok
    end

    if type(update) == "table" then
        for key, value in pairs(update) do
            row[key] = value
        end
        return true
    end

    return false
end

local function flushDirtyTables()
    for tableName in pairs(DirtyTables) do
        local cached = FakeCache[tableName]
        if cached then
            local ok = saveTableToFile(tableName, cached)
            if ok then
                log("Auto-saved table: %s", tableName)
            end
        else
            DirtyTables[tableName] = nil
        end
    end
end

CreateThread(function()
    while true do
        Wait(AUTOSAVE_SECONDS * 1000)
        flushDirtyTables()
    end
end)

AddEventHandler("onResourceStop", function(resourceName)
    if resourceName ~= RESOURCE_NAME then
        return
    end

    for tableName, data in pairs(FakeCache) do
        local ok = saveTableToFile(tableName, data)
        if ok then
            log("Saved table on shutdown: %s", tableName)
        end
    end
end)

exports("CreateTable", function(tableName, initialData)
    return createTable(tableName, initialData)
end)

exports("TableExists", function(tableName)
    return tableExists(tableName)
end)

exports("EnsureTable", function(tableName, initialData)
    return ensureTable(tableName, initialData)
end)

exports("LoadTable", function(tableName)
    return loadTable(tableName)
end)

exports("SaveTable", function(tableName, data)
    if type(data) ~= "table" then
        log("SaveTable failed for '%s': data must be a table", tostring(tableName))
        return false
    end

    local valid, err = validateTableName(tableName)
    if not valid then
        log("SaveTable failed: %s", err)
        return false
    end

    FakeCache[tableName] = data
    return saveTableToFile(tableName, data)
end)

exports("DeleteTable", function(tableName)
    local valid, err = validateTableName(tableName)
    if not valid then
        log("DeleteTable failed: %s", err)
        return false
    end

    local filePath = buildFilePath(tableName)
    local absPath = GetResourcePath(RESOURCE_NAME) .. "/" .. filePath
    local success, removeErr = os.remove(absPath)

    FakeCache[tableName] = nil
    DirtyTables[tableName] = nil

    if not success then
        log("Failed to delete table: %s (%s)", tableName, removeErr or "unknown error")
        return false, removeErr
    end

    log("Deleted table: %s", tableName)
    return true
end)

exports("InsertRow", function(tableName, row)
    if type(row) ~= "table" then
        log("InsertRow failed: row must be a table")
        return false
    end

    local data = ensureTable(tableName)
    if not data then
        log("InsertRow aborted: could not load table '%s'", tostring(tableName))
        return false
    end

    data[#data + 1] = row
    markDirty(tableName)
    return true, #data
end)

exports("InsertRows", function(tableName, rows)
    if type(rows) ~= "table" then
        log("InsertRows failed: rows must be an array table")
        return 0
    end

    local data = ensureTable(tableName)
    if not data then
        return 0
    end

    local inserted = 0
    for _, row in ipairs(rows) do
        if type(row) == "table" then
            data[#data + 1] = row
            inserted = inserted + 1
        end
    end

    if inserted > 0 then
        markDirty(tableName)
    end

    return inserted
end)

exports("UpdateRows", function(tableName, condition, update)
    local data = loadTable(tableName)
    if not data then
        log("UpdateRows aborted: could not load table '%s'", tostring(tableName))
        return 0
    end

    local matcher = buildMatcher(condition)
    local updated = 0

    for _, row in ipairs(data) do
        if matcher(row) and applyUpdate(row, update) then
            updated = updated + 1
        end
    end

    if updated > 0 then
        markDirty(tableName)
    end

    return updated
end)

exports("DeleteRows", function(tableName, condition)
    local data = loadTable(tableName)
    if not data then
        log("DeleteRows aborted: could not load table '%s'", tostring(tableName))
        return 0
    end

    local matcher = buildMatcher(condition)
    local kept = {}
    local deleted = 0

    for _, row in ipairs(data) do
        if matcher(row) then
            deleted = deleted + 1
        else
            kept[#kept + 1] = row
        end
    end

    if deleted > 0 then
        FakeCache[tableName] = kept
        markDirty(tableName)
    end

    return deleted
end)

exports("FindRows", function(tableName, condition, options)
    return findRows(tableName, condition, options)
end)

exports("FindOne", function(tableName, condition)
    local results = findRows(tableName, condition, { limit = 1 })
    return results[1]
end)

exports("CountRows", function(tableName, condition)
    return #findRows(tableName, condition)
end)

exports("Exists", function(tableName, condition)
    return exports["tss-fakesql"]:FindOne(tableName, condition) ~= nil
end)

exports("UpsertRow", function(tableName, condition, insertData, update)
    local existing = exports["tss-fakesql"]:FindOne(tableName, condition)
    if existing then
        local updated = applyUpdate(existing, update or insertData)
        if updated then
            markDirty(tableName)
            return "updated", existing
        end
        return "none", existing
    end

    if type(insertData) ~= "table" then
        return "none", nil
    end

    local inserted = cloneShallow(insertData)
    local ok = exports["tss-fakesql"]:InsertRow(tableName, inserted)
    if ok then
        return "inserted", inserted
    end

    return "none", nil
end)

exports("IncrementField", function(tableName, condition, fieldName, amount)
    local by = tonumber(amount) or 1
    local changed = exports["tss-fakesql"]:UpdateRows(tableName, condition, function(row)
        local current = tonumber(row[fieldName]) or 0
        row[fieldName] = current + by
    end)
    return changed
end)

exports("TruncateTable", function(tableName)
    local valid, err = validateTableName(tableName)
    if not valid then
        log("TruncateTable failed: %s", err)
        return false
    end

    FakeCache[tableName] = {}
    markDirty(tableName)
    return true
end)

exports("FlushTable", function(tableName)
    local data = loadTable(tableName)
    if not data then
        return false
    end

    return saveTableToFile(tableName, data)
end)

exports("FlushAll", function()
    flushDirtyTables()
end)

-- Backwards-compatible callback style query:
-- Query(tableName, rowName, expectedValue, cb)
exports("Query", function(tableName, rowName, expectedValue, cb)
    if type(rowName) ~= "string" or rowName == "" then
        if type(cb) == "function" then
            cb({})
        end
        return {}
    end

    local results = findRows(tableName, { [rowName] = expectedValue })
    if type(cb) == "function" then
        cb(results)
    end
    return results
end)
