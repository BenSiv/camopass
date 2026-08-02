-- Dynamically locate the script's directory to allow execution from any path
local_path = "."
if arg != nil and arg[0] != nil then
    dir_match = string.match(arg[0], "^(.-)[/\\][^/\\]-$")
    if dir_match != nil and dir_match != "" then
        local_path = dir_match
    end
end

print("Initializing CamoPass CLI tests...")

entry_script = local_path .. "/../entry.lua"

function run_cli(cli_args)
    cmd = "luam " .. entry_script .. " " .. cli_args .. " 2>&1"
    p = io.popen(cmd)
    if p == nil then
        return false, "Failed to run command"
    end
    io.input(p)
    out = io.read("*a")
    io.close(p)
    return true, out
end

-- Test 1: Empty args should print usage
print("Testing CLI usage output...")
success, out = run_cli("")
assert(success, "Failed to execute CLI")
assert(string.find(out, "Usage:", 1, true) != nil, "Test Failed: Usage not printed when no arguments provided")
assert(string.find(out, "CamoPass - Secure Metadata Obfuscator", 1, true) != nil, "Test Failed: Header missing")

-- Test 2: Invalid command
print("Testing invalid command...")
success, out = run_cli("invalid_command")
assert(string.find(out, "Usage:", 1, true) != nil, "Test Failed: Usage not printed for invalid command")

-- Test 3: init command argument validation
print("Testing init argument validation...")
success, out = run_cli("init")
assert(string.find(out, "Error: init requires", 1, true) != nil, "Test Failed: init did not validate arguments")

-- Test 4: init command execution
print("Testing init command execution...")
test_store = "/tmp/camopass_test_store"
test_plain = "/tmp/camopass_test_plain"
os.execute("rm -rf " .. test_store .. " " .. test_plain)
success, out = run_cli("init " .. test_store .. " " .. test_plain)
assert(string.find(out, "Successfully initialized", 1, true) != nil, "Test Failed: init command failed")
-- Verify it created the settings.json
settings_f = io.open(os.getenv("HOME") .. "/.config/camopass/settings.json", "r")
assert(settings_f != nil, "Test Failed: settings.json not created")
io.input(settings_f)
settings_content = io.read("*a")
io.close(settings_f)
assert(string.find(settings_content, test_store, 1, true) != nil, "Test Failed: target store not in settings.json")

-- Test 5: unhide command execution
print("Testing unhide command execution...")
test_unhide = "/tmp/camopass_test_unhide"
os.execute("rm -rf " .. test_unhide)
success, out = run_cli("unhide " .. test_store .. " " .. test_unhide)
assert(string.find(out, "Unhide failed", 1, true) != nil, "Test Failed: unhide should fail on non-existent index")

-- Clean up
os.execute("rm -rf " .. test_store .. " " .. test_plain .. " " .. test_unhide)

print("""
===========================================
    ALL CAMOPASS CLI TESTS PASSED!
===========================================
""")
