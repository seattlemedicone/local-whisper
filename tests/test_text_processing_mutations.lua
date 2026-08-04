local api = assert(WhisperTextProcessing, "WhisperTextProcessing is not loaded")
local source = debug.getinfo(1, "S").source
local scriptPath
if type(_cli) == "table" and type(_cli.args) == "table" and _cli.args[1] then
    -- The Hammerspoon CLI sends a file's contents over IPC, so debug.getinfo
    -- reports a source string rather than its path. The CLI retains the path.
    scriptPath = _cli.args[1]
else
    scriptPath = source:sub(1, 1) == "@" and source:sub(2) or source
end
local scriptDir = scriptPath:match("^(.*)/[^/]+$") or "."
local testFile = scriptDir .. "/test_text_processing.lua"
local testHandle = assert(io.open(testFile, "r"), "test file not found: " .. testFile)
testHandle:close()

local original = {
    process = assert(api.process),
    validateRefinement = assert(api.validateRefinement),
    finalizeRefinement = assert(api.finalizeRefinement),
}

local mutations = {
    {
        name = "comma separators replace canonical pipes",
        install = function()
            api.process = function(text, appBundleID)
                return original.process(text, appBundleID):gsub(" | ", ", ")
            end
        end,
    },
    {
        name = "EtCO2 unit loses required spacing",
        install = function()
            api.process = function(text, appBundleID)
                return original.process(text, appBundleID):gsub("mm Hg", "mmHg")
            end
        end,
    },
    {
        name = "leading paragraph is stripped",
        install = function()
            api.process = function(text, appBundleID)
                return original.process(text, appBundleID):gsub("^%s+", "")
            end
        end,
    },
    {
        name = "validator accepts every model response",
        install = function()
            api.validateRefinement = function() return true, "accepted" end
        end,
    },
    {
        name = "validator rejects every model response",
        install = function()
            api.validateRefinement = function() return false, "mutant" end
        end,
    },
    {
        name = "finalizer trusts an unsafe candidate",
        install = function()
            api.finalizeRefinement = function(_, candidate)
                return candidate, true, "accepted"
            end
        end,
    },
}

local function restore()
    api.process = original.process
    api.validateRefinement = original.validateRefinement
    api.finalizeRefinement = original.finalizeRefinement
end

for _, mutation in ipairs(mutations) do
    restore()
    mutation.install()
    local passed = pcall(dofile, testFile)
    assert(not passed, "tests failed to reject mutant: " .. mutation.name)
end

restore()
print(string.format("PASS: rejected %d targeted mutants", #mutations))
