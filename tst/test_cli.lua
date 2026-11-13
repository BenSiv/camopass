-- Dynamically locate the script's directory to allow execution from any path
local_path = "."
script_path = "tst/test_cli.lua"
if arg != nil and arg[0] != nil then
    script_path = arg[0]
    dir_match = string.match(arg[0], "^(.-)[/\\][^/\\]-$")
    if dir_match != nil and dir_match != "" then
        local_path = dir_match
    end
end

-- Self-isolate HOME and GNUPGHOME so CLI tests NEVER touch ~/.config/camopass or live GPG keys
if os.getenv("CAMOPASS_CLI_TEST_ISOLATED") != "1" then
    test_root = "/tmp/camopass_cli_env"
    os.execute("rm -rf " .. test_root .. " && mkdir -p " .. test_root .. "/home " .. test_root .. "/gnupg && chmod 700 " .. test_root .. "/gnupg")
    key_cmd = "GNUPGHOME=" .. test_root .. "/gnupg gpg --batch --quiet --pinentry-mode loopback --passphrase '' --quick-generate-key 'CamoPass CLI Test <cli@camopass.local>' ed25519 default never"
    rc = os.execute(key_cmd)
    if rc != 0 and rc != true then
        os.execute("rm -rf " .. test_root)
        print("Error: Failed to generate isolated CLI test GPG key.")
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
        print("Error: Could not extract CLI test GPG fingerprint.")
        os.exit(false)
    end
    sub_rc = os.execute("GNUPGHOME=" .. test_root .. "/gnupg gpg --batch --quiet --pinentry-mode loopback --passphrase '' --quick-add-key " .. primary_fpr .. " cv25519 encr never")
    if sub_rc != 0 and sub_rc != true then
        os.execute("rm -rf " .. test_root)
        print("Error: Failed to add encryption subkey for CLI tests.")
        os.exit(false)
    end

    run_rc = os.execute("HOME=" .. test_root .. "/home GNUPGHOME=" .. test_root .. "/gnupg CAMOPASS_CLI_TEST_ISOLATED=1 CAMOPASS_TEST_GPG_ID=" .. primary_fpr .. " luam " .. string.format("%q", script_path))
    os.execute("GNUPGHOME=" .. test_root .. "/gnupg gpgconf --kill gpg-agent >/dev/null 2>&1 || true")
    os.execute("rm -rf " .. test_root)
    if run_rc != 0 and run_rc != true then
        os.exit(false)
    end
    os.exit(true)
end

print("Initializing CamoPass CLI tests (isolated HOME & GNUPGHOME)...")

entry_script = local_path .. "/../src/main.lua"
gpg_id = os.getenv("CAMOPASS_TEST_GPG_ID")
assert(gpg_id != nil and gpg_id != "", "Missing isolated GPG fingerprint")

function shell_quote(s)
    return "'" .. string.gsub(tostring(s), "'", "'\\''") .. "'"
end

function run_cli(cli_args)
    cmd = "luam " .. shell_quote(entry_script) .. " " .. cli_args .. " 2>&1"
    p = io.popen(cmd)
    if p == nil then
        return false, "Failed to run command"
    end
    io.input(p)
    out = io.read("*a")
    io.close(p)
    io.input(io.stdin)
    return true, out
end

function run_cli_stdin(stdin_payload, cli_args)
    cmd = "printf %s " .. shell_quote(stdin_payload) .. " | luam " .. shell_quote(entry_script) .. " " .. cli_args .. " 2>&1"
    p = io.popen(cmd)
    if p == nil then
        return false, "Failed to run piped command"
    end
    io.input(p)
    out = io.read("*a")
    io.close(p)
    io.input(io.stdin)
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

-- Test 4: init fresh obfuscated store with GPG ID (zero plain_store!)
print("Testing stateless init + list + insert + show + generate + edit + remove...")
test_store = "/tmp/camopass_cli_store"
editor_script = "/tmp/camopass_cli_editor.sh"
os.execute("rm -rf " .. test_store .. " " .. editor_script)

success, out = run_cli("init " .. test_store .. " " .. gpg_id)
assert(string.find(out, "Successfully initialized store:", 1, true) != nil, "Test Failed: init command failed: " .. out)

-- Verify settings.json created inside isolated HOME and does NOT contain plain_store
settings_f = io.open(os.getenv("HOME") .. "/.config/camopass/settings.json", "r")
assert(settings_f != nil, "Test Failed: settings.json not created in isolated HOME")
io.input(settings_f)
settings_content = io.read("*a")
io.close(settings_f)
io.input(io.stdin)
assert(string.find(settings_content, test_store, 1, true) != nil, "Test Failed: target store not in settings.json")
assert(string.find(settings_content, "plain_store", 1, true) == nil, "Test Failed: plain_store should no longer be written")

-- Empty store list works immediately
success, out = run_cli("list")
assert(out == "", "Expected empty output on empty initialized store, got: " .. out)

-- Insert multiline entry via stdin directly into obfuscated store
success, out = run_cli_stdin("s3cr3t_gh_token\nusername: bensiv\n", "insert -m github/personal")
assert(string.find(out, "Saved 'github/personal'", 1, true) != nil, "Insert failed: " .. out)

-- Show returns exact decrypted multiline content
success, out = run_cli("show github/personal")
assert(out == "s3cr3t_gh_token\nusername: bensiv\n", "Show output mismatch: " .. out)

-- Generate alphanumeric password directly into obfuscated store
success, out = run_cli("generate -n email/proton 28")
assert(string.find(out, "The generated password for email/proton is:", 1, true) != nil, "Generate failed: " .. out)

success, gen_shown = run_cli("show email/proton")
gen_trimmed = string.match(gen_shown, "^%s*(.-)%s*$")
assert(gen_trimmed != nil and string.len(gen_trimmed) == 28, "Generated password length mismatch: " .. tostring(gen_shown))
assert(string.match(gen_trimmed, "^%w+$") != nil, "Expected alphanumeric password, got: " .. gen_trimmed)

-- Edit entry using custom EDITOR script on /dev/shm buffer
ef = io.open(editor_script, "w")
io.output(ef)
io.write("#!/bin/sh\nprintf 'edited_token_v2\\nusername: bensiv\\n' > \"$1\"\n")
io.close(ef)
io.output(io.stdout)
os.execute("chmod +x " .. editor_script)

edit_p = io.popen("EDITOR=" .. editor_script .. " luam " .. string.format("%q", entry_script) .. " edit github/personal 2>&1")
io.input(edit_p)
edit_out = io.read("*a")
io.close(edit_p)
io.input(io.stdin)
assert(string.find(edit_out, "Updated 'github/personal'.", 1, true) != nil, "Edit failed: " .. edit_out)

success, after_edit = run_cli("show github/personal")
assert(after_edit == "edited_token_v2\nusername: bensiv\n", "Content after edit mismatch: " .. after_edit)

-- List shows both entries in sorted order
success, list_out = run_cli("list")
assert(list_out == "email/proton\ngithub/personal\n", "List output mismatch: " .. list_out)

-- Verify store filesystem contains ONLY .gpg-id, index.gpg, and 10-hex-char .gpg files (zero plaintext directory/file leakage!)
find_p = io.popen("find " .. test_store .. " -mindepth 1 | sort")
io.input(find_p)
line = io.read("*l")
file_count = 0
while line != nil do
    rel = string.sub(line, string.len(test_store) + 2)
    valid = (rel == ".gpg-id") or (rel == "index.gpg") or (string.match(rel, "^%x%x%x%x%x%x%x%x%x%x%.gpg$") != nil)
    assert(valid, "Metadata leak in store filesystem: " .. rel)
    file_count = file_count + 1
    line = io.read("*l")
end
io.close(find_p)
io.input(io.stdin)
assert(file_count == 4, "Expected .gpg-id + index.gpg + 2 entries (4 files), got: " .. tostring(file_count))

-- Remove entry with -f
success, rm_out = run_cli("remove -f email/proton")
assert(string.find(rm_out, "Removed 'email/proton'", 1, true) != nil, "Remove failed: " .. rm_out)
success, list_after_rm = run_cli("list")
assert(list_after_rm == "github/personal\n", "List after remove mismatch: " .. list_after_rm)

-- Test 5: unhide error handling on empty uninitialized directory
empty_store = "/tmp/camopass_cli_empty"
test_unhide = "/tmp/camopass_cli_unhide"
os.execute("rm -rf " .. empty_store .. " " .. test_unhide .. " && mkdir -p " .. empty_store)
success, out = run_cli("unhide " .. empty_store .. " " .. test_unhide)
assert(string.find(out, "Unhide failed", 1, true) != nil, "Test Failed: unhide should fail on non-existent index")

-- Clean up
os.execute("rm -rf " .. test_store .. " " .. editor_script .. " " .. empty_store .. " " .. test_unhide)

print("""
===========================================
    ALL CAMOPASS CLI TESTS PASSED!
===========================================
""")
