package.path = package.path .. ";./?.lua;src/?.lua"
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

-- Print usage instructions using Luam's triple-quoted strings
function usage()
    print("""
CamoPass - Secure Metadata Obfuscator for Pass (MIT License)

Usage:
  camopass init <store_path>
  camopass hide <source_store> <target_store> <gpg_id>
  camopass list [<store_path>]
  camopass show [<store_path>] <entry_name>
  camopass clip [<store_path>] <entry_name>
""")
    os.exit(false)
end

args = arg
if #args < 1 then
    usage()
end

cmd = args[1]

if cmd == "init" then
    if #args != 2 then
        print("Error: init requires <store_path>")
        os.exit(false)
    end
    store_path = resolve_path(args[2])
    
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
    io.write('{\n  "default_store": "' .. store_path .. '"\n}\n')
    io.close(f)
    print("Successfully initialized default store path: " .. store_path)

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
        table.insert(keys, k)
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
        os.exit(false)
    end
    
    mappings = load_index(store_path)
    if mappings == nil then
        os.exit(false)
    end
    
    obf_file = mappings[entry_name]
    if obf_file == nil then
        os.exit(false)
    end
    
    filepath = store_path .. "/" .. obf_file .. ".gpg"
    decrypted = decrypt_file(filepath)
    if decrypted == nil or decrypted == "" then
        os.exit(false)
    end
    
    lines = split(decrypted, "\n")
    if #lines == 0 then
        os.exit(false)
    end
    password = lines[1]
    
    -- Securely stream the decrypted password into wl-copy silently
    p = io.popen("wl-copy", "w")
    if p != nil then
        io.output(p)
        io.write(password)
        io.close(p)
        
        -- Fork a background process to clear Wayland clipboard after 45 seconds
        os.execute("(sleep 45 && wl-copy --clear) >/dev/null 2>&1 &")
    end

else
    usage()
end
