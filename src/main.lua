-- Dynamically locate the script's directory to allow execution from any path
local_path = "."
if arg != nil and arg[0] != nil then
    dir_match = string.match(arg[0], "^(.-)[/\\][^/\\]-$")
    if dir_match != nil and dir_match != "" then
        local_path = dir_match
    end
end
package.path = package.path .. ";" .. local_path .. "/?.lua"
const dkjson = require("dkjson")
const git = require("git")
const obfuscator = require("obfuscator")
const paths = require("paths")

-- Retrieve and validate default store path from settings.json if not passed explicitly
function get_store_path(passed_path)
    if passed_path != nil and passed_path != "" then
        return obfuscator.resolve_path(passed_path)
    end

    settings_file = obfuscator.resolve_path("~/.config/camopass/settings.json")
    content = paths.read_file(settings_file)
    if content == nil then
        print("Error: No store path provided, and ~/.config/camopass/settings.json does not exist.")
        print("Please run 'camopass init <store_path> [<gpg_id>]' first to set a default store.")
        os.exit(false)
    end

    parsed = dkjson.decode(content)
    if type(parsed) != "table" or type(parsed.default_store) != "string" or parsed.default_store == "" then
        print("Error: Invalid settings.json configuration. Please run 'camopass init <store_path> [<gpg_id>]' to reinitialize.")
        os.exit(false)
    end
    return obfuscator.resolve_path(parsed.default_store)
end

function stderr_write(text)
    io.write(io.stderr, text)
    io.flush(io.stderr)
end

-- Helper: Check if stdin is an interactive TTY
function stdin_is_tty()
    return obfuscator.exec_ok(os.execute("test -t 0"))
end

-- Helper: Read a single line from stdin without echoing when TTY
function read_secret_line(prompt)
    if stdin_is_tty() then
        stderr_write(prompt)
        os.execute("stty -echo 2>/dev/null")
        io.input(io.stdin)
        line = io.read("*l")
        os.execute("stty echo 2>/dev/null")
        stderr_write("\n")
        return line
    end
    io.input(io.stdin)
    return io.read("*l")
end

-- Helper: Confirm overwrite/delete when interactive
function confirm_prompt(prompt)
    if not stdin_is_tty() then
        return true
    end
    stderr_write(prompt .. " [y/N] ")
    io.input(io.stdin)
    ans = io.read("*l")
    if ans == nil then
        return false
    end
    ans = string.lower(obfuscator.trim(ans))
    return ans == "y" or ans == "yes"
end

function sync_git_if_repo(target_store)
    q_store = obfuscator.shell_quote(target_store)
    if git.is_repo(target_store) then
        print("Syncing target store with Git repository...")
        os.execute("git -C " .. q_store .. " add -A")
        os.execute("git -C " .. q_store .. " commit -m 'CamoPass sync' >/dev/null 2>&1")
        has_remote = os.execute("git -C " .. q_store .. " remote | grep -q .")
        if obfuscator.exec_ok(has_remote) then
            os.execute("git -C " .. q_store .. " push")
        end
        print("Git sync complete!")
        return true
    end
    return false
end

-- Print usage instructions using Luam's triple-quoted strings
function usage()
    print(string.dedent("""
CamoPass - Secure Metadata Obfuscator for Pass (MIT License)

Usage:
  camopass init <store_path> [<gpg_id>]
  camopass hide <source_store> <target_store> <gpg_id>
  camopass unhide <obfuscated_store> <plain_store>
  camopass insert [-m|--multiline] [-f|--force] <entry_name>
  camopass generate [-n|--no-symbols] [-f|--force] <entry_name> [<length>]
  camopass list [<store_path>]
  camopass show [<store_path>] <entry_name>
  camopass clip [<store_path>] <entry_name>
  camopass edit <entry_name>
  camopass remove [-f|--force] <entry_name>
  camopass sync [<store_path>]
"""))
    os.exit(false)
end

args = arg
if #args < 1 then
    usage()
end

cmd = args[1]

if cmd == "init" then
    if #args != 2 and #args != 3 then
        print("Error: init requires <store_path> [<gpg_id>]")
        os.exit(false)
    end
    store_path = obfuscator.resolve_path(args[2])
    os.execute("mkdir -p " .. obfuscator.shell_quote(store_path))

    gpg_id = nil
    if #args == 3 then
        gpg_id = obfuscator.trim(args[3])
        if gpg_id != "" then
            gpg_file = io.open(store_path .. "/.gpg-id", "w")
            if gpg_file == nil then
                print("Error: Could not write .gpg-id to " .. store_path)
                os.exit(false)
            end
            io.output(gpg_file)
            io.write(gpg_id .. "\n")
            io.close(gpg_file)
            io.output(io.stdout)

            if not obfuscator.file_exists(store_path .. "/index.gpg") then
                mappings, idx_err = obfuscator.load_or_create_index(store_path)
                if mappings == nil then
                    print("Error: " .. idx_err)
                    os.exit(false)
                end
                ok_idx, save_err = obfuscator.save_index(store_path, mappings, gpg_id)
                if not ok_idx then
                    print("Error: " .. save_err)
                    os.exit(false)
                end
            end
        end
    end

    config_dir = obfuscator.resolve_path("~/.config/camopass")
    settings_file = config_dir .. "/settings.json"
    ok_w, _ = paths.write_atomic(settings_file, dkjson.encode({default_store = store_path}, {indent = true}) .. "\n")
    if not ok_w then
        print("Error: Could not write settings to " .. settings_file)
        os.exit(false)
    end

    if gpg_id != nil and gpg_id != "" then
        print("Successfully initialized store: " .. store_path .. " (GPG ID: " .. gpg_id .. ")")
    else
        print("Successfully initialized default store path: " .. store_path)
    end

elseif cmd == "hide" then
    if #args != 4 then
        print("Error: hide requires <source_store> <target_store> <gpg_id>")
        os.exit(false)
    end
    success, err = obfuscator.obfuscate_store(args[2], args[3], args[4])
    if not success then
        print("Obfuscation failed: " .. err)
        os.exit(false)
    end
    print(err)

elseif cmd == "unhide" then
    if #args != 3 then
        print("Error: unhide requires <obfuscated_store> <plain_store>")
        os.exit(false)
    end
    success, err = obfuscator.unhide_store(args[2], args[3])
    if not success then
        print("Unhide failed: " .. err)
        os.exit(false)
    end
    print(err)

elseif cmd == "list" then
    store_path = nil
    if #args >= 2 then
        store_path = get_store_path(args[2])
    else
        store_path = get_store_path(nil)
    end

    mappings = obfuscator.load_index(store_path)
    if mappings == nil then
        print("Error: Could not load index.gpg from " .. store_path)
        os.exit(false)
    end

    keys = {}
    k, v = next(mappings)
    while k != nil do
        if k != "__salt__" then
            table.insert(keys, k)
        end
        k, v = next(mappings, k)
    end
    table.sort(keys)

    i = 1
    while i <= #keys do
        print(keys[i])
        i = i + 1
    end

elseif cmd == "show" then
    store_path = nil
    entry_name = nil
    if #args == 2 then
        store_path = get_store_path(nil)
        entry_name = args[2]
    elseif #args == 3 then
        store_path = get_store_path(args[2])
        entry_name = args[3]
    else
        print("Error: show requires <entry_name> [or <store_path> <entry_name>]")
        os.exit(false)
    end

    mappings = obfuscator.load_index(store_path)
    if mappings == nil then
        print("Error: Could not load index.gpg")
        os.exit(false)
    end

    obf_file = mappings[entry_name]
    if obf_file == nil then
        print("Error: Entry '" .. entry_name .. "' not found in index.")
        os.exit(false)
    end

    filepath = store_path .. "/" .. obf_file .. ".gpg"
    decrypted = obfuscator.decrypt_file(filepath)
    if decrypted == nil then
        print("Error: Decryption failed.")
        os.exit(false)
    end
    io.write(decrypted)

elseif cmd == "clip" then
    store_path = nil
    entry_name = nil
    if #args == 2 then
        store_path = get_store_path(nil)
        entry_name = args[2]
    elseif #args == 3 then
        store_path = get_store_path(args[2])
        entry_name = args[3]
    else
        print("Error: clip requires <entry_name> [or <store_path> <entry_name>]")
        os.exit(false)
    end

    mappings = obfuscator.load_index(store_path)
    if mappings == nil then
        print("Error: Could not load index.gpg from " .. store_path)
        os.exit(false)
    end

    obf_file = mappings[entry_name]
    if obf_file == nil then
        print("Error: Entry '" .. entry_name .. "' not found in index.")
        os.exit(false)
    end

    filepath = store_path .. "/" .. obf_file .. ".gpg"
    decrypted = obfuscator.decrypt_file(filepath)
    if decrypted == nil or decrypted == "" then
        print("Error: Decryption failed or file is empty.")
        os.exit(false)
    end

    lines = obfuscator.split(decrypted, "\n")
    if #lines == 0 then
        print("Error: Decrypted content has no lines.")
        os.exit(false)
    end
    password = lines[1]

    success = false
    if obfuscator.exec_ok(os.execute("command -v wl-copy >/dev/null 2>&1")) then
        p = io.popen("wl-copy", "w")
        if p != nil then
            io.output(p)
            io.write(password)
            io.close(p)
            io.output(io.stdout)
            success = true
        end
    end

    if not success and obfuscator.exec_ok(os.execute("command -v xclip >/dev/null 2>&1")) then
        p = io.popen("xclip -selection clipboard", "w")
        if p != nil then
            io.output(p)
            io.write(password)
            io.close(p)
            io.output(io.stdout)
            success = true
        end
    end

    if success then
        os.execute("(sleep 45 && (wl-copy --clear || xclip -selection clipboard /dev/null)) >/dev/null 2>&1 &")
    else
        print("Error: Could not copy to clipboard. Please ensure 'wl-clipboard' or 'xclip' is installed.")
        os.exit(false)
    end

elseif cmd == "insert" then
    multiline = false
    force = false
    positional = {}
    i = 2
    while i <= #args do
        a = args[i]
        if a == "-m" or a == "--multiline" then
            multiline = true
        elseif a == "-f" or a == "--force" then
            force = true
        else
            table.insert(positional, a)
        end
        i = i + 1
    end

    if #positional != 1 then
        print("Error: insert requires [-m|--multiline] [-f|--force] <entry_name>")
        os.exit(false)
    end

    entry_name = positional[1]
    target_store = get_store_path(nil)

    existing_mappings, idx_err = obfuscator.load_or_create_index(target_store)
    if existing_mappings == nil then
        print("Error: " .. idx_err)
        os.exit(false)
    end
    if existing_mappings[entry_name] != nil and not force then
        if not confirm_prompt("An entry already exists for " .. entry_name .. ". Overwrite it?") then
            os.exit(false)
        end
    end

    content = nil
    if multiline then
        if stdin_is_tty() then
            print("Enter contents of " .. entry_name .. " and press Ctrl+D when finished:")
        end
        io.input(io.stdin)
        content = io.read("*a")
    elseif stdin_is_tty() then
        pw1 = read_secret_line("Enter password for " .. entry_name .. ": ")
        pw2 = read_secret_line("Retype password for " .. entry_name .. ": ")
        if pw1 == nil or pw1 != pw2 then
            print("Error: the entered passwords do not match.")
            os.exit(false)
        end
        content = pw1
    else
        io.input(io.stdin)
        content = io.read("*a")
    end

    if content == nil or obfuscator.trim(content) == "" then
        print("Error: password cannot be empty.")
        os.exit(false)
    end

    ok, err = obfuscator.upsert_entry(target_store, entry_name, content)
    if not ok then
        print("Error: " .. err)
        os.exit(false)
    end
    print("Saved '" .. entry_name .. "' directly to obfuscated store.")
    sync_git_if_repo(target_store)

elseif cmd == "generate" then
    no_symbols = false
    force = false
    positional = {}
    i = 2
    while i <= #args do
        a = args[i]
        if a == "-n" or a == "--no-symbols" then
            no_symbols = true
        elseif a == "-f" or a == "--force" then
            force = true
        else
            table.insert(positional, a)
        end
        i = i + 1
    end

    if #positional < 1 or #positional > 2 then
        print("Error: generate requires [-n|--no-symbols] [-f|--force] <entry_name> [<length>]")
        os.exit(false)
    end

    entry_name = positional[1]
    pw_len = 25
    if #positional == 2 then
        pw_len = tonumber(positional[2])
        if pw_len == nil or pw_len < 1 then
            print("Error: password length must be a positive integer.")
            os.exit(false)
        end
    end

    target_store = get_store_path(nil)
    existing_mappings, idx_err = obfuscator.load_or_create_index(target_store)
    if existing_mappings == nil then
        print("Error: " .. idx_err)
        os.exit(false)
    end
    if existing_mappings[entry_name] != nil and not force then
        if not confirm_prompt("An entry already exists for " .. entry_name .. ". Overwrite it?") then
            os.exit(false)
        end
    end

    pw, gen_err = obfuscator.generate_password(pw_len, no_symbols)
    if pw == nil then
        print("Error: " .. gen_err)
        os.exit(false)
    end

    ok, err = obfuscator.upsert_entry(target_store, entry_name, pw)
    if not ok then
        print("Error: " .. err)
        os.exit(false)
    end
    print("The generated password for " .. entry_name .. " is:")
    print(pw)
    sync_git_if_repo(target_store)

elseif cmd == "edit" then
    if #args != 2 then
        print("Error: edit requires <entry_name>")
        os.exit(false)
    end
    entry_name = args[2]
    target_store = get_store_path(nil)

    ok, msg = obfuscator.edit_entry(target_store, entry_name)
    if not ok then
        print("Error: " .. msg)
        os.exit(false)
    end
    print(msg)
    if msg != "Password unchanged." then
        sync_git_if_repo(target_store)
    end

elseif cmd == "remove" then
    force = false
    positional = {}
    i = 2
    while i <= #args do
        a = args[i]
        if a == "-f" or a == "--force" then
            force = true
        else
            table.insert(positional, a)
        end
        i = i + 1
    end

    if #positional != 1 then
        print("Error: remove requires [-f|--force] <entry_name>")
        os.exit(false)
    end

    entry_name = positional[1]
    target_store = get_store_path(nil)

    if not force then
        if not confirm_prompt("Are you sure you would like to delete " .. entry_name .. "?") then
            os.exit(false)
        end
    end

    ok, msg = obfuscator.remove_entry(target_store, entry_name)
    if not ok then
        print("Error: " .. msg)
        os.exit(false)
    end
    print(msg)
    sync_git_if_repo(target_store)

elseif cmd == "sync" then
    target_store = nil
    if #args >= 2 then
        target_store = get_store_path(args[2])
    else
        target_store = get_store_path(nil)
    end

    if not sync_git_if_repo(target_store) then
        print("Target store is not a Git repository.")
    end

else
    usage()
end
