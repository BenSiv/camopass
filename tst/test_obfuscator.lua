package.path = package.path .. ";./src/?.lua"
require("obfuscator")

print("Initializing CamoPass tests...")

source_dir = "/tmp/camopass_test_source"
target_dir = "/tmp/camopass_test_target"

os.execute("rm -rf " .. source_dir .. " " .. target_dir)
os.execute("mkdir -p " .. source_dir)

-- Write GPG ID
f = io.open(source_dir .. "/.gpg-id", "w")
io.output(f)
io.write("A748A133F7C13732\n")
io.close(f)

-- Seed GPG credentials
print("Creating dummy GPG files...")
os.execute("echo 'my_secret_pass_1' | gpg --batch --yes --encrypt --recipient A748A133F7C13732 --output " .. source_dir .. "/test1.gpg")
os.execute("mkdir -p " .. source_dir .. "/social")
os.execute("echo 'my_secret_pass_2' | gpg --batch --yes --encrypt --recipient A748A133F7C13732 --output " .. source_dir .. "/social/mastodon.gpg")

-- Run core obfuscator
print("Running obfuscator engine...")
success, msg = obfuscate_store(source_dir, target_dir, "A748A133F7C13732")

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
