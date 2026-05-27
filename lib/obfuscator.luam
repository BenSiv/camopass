-- CamoPass Core Obfuscator Library (Luam)

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

-- Scan the store recursively for all non-hidden GPG files
function scan_store(store_path)
    files = {}
    p = io.popen("find " .. string.format("%q", store_path) .. " -name '*.gpg' -not -path '*/.*'")
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
    files = scan_store(source_path)
    if #files == 0 then
        return false, "No GPG credentials found in source store."
    end
    
    -- Ensure target directory exists
    os.execute("mkdir -p " .. string.format("%q", target_path))
    
    index_lines = {}
    i = 1
    while i <= #files do
        filepath = files[i]
        rel_path = string.sub(filepath, string.len(source_path) + 2)
        human_name = string.sub(rel_path, 1, -5)
        
        -- Generate sequential obfuscated identifier
        obf_name = "e" .. i
        
        -- Copy encrypted GPG file directly (perfect security, zero decryption overhead)
        target_file = target_path .. "/" .. obf_name .. ".gpg"
        os.execute("cp " .. string.format("%q", filepath) .. " " .. string.format("%q", target_file))
        
        table.insert(index_lines, human_name .. " : " .. obf_name)
        i = i + 1
    end
    
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
    encrypt_cmd = "gpg --batch --quiet --yes --encrypt --recipient " .. string.format("%q", gpg_id) .. " --output " .. string.format("%q", target_path .. "/index.gpg") .. " " .. string.format("%q", temp_index)
    os.execute(encrypt_cmd)
    
    -- Shred GPG temporary buffer from RAM
    os.execute("shred -u -z -n 3 " .. string.format("%q", temp_index))
    
    -- Copy .gpg-id file to target directory
    os.execute("cp " .. string.format("%q", source_path .. "/.gpg-id") .. " " .. string.format("%q", target_path .. "/.gpg-id"))
    
    return true, "Successfully obfuscated " .. #files .. " entries."
end
