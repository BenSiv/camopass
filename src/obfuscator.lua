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
function scan_store(store_path)
    store_path = resolve_path(store_path)
    files = {}
    p = io.popen("find " .. string.format("%q", store_path) .. " -name '*.gpg' -not -path '*/.git/*'")
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

-- Perform the complete metadata obfuscation
function obfuscate_store(source_path, target_path, gpg_id)
    source_path = resolve_path(source_path)
    target_path = resolve_path(target_path)
    
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
