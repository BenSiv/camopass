package.path = package.path .. ";./?.lua;src/?.lua"
require("obfuscator")

-- Print usage instructions using Luam's triple-quoted strings
function usage()
    print("""
CamoPass - Secure Metadata Obfuscator for Pass (MIT License)

Usage:
  camopass hide <source_store> <target_store> <gpg_id>
  camopass list <store_path>
  camopass show <store_path> <entry_name>
  camopass clip <store_path> <entry_name>
""")
    os.exit(false)
end

args = arg
if #args < 2 then
    usage()
end

cmd = args[1]

if cmd == "hide" then
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
    store_path = args[2]
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
    if #args != 3 then
        print("Error: show requires <store_path> <entry_name>")
        os.exit(false)
    end
    store_path = args[2]
    entry_name = args[3]
    
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
    if #args != 3 then
        print("Error: clip requires <store_path> <entry_name>")
        os.exit(false)
    end
    store_path = args[2]
    entry_name = args[3]
    
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
