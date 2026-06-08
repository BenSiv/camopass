-- Dynamically locate the script's directory to allow execution from any path
local_path = "."
if arg != nil and arg[0] != nil then
    dir_match = string.match(arg[0], "^(.-)[/\\][^/\\]-$")
    if dir_match != nil and dir_match != "" then
        local_path = dir_match
    end
end
package.path = package.path .. ";" .. local_path .. "/../src/?.lua"
require("obfuscator")

print("Initializing CamoPass tests...")

source_dir = "/tmp/camopass_test_source"
target_dir = "/tmp/camopass_test_target"

os.execute("rm -rf " .. source_dir .. " " .. target_dir)
os.execute("mkdir -p " .. source_dir)

-- Dynamically fetch a valid secret GPG key ID from the local keyring
gpg_id = nil
p = io.popen("gpg --list-secret-keys --keyid-format LONG 2>/dev/null")
if p != nil then
    io.input(p)
    line = io.read("*l")
    while line != nil do
        match = string.match(line, "sec%s+%S+/(%w+)")
        if match != nil then
            gpg_id = match
            break
        end
        line = io.read("*l")
    end
    io.close(p)
end

if gpg_id == nil then
    print("Error: No secret GPG keys found in local keyring. GPG tests require a local secret key.")
    os.exit(false)
end

print("Using discovered GPG key for tests: " .. gpg_id)

-- Write GPG ID
f = io.open(source_dir .. "/.gpg-id", "w")
io.output(f)
io.write(gpg_id .. "\n")
io.close(f)

-- Seed GPG credentials
print("Creating dummy GPG files...")
os.execute("echo 'my_secret_pass_1' | gpg --batch --yes --encrypt --recipient " .. gpg_id .. " --output " .. source_dir .. "/test1.gpg")
os.execute("mkdir -p " .. source_dir .. "/social")
os.execute("echo 'my_secret_pass_2' | gpg --batch --yes --encrypt --recipient " .. gpg_id .. " --output " .. source_dir .. "/social/mastodon.gpg")

-- Run core obfuscator
print("Running obfuscator engine...")
success, msg = obfuscate_store(source_dir, target_dir, gpg_id)

if not success then
    print("Test Failed: " .. (msg or "unknown error"))
    os.exit(false)
end
print(msg)

-- Verify structural lookup
print("Verifying mappings...")
mappings = load_index(target_dir)
if mappings == nil then
    print("Test Failed: Index failed to load or decrypt.")
    os.exit(false)
end

salt = mappings["__salt__"]
assert(salt != nil and string.len(salt) == 16, "Test Failed: Salt is not valid 16-character hex string: " .. tostring(salt))

obf1 = mappings["social/mastodon"]
obf2 = mappings["test1"]

assert(obf1 != nil and string.len(obf1) == 10, "Test Failed: Obfuscated name for social/mastodon is not 10 chars: " .. tostring(obf1))
assert(obf2 != nil and string.len(obf2) == 10, "Test Failed: Obfuscated name for test1 is not 10 chars: " .. tostring(obf2))

-- Verify Git-stability (Adding a new file preserves old names and uses the same salt)
print("Verifying Git stability (preserving salt & names)...")
os.execute("echo 'new_secret' | gpg --batch --yes --encrypt --recipient " .. gpg_id .. " --output " .. source_dir .. "/a_new_first_credential.gpg")

success, msg = obfuscate_store(source_dir, target_dir, gpg_id)
if not success then
    print("Test Failed during stability check: " .. (msg or "unknown error"))
    os.exit(false)
end

new_mappings = load_index(target_dir)
if new_mappings == nil then
    print("Test Failed: Index failed to reload.")
    os.exit(false)
end

assert(new_mappings["__salt__"] == salt, "Test Failed: Salt changed during second hide!")
assert(new_mappings["social/mastodon"] == obf1, "Test Failed: Name for social/mastodon changed after adding new entry!")
assert(new_mappings["test1"] == obf2, "Test Failed: Name for test1 changed after adding new entry!")

obf3 = new_mappings["a_new_first_credential"]
assert(obf3 != nil and string.len(obf3) == 10, "Test Failed: New credential not mapped correctly: " .. tostring(obf3))

print("Cleaning test environment...")
os.execute("rm -rf " .. source_dir .. " " .. target_dir)

print("""
===========================================
    ALL CAMOPASS TESTS PASSED!
===========================================
""")

