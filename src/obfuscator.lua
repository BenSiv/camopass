-- CamoPass Core Obfuscator Library (Luam)

-- Helper: Resolve tilde (~) paths to absolute home directory paths and ensure absolute paths
function resolve_path(path)
    p = path
    if string.sub(p, 1, 2) == "~/" then
        p = os.getenv("HOME") .. string.sub(p, 2)
    elseif p == "~" then
        p = os.getenv("HOME")
    end
    
    -- Use realpath to ensure we have an absolute path (even if it doesn't exist yet)
    handle = io.popen("realpath -m " .. string.format("%q", p) .. " 2>/dev/null")
    if handle != nil then
        io.input(handle)
        result = io.read("*l")
        io.close(handle)
        if result != nil and result != "" then
            return result
        end
    end
    
    return p
end

-- Helper: Split a string by delimiter using a while loop (Luam style)
function split(str, sep)
    result = {}
    start = 1
    s_idx, e_idx = string.find(str, sep, start, true)
    while s_idx != nil do
        table.insert(result, string.sub(str, start, s_idx - 1))
        start = e_idx + 1
        s_idx, e_idx = string.find(str, sep, start, true)
    end
    table.insert(result, string.sub(str, start))
    return result
end

-- Helper: Trim whitespace
function trim(s)
    return string.match(s, "^%s*(.-)%s*$")
end

-- Helper: Generate a secure 16-character hex salt from /dev/urandom
function generate_salt()
    f = io.open("/dev/urandom", "rb")
    if f == nil then
        -- Fallback to pseudo-random generator
        math.randomseed(os.time())
        s = ""
        chars = "0123456789abcdef"
        i = 1
        while i <= 16 do
            r = math.random(1, 16)
            s = s .. string.sub(chars, r, r)
            i = i + 1
        end
        return s
    end
    io.input(f)
    bytes = io.read(8)
    io.close(f)
    if bytes == nil or string.len(bytes) == 0 then
        -- Fallback to pseudo-random generator
        math.randomseed(os.time())
        s = ""
        chars = "0123456789abcdef"
        i = 1
        while i <= 16 do
            r = math.random(1, 16)
            s = s .. string.sub(chars, r, r)
            i = i + 1
        end
        return s
    end
    s = ""
    i = 1
    while i <= string.len(bytes) do
        s = s .. string.format("%02x", string.byte(bytes, i))
        i = i + 1
    end
    return s
end

-- Helper: SHA-256 hash using system command
function sha256(str)
    cmd = "printf %s " .. string.format("%q", str) .. " | sha256sum 2>/dev/null"
    p = io.popen(cmd)
    if p == nil then
        cmd = "printf %s " .. string.format("%q", str) .. " | openssl dgst -sha256 2>/dev/null"
        p = io.popen(cmd)
    end
    if p == nil then
        -- Fallback to md5sum
        cmd = "printf %s " .. string.format("%q", str) .. " | md5sum 2>/dev/null"
        p = io.popen(cmd)
    end
    if p == nil then
        return nil
    end
    io.input(p)
    out = io.read("*a")
    io.close(p)
    hash = string.match(out, "(%x+)")
    return hash
end


-- Scan the store recursively for all non-hidden GPG files
-- index.gpg is always excluded: it is the store's own lookup index, never a credential,
-- and must never be treated as one (e.g. if source_path and target_path are ever the same).
function scan_store(store_path)
    store_path = resolve_path(store_path)
    files = {}
    p = io.popen("find " .. string.format("%q", store_path) .. " -name '*.gpg' -not -name 'index.gpg' -not -path '*/.git/*'")
    if p == nil then
        return files
    end
    
    io.input(p)
    line = io.read("*l")
    while line != nil do
        table.insert(files, line)
        line = io.read("*l")
    end
    io.close(p)
    
    -- Guarantee deterministic order
    table.sort(files)
    return files
end

-- Decrypt a GPG file in memory
function decrypt_file(filepath)
    filepath = resolve_path(filepath)
    -- Try quiet batch mode first (fast if cached)
    p = io.popen("gpg --quiet --batch --decrypt " .. string.format("%q", filepath) .. " 2>/dev/null")
    if p == nil then
        return nil
    end
    io.input(p)
    out = io.read("*a")
    success = io.close(p)
    
    if not success or out == "" then
        -- If batch fails, run with interactive prompts to display GUI pinentry
        p = io.popen("gpg --quiet --decrypt " .. string.format("%q", filepath) .. " 2>/dev/null")
        if p == nil then
            return nil
        end
        io.input(p)
        out = io.read("*a")
        io.close(p)
    end
    return out
end

-- Load and parse the decrypted index
function load_index(store_path)
    store_path = resolve_path(store_path)
    index_file = store_path .. "/index.gpg"
    test_f = io.open(index_file, "r")
    if test_f == nil then
        return nil
    end
    io.close(test_f)
    
    index_content = decrypt_file(index_file)
    if index_content == nil or index_content == "" then
        return nil
    end
    
    mappings = {}
    lines = split(index_content, "\n")
    i = 1
    while i <= #lines do
        line = trim(lines[i])
        if line != "" then
            parts = split(line, ":")
            if #parts >= 2 then
                mappings[trim(parts[1])] = trim(parts[2])
            end
        end
        i = i + 1
    end
    return mappings
end

-- Safety check for the insert/generate/edit/remove flow: obfuscate_store deletes
-- any target entry whose plaintext is missing from plain_store (by design, so that
-- "remove" propagates). That is only safe if plain_store already mirrors every other
-- entry target_store currently tracks. This detects an incomplete/misconfigured
-- plain_store (e.g. one that was never populated via unhide) before it causes
-- obfuscate_store to silently delete entries. touched_entry is excluded from the
-- check since it is expected to appear/disappear in plain_store as part of this call.
function check_plain_store_sync(target_store, plain_store, touched_entry)
    target_store = resolve_path(target_store)
    plain_store = resolve_path(plain_store)

    mappings = load_index(target_store)
    if mappings == nil then
        return true, nil
    end

    missing = {}
    k, v = next(mappings)
    while k != nil do
        if k != "__salt__" and k != touched_entry then
            f = io.open(plain_store .. "/" .. k .. ".gpg", "r")
            if f == nil then
                table.insert(missing, k)
            else
                io.close(f)
            end
        end
        k, v = next(mappings, k)
    end

    if #missing > 0 then
        return false, missing
    end
    return true, nil
end

-- Perform the complete metadata obfuscation
function obfuscate_store(source_path, target_path, gpg_id)
    source_path = resolve_path(source_path)
    target_path = resolve_path(target_path)

    if source_path == target_path then
        return false, "source_path and target_path must be different (hiding a store into itself would double-wrap every entry, including index.gpg)."
    end

    files = scan_store(source_path)
    if #files == 0 then
        return false, "No GPG credentials found in source store."
    end
    
    -- Ensure target directory exists
    os.execute("mkdir -p " .. string.format("%q", target_path))
    
    -- Load existing index to reuse salt if present
    salt = nil
    existing_mappings = load_index(target_path)
    if existing_mappings != nil then
        salt = existing_mappings["__salt__"]
    end
    
    if salt == nil or salt == "" then
        salt = generate_salt()
    end
    
    index_lines = {}
    valid_obf_names = { ["index"] = true }
    i = 1
    while i <= #files do
        filepath = files[i]
        rel_path = string.sub(filepath, string.len(source_path) + 2)
        human_name = string.sub(rel_path, 1, -5)
        
        -- Generate stable, deterministic obfuscated identifier (first 10 chars of sha256)
        hash = sha256(human_name .. salt)
        if hash == nil then
            return false, "Failed to compute stable hash for credential: " .. human_name
        end
        obf_name = string.sub(hash, 1, 10)
        valid_obf_names[obf_name] = true
        
        -- Copy encrypted GPG file directly (perfect security, zero decryption overhead)
        target_file = target_path .. "/" .. obf_name .. ".gpg"
        os.execute("cp " .. string.format("%q", filepath) .. " " .. string.format("%q", target_file))
        
        table.insert(index_lines, human_name .. " : " .. obf_name)
        i = i + 1
    end
    
    -- Cleanup orphaned .gpg files in the target store
    target_files = scan_store(target_path)
    i = 1
    while i <= #target_files do
        t_filepath = target_files[i]
        t_rel_path = string.sub(t_filepath, string.len(target_path) + 2)
        t_obf_name = string.sub(t_rel_path, 1, -5)
        
        if valid_obf_names[t_obf_name] == nil then
            os.execute("rm -f " .. string.format("%q", t_filepath))
        end
        i = i + 1
    end
    
    -- Add the salt to the index so we can retrieve it during future updates
    table.insert(index_lines, "__salt__ : " .. salt)
    
    -- Write temporary plaintext index in RAM, encrypt it, then shred it
    temp_index = "/dev/shm/index_temp.txt"
    f = io.open(temp_index, "w")
    if f == nil then
        return false, "Could not open RAM-based index buffer."
    end
    
    idx_content = table.concat(index_lines, "\n")
    io.output(f)
    io.write(idx_content)
    io.close(f)
    
    -- Encrypt index using the GPG recipient key ID
    encrypt_cmd = "gpg --batch --quiet --yes --always-trust --encrypt --recipient " .. string.format("%q", gpg_id) .. " --output " .. string.format("%q", target_path .. "/index.gpg") .. " " .. string.format("%q", temp_index)
    os.execute(encrypt_cmd)
    
    -- Shred GPG temporary buffer from RAM
    os.execute("shred -u -z -n 3 " .. string.format("%q", temp_index))
    
    -- Copy .gpg-id file to target directory
    os.execute("cp " .. string.format("%q", source_path .. "/.gpg-id") .. " " .. string.format("%q", target_path .. "/.gpg-id"))
    
    return true, "Successfully obfuscated " .. #files .. " entries."
end

-- Perform the reverse: decrypt index and restore plain files
function unhide_store(source_obfuscated, target_plain)
    source_obfuscated = resolve_path(source_obfuscated)
    target_plain = resolve_path(target_plain)
    
    mappings = load_index(source_obfuscated)
    if mappings == nil then
        return false, "Could not load or decrypt index.gpg from " .. source_obfuscated
    end
    
    os.execute("mkdir -p " .. string.format("%q", target_plain))
    
    count = 0
    k, v = next(mappings)
    while k != nil do
        if k != "__salt__" then
            human_name = k
            obf_name = v
            
            obf_file = source_obfuscated .. "/" .. obf_name .. ".gpg"
            plain_file = target_plain .. "/" .. human_name .. ".gpg"
            
            -- create directories
            plain_dir = string.match(plain_file, "^(.*)/[^/]+$")
            if plain_dir != nil then
                os.execute("mkdir -p " .. string.format("%q", plain_dir))
            end
            
            -- copy file
            os.execute("cp " .. string.format("%q", obf_file) .. " " .. string.format("%q", plain_file))
            count = count + 1
        end
        k, v = next(mappings, k)
    end
    
    -- copy gpg id
    os.execute("cp " .. string.format("%q", source_obfuscated .. "/.gpg-id") .. " " .. string.format("%q", target_plain .. "/.gpg-id"))
    
    return true, "Successfully unhid " .. count .. " entries."
end
