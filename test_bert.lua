local lines = {}
for line in io.lines("data/SST-2/dev.txt") do
    table.insert(lines, line)
end

request = function()
    --- Random select line
    local currentLine = lines[math.random(#lines)]

    local body = currentLine

    local method = "PUT"

    return wrk.format(method, nil, nil, body)
end
