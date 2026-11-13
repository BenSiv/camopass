-- Dynamically locate the script's directory to allow execution from any path
local_path = "."
script_path = "tst/test_obfuscator.lua"
if arg != nil and arg[0] != nil then
    script_path = arg[0]
    dir_match = string.match(arg[0], "^(.-)[/\\][^/\\]-$")
    if dir_match != nil and dir_match != "" then
        local_path = dir_match
    end
end

-- Self-isolate HOME and GNUPGHOME so tests never touch live user config or keyrings
if os.getenv("CAMOPASS_TEST_ISOLATED") != "1" then
    test_root = "/tmp/camopass_unit_env"
    os.execute("rm -rf " .. test_root .. " && mkdir -p " .. test_root .. "/home " .. test_root .. "/gnupg && chmod 700 " .. test_root .. "/gnupg")
    key_cmd = "GNUPGHOME=" .. test_root .. "/gnupg gpg --batch --quiet --pinentry-mode loopback --passphrase '' --quick-generate-key 'CamoPass Test <test@camopass.local>' ed25519 default never"
    rc = os.execute(key_cmd)
    if rc != 0 and rc != true then
        os.execute("rm -rf " .. test_root)
        print("Error: Failed to generate isolated test GPG key.")
        os.exit(false)
    end
    enc_fpr_p = io.popen("GNUPGHOME=" .. test_root .. "/gnupg gpg --list-keys --with-colons 2>/dev/null")
    io.input(enc_fpr_p)
    fpr_out = io.read("*a")
    io.close(enc_fpr_p)
    io.input(io.stdin)
    primary_fpr = string.match(fpr_out, "fpr:::::::::(%x+):")
    if primary_fpr == nil then
        os.execute("rm -rf " .. test_root)
        print("Error: Could not extract test GPG fingerprint.")
        os.exit(false)
    end
    sub_rc = os.execute("GNUPGHOME=" .. test_root .. "/gnupg gpg --batch --quiet --pinentry-mode loopback --passphrase '' --quick-add-key " .. primary_fpr .. " cv25519 encr never")
    if sub_rc != 0 and sub_rc != true then
        os.execute("rm -rf " .. test_root)
        print("Error: Failed to add encryption subkey to isolated test GPG key.")
        os.exit(false)
    end

    run_rc = os.execute("HOME=" .. test_root .. "/home GNUPGHOME=" .. test_root .. "/gnupg CAMOPASS_TEST_ISOLATED=1 CAMOPASS_TEST_GPG_ID=" .. primary_fpr .. " luam " .. string.format("%q", script_path))
    os.execute("GNUPGHOME=" .. test_root .. "/gnupg gpgconf --kill gpg-agent >/dev/null 2>&1 || true")
    os.execute("rm -rf " .. test_root)
    if run_rc != 0 and run_rc != true then
        os.exit(false)
    end
    os.exit(true)
end

package.path = package.path .. ";" .. local_path .. "/../src/?.lua"
obfuscator = require("obfuscator")

print("Initializing CamoPass core tests (isolated GNUPGHOME)...")

source_dir = "/tmp/camopass_test_source"
target_dir = "/tmp/camopass_test_target"
stateless_dir = "/tmp/camopass_test_stateless"
unhide_dir = "/tmp/camopass_test_unhide"

os.execute("rm -rf " .. source_dir .. " " .. target_dir .. " " .. stateless_dir .. " " .. unhide_dir)
os.execute("mkdir -p " .. source_dir .. " " .. stateless_dir)

gpg_id = os.getenv("CAMOPASS_TEST_GPG_ID")
assert(gpg_id != nil and gpg_id != "", "Missing isolated GPG fingerprint")
print("Using isolated test GPG key: " .. gpg_id)

-- Write GPG ID
f = io.open(source_dir .. "/.gpg-id", "w")
io.output(f)
io.write(gpg_id .. "\n")
io.close(f)
io.output(io.stdout)

-- Seed GPG credentials for migration tests
print("Creating dummy GPG files...")
os.execute("printf 'my_secret_pass_1\n' | gpg --batch --yes --always-trust --encrypt --recipient " .. gpg_id .. " --output " .. source_dir .. "/test1.gpg")
os.execute("mkdir -p " .. source_dir .. "/social")
os.execute("printf 'my_secret_pass_2\n' | gpg --batch --yes --always-trust --encrypt --recipient " .. gpg_id .. " --output " .. source_dir .. "/social/mastodon.gpg")

-- 1. Run core migration obfuscator
print("Running obfuscator engine...")
success, msg = obfuscator.obfuscate_store(source_dir, target_dir, gpg_id)
assert(success, "Test Failed: " .. tostring(msg))
print(msg)

-- 2. Verify structural lookup
print("Verifying mappings...")
mappings = obfuscator.load_index(target_dir)
assert(mappings != nil, "Test Failed: Index failed to load or decrypt.")

salt = mappings["__salt__"]
assert(salt != nil and string.len(salt) == 16, "Test Failed: Salt is not valid 16-character hex string: " .. tostring(salt))

obf1 = mappings["social/mastodon"]
obf2 = mappings["test1"]
assert(obf1 != nil and string.len(obf1) == 10, "Test Failed: Obfuscated name for social/mastodon is not 10 chars: " .. tostring(obf1))
assert(obf2 != nil and string.len(obf2) == 10, "Test Failed: Obfuscated name for test1 is not 10 chars: " .. tostring(obf2))

-- 3. Verify Git-stability (Adding a new file preserves old names and uses the same salt)
print("Verifying Git stability (preserving salt & names)...")
os.execute("printf 'new_secret\n' | gpg --batch --yes --always-trust --encrypt --recipient " .. gpg_id .. " --output " .. source_dir .. "/a_new_first_credential.gpg")

success, msg = obfuscator.obfuscate_store(source_dir, target_dir, gpg_id)
assert(success, "Test Failed during stability check: " .. tostring(msg))

new_mappings = obfuscator.load_index(target_dir)
assert(new_mappings != nil, "Test Failed: Index failed to reload.")
assert(new_mappings["__salt__"] == salt, "Test Failed: Salt changed during second hide!")
assert(new_mappings["social/mastodon"] == obf1, "Test Failed: Name for social/mastodon changed after adding new entry!")
assert(new_mappings["test1"] == obf2, "Test Failed: Name for test1 changed after adding new entry!")
obf3 = new_mappings["a_new_first_credential"]
assert(obf3 != nil and string.len(obf3) == 10, "Test Failed: New credential not mapped correctly: " .. tostring(obf3))

-- 4. Verify unhide functionality
print("Verifying unhide functionality...")
success, msg = obfuscator.unhide_store(target_dir, unhide_dir)
assert(success, "Test Failed during unhide: " .. tostring(msg))
assert(obfuscator.file_exists(unhide_dir .. "/test1.gpg"), "Test Failed: test1.gpg not restored")
assert(obfuscator.file_exists(unhide_dir .. "/social/mastodon.gpg"), "Test Failed: social/mastodon.gpg not restored")
assert(obfuscator.file_exists(unhide_dir .. "/a_new_first_credential.gpg"), "Test Failed: new credential not restored")
assert(obfuscator.file_exists(unhide_dir .. "/.gpg-id"), "Test Failed: .gpg-id not restored")

-- 5. Verify stateless mutations without ANY plain_store on disk
print("Verifying stateless upsert, edit, password generation, and remove...")
f = io.open(stateless_dir .. "/.gpg-id", "w")
io.output(f)
io.write(gpg_id .. "\n")
io.close(f)
io.output(io.stdout)

ok, obf_bank = obfuscator.upsert_entry(stateless_dir, "finance/bank", "super_secret_bank_pw\nuser: alice")
assert(ok, "Stateless upsert failed: " .. tostring(obf_bank))
assert(string.len(obf_bank) == 10, "Expected 10-char obf name")
assert(not obfuscator.file_exists(stateless_dir .. "/finance/bank.gpg"), "Plaintext path must NEVER exist in obfuscated store")
assert(obfuscator.file_exists(stateless_dir .. "/" .. obf_bank .. ".gpg"), "Obfuscated entry file missing")
assert(obfuscator.file_exists(stateless_dir .. "/index.gpg"), "index.gpg missing")

dec_bank = obfuscator.decrypt_file(stateless_dir .. "/" .. obf_bank .. ".gpg")
assert(dec_bank == "super_secret_bank_pw\nuser: alice\n", "Unexpected decrypted content: " .. tostring(dec_bank))

-- Update existing entry preserves exact same obfuscated filename & salt
st_map_before = obfuscator.load_index(stateless_dir)
ok2, obf_bank2 = obfuscator.upsert_entry(stateless_dir, "finance/bank", "rotated_bank_pw")
assert(ok2 and obf_bank2 == obf_bank, "Updating entry must preserve obfuscated filename")
st_map_after = obfuscator.load_index(stateless_dir)
assert(st_map_after["__salt__"] == st_map_before["__salt__"], "Salt must remain stable across stateless updates")
assert(obfuscator.decrypt_file(stateless_dir .. "/" .. obf_bank .. ".gpg") == "rotated_bank_pw\n", "Updated content mismatch")

-- Password generator test (with & without symbols)
pw_sym, pw_err = obfuscator.generate_password(32, false)
assert(pw_sym != nil and string.len(pw_sym) == 32, "Password generation (32) failed: " .. tostring(pw_err))
pw_nosym, pw_err2 = obfuscator.generate_password(24, true)
assert(pw_nosym != nil and string.len(pw_nosym) == 24, "Alnum password generation failed: " .. tostring(pw_err2))
assert(string.match(pw_nosym, "^%w+$") != nil, "No-symbols password contained non-alphanumeric chars: " .. pw_nosym)

-- Remove entry shreds the .gpg file and updates index.gpg
ok_rm, rm_msg = obfuscator.remove_entry(stateless_dir, "finance/bank")
assert(ok_rm, "Stateless remove failed: " .. tostring(rm_msg))
assert(not obfuscator.file_exists(stateless_dir .. "/" .. obf_bank .. ".gpg"), "Removed .gpg file still exists on disk!")
st_map_removed = obfuscator.load_index(stateless_dir)
assert(st_map_removed["finance/bank"] == nil, "Removed entry still present in index.gpg!")

-- Verify zero leftover /dev/shm buffers
shm_p = io.popen("ls /dev/shm/camopass_* 2>/dev/null | wc -l")
io.input(shm_p)
shm_count = tonumber(obfuscator.trim(io.read("*a")))
io.close(shm_p)
io.input(io.stdin)
assert(shm_count == 0, "Leftover RAM buffers detected in /dev/shm!")

print("Cleaning test directories...")
os.execute("rm -rf " .. source_dir .. " " .. target_dir .. " " .. stateless_dir .. " " .. unhide_dir)

print("""
===========================================
    ALL CAMOPASS CORE TESTS PASSED!
===========================================
""")
