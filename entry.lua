-- Dynamically locate the script's directory to allow execution from any path
local_path = "."
if arg != nil and arg[0] != nil then
    dir_match = string.match(arg[0], "^(.-)[/\\][^/\\]-$")
    if dir_match != nil and dir_match != "" then
        local_path = dir_match
    end
end
package.path = package.path .. ";" .. local_path .. "/?.lua;" .. local_path .. "/src/?.lua"
require("obfuscator")

-- Helper: Retrieve and validate default store path from settings.json if not passed explicitly
function get_store_path(passed_path)
    if passed_path != nil and passed_path != "" then
        return resolve_path(passed_path)
    end
    
    settings_file = resolve_path("~/.config/camopass/settings.json")
    f = io.open(settings_file, "r")
    if f == nil then
        print("Error: No store path provided, and ~/.config/camopass/settings.json does not exist.")
        print("Please run 'camopass init <store_path>' first to set a default store.")
        os.exit(false)
    end
    io.input(f)
    content = io.read("*a")
    io.close(f)
    
    default_store = string.match(content, '"default_store"%s*:%s*"([^"]+)"')
    if default_store == nil then
        print("Error: Invalid settings.json configuration. Please run 'camopass init <store_path>' to reinitialize.")
        os.exit(false)
    end
    return resolve_path(default_store)
end

-- Helper: Retrieve and validate plain store path from settings.json
function get_plain_store_path()
    settings_file = resolve_path("~/.config/camopass/settings.json")
    f = io.open(settings_file, "r")
    if f == nil then
        return nil
    end
    io.input(f)
    content = io.read("*a")
    io.close(f)
    
    plain_store = string.match(content, '"plain_store"%s*:%s*"([^"]+)"')
    if plain_store == nil then
        return nil
    end
    return resolve_path(plain_store)
end

-- Print usage instructions using Luam's triple-quoted strings
function usage()
    print("""
CamoPass - Secure Metadata Obfuscator for Pass (MIT License)

Usage:
  camopass init <store_path> [<plain_store_path>]
  camopass hide <source_store> <target_store> <gpg_id>
  camopass insert <entry_name>
  camopass generate <entry_name> [<length>]
  camopass list [<store_path>]
  camopass show [<store_path>] <entry_name>
  camopass clip [<store_path>] <entry_name>
  camopass edit <entry_name>
  camopass remove <entry_name>
  camopass sync
""")
    os.exit(false)
end

args = arg
if #args < 1 then
    usage()
end

cmd = args[1]

if cmd == "init" then
    if #args != 2 and #args != 3 then
        print("Error: init requires <store_path> [<plain_store_path>]")
        os.exit(false)
    end
    store_path = resolve_path(args[2])
    os.execute("mkdir -p " .. string.format("%q", store_path))
    plain_store_path = nil
    if #args == 3 then
        plain_store_path = resolve_path(args[3])
        os.execute("mkdir -p " .. string.format("%q", plain_store_path))
    end
    
    -- Ensure configuration directory exists
    config_dir = resolve_path("~/.config/camopass")
    os.execute("mkdir -p " .. string.format("%q", config_dir))
    
    -- Write settings.json
    settings_file = config_dir .. "/settings.json"
    f = io.open(settings_file, "w")
    if f == nil then
        print("Error: Could not write settings to " .. settings_file)
        os.exit(false)
    end
    io.output(f)
    if plain_store_path != nil then
        io.write('{\n  "default_store": "' .. store_path .. '",\n  "plain_store": "' .. plain_store_path .. '"\n}\n')
    else
        io.write('{\n  "default_store": "' .. store_path .. '"\n}\n')
    end
    io.close(f)
    if plain_store_path != nil then
        print("Successfully initialized default store path: " .. store_path .. " and plain store path: " .. plain_store_path)
    else
        print("Successfully initialized default store path: " .. store_path)
    end

elseif cmd == "hide" then
    if #args != 4 then
        print("Error: hide requires <source_store> <target_store> <gpg_id>")
        os.exit(false)
    end
    success, err = obfuscate_store(args[2], args[3], args[4])
    if not success then
        print("Obfuscation failed: " .. err)
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
    
    mappings = load_index(store_path)
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
    
    mappings = load_index(store_path)
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
    decrypted = decrypt_file(filepath)
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
    
    mappings = load_index(store_path)
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
    decrypted = decrypt_file(filepath)
    if decrypted == nil or decrypted == "" then
        print("Error: Decryption failed or file is empty.")
        os.exit(false)
    end
    
    lines = split(decrypted, "\n")
    if #lines == 0 then
        print("Error: Decrypted content has no lines.")
        os.exit(false)
    end
    password = lines[1]
    
    -- Use a more robust clipboard copying strategy (Wayland then X11 fallback)
    success = false
    p = io.popen("wl-copy", "w")
    if p != nil then
        io.output(p)
        io.write(password)
        io.close(p)
        success = true
    end
    
    if not success then
        p = io.popen("xclip -selection clipboard", "w")
        if p != nil then
            io.output(p)
            io.write(password)
            io.close(p)
            success = true
        end
    end

    if success then
        -- Fork a background process to clear clipboard after 45 seconds
        -- Try clearing both Wayland and X11 clipboards
        os.execute("(sleep 45 && (wl-copy --clear || xclip -selection clipboard /dev/null)) >/dev/null 2>&1 &")
    else
        print("Error: Could not copy to clipboard. Please ensure 'wl-clipboard' or 'xclip' is installed.")
        os.exit(false)
    end

elseif cmd == "insert" or cmd == "generate" or cmd == "edit" or cmd == "remove" then
    if #args < 2 then
        print("Error: " .. cmd .. " requires <entry_name>")
        os.exit(false)
    end
    entry_name = args[2]
    
    plain_store = get_plain_store_path()
    target_store = get_store_path(nil)
    
    if plain_store == nil then
        print("Error: plain_store is not configured in settings.json.")
        print("Please run 'camopass init <default_store> <plain_store>' to initialize both.")
        os.exit(false)
    end
    
    -- 1. Read GPG key ID from the plain store's .gpg-id
    gpg_id_file = plain_store .. "/.gpg-id"
    f = io.open(gpg_id_file, "r")
    if f == nil then
        print("Error: Could not read .gpg-id from plain store: " .. plain_store)
        os.exit(false)
    end
    io.input(f)
    gpg_id = io.read("*l")
    io.close(f)
    if gpg_id == nil or gpg_id == "" then
        print("Error: .gpg-id is empty in plain store.")
        os.exit(false)
    end
    gpg_id = string.gsub(gpg_id, "%s+", "")
    
    -- 2. Execute pass command targeting plain_store
    status = nil
    if cmd == "insert" then
        cmd_str = string.format("PASSWORD_STORE_DIR=%q pass insert %q", plain_store, entry_name)
        status = os.execute(cmd_str)
    elseif cmd == "edit" then
        cmd_str = string.format("PASSWORD_STORE_DIR=%q pass edit %q", plain_store, entry_name)
        status = os.execute(cmd_str)
    elseif cmd == "remove" then
        cmd_str = string.format("PASSWORD_STORE_DIR=%q pass rm %q", plain_store, entry_name)
        status = os.execute(cmd_str)
    else
        extra_args = ""
        i = 3
        while i <= #args do
            extra_args = extra_args .. " " .. args[i]
            i = i + 1
        end
        cmd_str = string.format("PASSWORD_STORE_DIR=%q pass generate %q%s", plain_store, entry_name, extra_args)
        status = os.execute(cmd_str)
    end
    
    if status == true or status == 0 then
        print("Successfully updated plain store! Re-hiding to target store...")
        
        -- 3. Run the obfuscation hide logic
        success, err = obfuscate_store(plain_store, target_store, gpg_id)
        if not success then
            print("Obfuscation failed: " .. err)
            os.exit(false)
        end
        print("Obfuscation successful!")
        
        -- 4. Check if target store is a Git repository and commit/push
        status_git = os.execute("git -C " .. string.format("%q", target_store) .. " rev-parse --is-inside-work-tree >/dev/null 2>&1")
        if status_git == true or status_git == 0 then
            print("Syncing with target Git repository...")
            os.execute("git -C " .. string.format("%q", target_store) .. " add -A")
            os.execute("git -C " .. string.format("%q", target_store) .. " commit -m " .. string.format("%q", "CamoPass sync"))
            os.execute("git -C " .. string.format("%q", target_store) .. " push")
            print("Git sync complete!")
        end
    else
        print("Error: pass " .. cmd .. " command failed.")
        os.exit(false)
    end

elseif cmd == "sync" then
    plain_store = get_plain_store_path()
    target_store = get_store_path(nil)
    
    if target_store != nil then
        status_git = os.execute("git -C " .. string.format("%q", target_store) .. " rev-parse --is-inside-work-tree >/dev/null 2>&1")
        if status_git == true or status_git == 0 then
            print("Syncing target store with Git repository...")
            os.execute("git -C " .. string.format("%q", target_store) .. " add -A")
            os.execute("git -C " .. string.format("%q", target_store) .. " commit -m " .. string.format("%q", "CamoPass sync") .. " >/dev/null 2>&1")
            os.execute("git -C " .. string.format("%q", target_store) .. " push")
            print("Git sync complete!")
        else
            print("Target store is not a Git repository.")
        end
    end

else
    usage()
end
