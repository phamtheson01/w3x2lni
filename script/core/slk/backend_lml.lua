local lang = require 'lang'

local w2l
local wtg
local wct
local wts

local type = type
local tonumber = tonumber
local pairs = pairs
local ipairs = ipairs
local find = string.find
local gsub = string.gsub
local format = string.format
local rep = string.rep
local buf
local lml_table

local sp_rep = setmetatable({}, {
    __index = function (self, k)
        self[k] = rep(' ', k)
        return self[k]
    end,
})

local function lml_string(str)
    if type(str) == 'string' then
        -- Check string from WTS firstly.
        if find(str, '^TRIGSTR_%d+$') then
            str = w2l:load_wts(wts, str)
        end
        -- Then check if the string should be in quotes.
        if find(str, "[%s%:%'%c]") then
            str = format("'%s'", gsub(str, "'", "''"))
        end
    end
    return str
end

local function lml_key(str)
    if type(str) == 'string' then
        if find(str, "[%s%:%'%c]") then
            str = format("'%s'", gsub(str, "'", "''"))
        end
    end
    return str
end

local function lml_value(v, sp)
    if v[2] then
        buf[#buf+1] = format('%s%s: %s\n', sp_rep[sp], v[1], lml_string(v[2]))
    else
        buf[#buf+1] = format('%s%s\n', sp_rep[sp], lml_string(v[1]))
    end
    for i = 3, #v do
        lml_value(v[i], sp+4)
    end
end

local function lml_value_by_dir(v, sp)
    if v[2] then
        buf[#buf+1] = format('%s%s: %s\n', sp_rep[sp], lml_key(v[1]), lml_string(v[2]))
    else
        buf[#buf+1] = format('%s%s\n', sp_rep[sp], lml_string(v[1]))
    end
    for i = 3, #v do
        lml_value(v[i], sp+4)
    end
end

local function convert_lml(tbl)
    buf = {}
    for i = 3, #tbl do
        lml_value(tbl[i], 0)
    end
    return table.concat(buf)
end

local function convert_lml_by_dir(tbl)
    buf = {}
    for i = 3, #tbl do
        lml_value_by_dir(tbl[i], 0)
    end
    return table.concat(buf)
end

local function get_path(path, used)
    path = path:gsub('[$\\$/$:$*$?$"$<$>$|]', '_')
    while used[path:lower()] do
        local name, id = path:match '(.+)_(%d+)$'
        if name and id then
            id = id + 1
        else
            name = path
            id = 1
        end
        path = name .. '_' .. id
    end
    used[path:lower()] = true
    return path
end

local function compute_path()
    if not wtg then
        return
    end
    local dirs = {}
    local used = {}
    local map = {}
    for _, dir in ipairs(wtg.categories) do
        dirs[dir.id] = {}
        map[dir.id] = {}
        local path = get_path(dir.name, used)
        map[dir.id][1] = path
    end
    for _, trg in ipairs(wtg.triggers) do
        table.insert(dirs[trg.category], trg)
    end
    for _, dir in ipairs(wtg.categories) do
        for _, trg in ipairs(dirs[dir.id]) do
            map[dir.id][trg.name] = get_path(trg.name, dirs[dir.id])
        end
    end
    return map
end

local function read_dirs(map)
    local dirs = {}
    for _, dir in ipairs(wtg.categories) do
        dirs[dir.id] = {}
    end
    for _, trg in ipairs(wtg.triggers) do
        table.insert(dirs[trg.category], trg)
    end
    local lml = { '', false }
    for i, dir in ipairs(wtg.categories) do
        local filename = map[dir.id][1]
        local dir_data
        if dir.name ~= filename then
            dir_data = { dir.name, filename }
        else
            dir_data = { dir.name, false }
        end
        if dir.comment == 1 then
            dir_data[#dir_data+1] = { lang.lml.COMMENT, 1 }
        end
        for i, trg in ipairs(dirs[dir.id]) do
            local filename = map[dir.id][trg.name]
            local trg_data = { trg.name, false }
            if trg.name ~= filename then
                trg_data[#trg_data+1] = { lang.lml.NAME, filename }
            end
            if trg.type == 1 then
                trg_data[#trg_data+1] = { lang.lml.COMMENT }
            end
            if trg.enable == 0 then
                trg_data[#trg_data+1] = { lang.lml.DISABLE }
            end
            if trg.close == 1 then
                trg_data[#trg_data+1] = { lang.lml.CLOSE }
            end
            if trg.run == 1 then
                trg_data[#trg_data+1] = { lang.lml.RUN }
            end
            dir_data[#dir_data+1] = trg_data
        end
        lml[i+2] = dir_data
    end
    return convert_lml_by_dir(lml)
end

local function read_triggers(files, map)
    if not wtg then
        return
    end
    local triggers = {}
    for i, trg in ipairs(wtg.triggers) do
        local dir = map[trg.category]
        local path = dir[1] .. '\\' .. dir[trg.name]
        if trg.wct == 0 and trg.type == 0 then
            files[path..'.lml'] = convert_lml(trg.trg)
        end
        if #trg.des > 0 then
            files[path..'.txt'] = trg.des
        end
        if trg.wct == 1 then
            local buf = wct.triggers[i]
            if #buf > 0 then
                files[path..'.j'] = buf
            end
        end
    end
end

return function (w2l_, wtg_, wct_, wts_)
    w2l = w2l_
    wtg = wtg_
    wct = wct_
    wts = wts_

    local files = {}

    if #wct.custom.comment > 0 then
        files['code.txt'] = wct.custom.comment
    end
    if #wct.custom.code > 0 then
        files['code.j'] = wct.custom.code
    end

    local vars = convert_lml(wtg.vars)
    if #vars > 0 then
        files['variable.lml'] = vars
    end

    local map = compute_path()
    
    local listfile = read_dirs(map)
    if #listfile > 0 then
        files['catalog.lml'] = listfile
    end

    read_triggers(files, map)

    return files
end
