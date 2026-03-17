# tss-fakesql
Lightweight Lua table storage that mirrors common database workflows without MySQL.

## What It Does
- Stores each "table" as a Lua file in `database/*.lua`
- Caches loaded tables in memory for fast reads
- Marks changed tables as dirty and auto-saves every 5 minutes
- Flushes all cached tables on resource stop

## Core Exports
- `CreateTable(tableName, initialData?)`
- `EnsureTable(tableName, initialData?)`
- `TableExists(tableName)`
- `LoadTable(tableName)`
- `SaveTable(tableName, data)`
- `DeleteTable(tableName)`
- `TruncateTable(tableName)`
- `FlushTable(tableName)`
- `FlushAll()`

## Row Operations
- `InsertRow(tableName, row)`
- `InsertRows(tableName, rows)`
- `FindRows(tableName, condition?, options?)`
- `FindOne(tableName, condition?)`
- `CountRows(tableName, condition?)`
- `Exists(tableName, condition?)`
- `UpdateRows(tableName, condition, update)`
- `DeleteRows(tableName, condition)`
- `UpsertRow(tableName, condition, insertData, update?)`
- `IncrementField(tableName, condition, fieldName, amount?)`

## Condition Format
Most condition args support:
- function matcher:
```lua
function(row) return row.owner == "CID1001" end
```
- table matcher (exact key/value match):
```lua
{ owner = "CID1001", model = "sultan" }
```

## Query Options
`FindRows(..., options)` supports:
- `orderBy = "fieldName"`
- `desc = true|false`
- `limit = number`
- `offset = number`

## Examples
```lua
local db = exports["tss-fakesql"]

db:EnsureTable("vehicles")
db:InsertRow("vehicles", {
    plate = "ABC123",
    owner = "CID1001",
    model = "sultan",
    coords = vector3(0.0, 0.0, 0.0)
})

local myVehicles = db:FindRows("vehicles", { owner = "CID1001" }, { orderBy = "plate" })
local found = db:FindOne("vehicles", { plate = "ABC123" })
local count = db:CountRows("vehicles", function(row) return row.model == "sultan" end)

db:UpdateRows("vehicles", { plate = "ABC123" }, { owner = "CID2002" })
db:IncrementField("vehicles", { plate = "ABC123" }, "mileage", 15)
db:DeleteRows("vehicles", function(row) return row.plate == "ABC123" end)

-- Callback-friendly legacy helper (still supported)
db:Query("vehicles", "owner", "CID2002", function(results)
    print("rows:", #results)
end)
```
