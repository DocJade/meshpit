local function local_function()
    local sum = 0
    for i = 1, 100000 do
        sum = sum + i
    end
end

local function table_function()
    local table = {
        sum = 0
    }
    for i = 1, 100000 do
        table.sum = table.sum + i
    end
end

-- Benchmarking setup
local num_iterations = 100000 -- Number of times to run the function
local start_time = os.clock() -- Get the initial CPU time

for i = 1, num_iterations do
    table_function()
end

local end_time = os.clock() -- Get the final CPU time
local elapsed_time = end_time - start_time
local average_time = elapsed_time / num_iterations

print(string.format("Total elapsed time for %d iterations: %.4f seconds", num_iterations, elapsed_time))
print(string.format("Average execution time per call: %.8f seconds", average_time))
