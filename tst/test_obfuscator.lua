package.path = package.path .. ";./src/?.lua"
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

assert(mappings["social/mastodon"] == "e1", "Test Failed: mapping for social/mastodon was " .. tostring(mappings["social/mastodon"]))
assert(mappings["test1"] == "e2", "Test Failed: mapping for test1 was " .. tostring(mappings["test1"]))

print("Cleaning test environment...")
os.execute("rm -rf " .. source_dir .. " " .. target_dir)

print("""
===========================================
    ALL CAMOPASS TESTS PASSED!
===========================================
""")
