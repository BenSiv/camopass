-- CamoPass Core Obfuscator Library (Luam)

-- Helper: Safe POSIX single-quote shell escaping (prevents $, `, \, and newline expansion in /bin/sh)
function shell_quote(s)
    return "'" .. string.gsub(tostring(s), "'", "'\\''") .. "'"
end

-- Helper: Resolve tilde (~) paths to absolute home directory paths and ensure absolute paths
function resolve_path(path)
    p = path
    if string.sub(p, 1, 2) == "~/" then
        p = os.getenv("HOME") .. string.sub(p, 2)
    elseif p == "~" then
        p = os.getenv("HOME")
    end

    -- Use realpath to ensure we have an absolute path (even if it doesn't exist yet)
    handle = io.popen("realpath -m " .. shell_quote(p) .. " 2>/dev/null")
    if handle != nil then
        io.input(handle)
        result = io.read("*l")
        io.close(handle)
        io.input(io.stdin)
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

-- Helper: Check if a file exists on disk
function file_exists(filepath)
    f = io.open(filepath, "rb")
    if f != nil then
        io.close(f)
        return true
    end
    return false
end

-- Helper: Securely shred and delete a temporary file
function shred_file(filepath)
    q = shell_quote(filepath)
    os.execute("shred -u -z -n 3 " .. q .. " 2>/dev/null || rm -f " .. q)
end

-- Helper: Normalize os.execute return value across Lua 5.1 / Luam builds
function exec_ok(status)
    return status == true or status == 0
end

-- Helper: Generate a secure 16-character hex salt from /dev/urandom
function generate_salt()
    f = io.open("/dev/urandom", "rb")
    if f == nil then
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
    io.input(io.stdin)
    if bytes == nil or string.len(bytes) == 0 then
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

-- Helper: Generate a cryptographically random password from /dev/urandom
function generate_password(length, no_symbols)
    len = length
    if len == nil or len < 1 then
        len = 25
    end

    charset = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*()-_=+[]{};:,.<>?/"
    if no_symbols == true then
        charset = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
    end

    n = string.len(charset)
    limit = math.floor(256 / n) * n

    f = io.open("/dev/urandom", "rb")
    if f == nil then
        return nil, "Could not open /dev/urandom for password generation."
    end

    io.input(f)
    out = ""
    while string.len(out) < len do
        chunk = io.read(64)
        if chunk == nil or string.len(chunk) == 0 then
            io.close(f)
            io.input(io.stdin)
            return nil, "Failed reading random bytes from /dev/urandom."
        end
        i = 1
        while i <= string.len(chunk) and string.len(out) < len do
            b = string.byte(chunk, i)
            if b < limit then
                idx = (b % n) + 1
                out = out .. string.sub(charset, idx, idx)
            end
            i = i + 1
        end
    end
    io.close(f)
    io.input(io.stdin)
    return out, nil
end

-- Helper: SHA-256 hash using system command
function sha256(str)
    q = shell_quote(str)
    cmd = "printf %s " .. q .. " | sha256sum 2>/dev/null"
    p = io.popen(cmd)
    if p == nil then
        cmd = "printf %s " .. q .. " | openssl dgst -sha256 2>/dev/null"
        p = io.popen(cmd)
    end
    if p == nil then
        cmd = "printf %s " .. q .. " | md5sum 2>/dev/null"
        p = io.popen(cmd)
    end
    if p == nil then
        return nil
    end
    io.input(p)
    out = io.read("*a")
    io.close(p)
    io.input(io.stdin)
    hash = string.match(out, "(%x+)")
    return hash
end

-- Compute deterministic 10-char obfuscated filename stem
function compute_obf_name(human_name, salt)
    hash = sha256(human_name .. salt)
    if hash == nil then
        return nil
    end
    return string.sub(hash, 1, 10)
end

-- Read the recipient GPG ID from <store_path>/.gpg-id
function read_gpg_id(store_path)
    store_path = resolve_path(store_path)
    gpg_id_file = store_path .. "/.gpg-id"
    f = io.open(gpg_id_file, "r")
    if f == nil then
        return nil, "Could not read .gpg-id from store: " .. store_path
    end
    io.input(f)
    line = io.read("*l")
    while line != nil do
        cleaned = trim(line)
        if cleaned != "" then
            io.close(f)
            io.input(io.stdin)
            return cleaned, nil
        end
        line = io.read("*l")
    end
    io.close(f)
    io.input(io.stdin)
    return nil, ".gpg-id is empty in store: " .. store_path
end

-- Allocate a private 0600 buffer path in /dev/shm (RAM tmpfs)
function create_ram_buffer(prefix, content)
    buf_path = "/dev/shm/camopass_" .. prefix .. "_" .. generate_salt() .. ".tmp"
    status = os.execute("umask 077 && : > " .. shell_quote(buf_path))
    if not exec_ok(status) then
        return nil, "Could not allocate private RAM buffer in /dev/shm."
    end
    f = io.open(buf_path, "wb")
    if f == nil then
        shred_file(buf_path)
        return nil, "Could not open RAM buffer for writing."
    end
    io.output(f)
    io.write(content)
    io.close(f)
    io.output(io.stdout)
    return buf_path, nil
end

-- Encrypt plaintext string atomically to output_path via a shredded /dev/shm buffer
function encrypt_text_to_file(content, gpg_id, output_path)
    buf_path, err = create_ram_buffer("enc", content)
    if buf_path == nil then
        return false, err
    end

    tmp_out = output_path .. ".tmp." .. generate_salt()
    encrypt_cmd = "gpg --batch --quiet --yes --always-trust --encrypt --recipient " .. shell_quote(gpg_id) .. " --output " .. shell_quote(tmp_out) .. " " .. shell_quote(buf_path)
    status = os.execute(encrypt_cmd)
    shred_file(buf_path)

    if not exec_ok(status) or not file_exists(tmp_out) then
        os.execute("rm -f " .. shell_quote(tmp_out))
        return false, "GPG encryption failed for recipient: " .. gpg_id
    end

    mv_status = os.execute("mv -f " .. shell_quote(tmp_out) .. " " .. shell_quote(output_path))
    if not exec_ok(mv_status) then
        os.execute("rm -f " .. shell_quote(tmp_out))
        return false, "Failed to move encrypted file into place: " .. output_path
    end

    return true, nil
end

-- Scan the store recursively for all non-hidden GPG files
-- index.gpg is always excluded: it is the store's own lookup index, never a credential.
function scan_store(store_path)
    store_path = resolve_path(store_path)
    files = {}
    p = io.popen("find " .. shell_quote(store_path) .. " -name '*.gpg' -not -name 'index.gpg' -not -path '*/.git/*'")
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
    io.input(io.stdin)

    table.sort(files)
    return files
end

-- Decrypt a GPG file via a private /dev/shm RAM buffer so GPG exit status is verified accurately
function decrypt_file(filepath)
    filepath = resolve_path(filepath)
    if not file_exists(filepath) then
        return nil
    end

    buf_path, buf_err = create_ram_buffer("dec", "")
    if buf_path == nil then
        return nil
    end

    -- Try quiet batch mode first (fast when gpg-agent already has key unlocked)
    batch_cmd = "gpg --quiet --batch --yes --output " .. shell_quote(buf_path) .. " --decrypt " .. shell_quote(filepath) .. " 2>/dev/null"
    status = os.execute(batch_cmd)
    if not exec_ok(status) then
        -- Fall back to interactive mode so GUI/TTY pinentry can prompt
        inter_cmd = "gpg --quiet --yes --output " .. shell_quote(buf_path) .. " --decrypt " .. shell_quote(filepath) .. " 2>/dev/null"
        status = os.execute(inter_cmd)
        if not exec_ok(status) then
            shred_file(buf_path)
            return nil
        end
    end

    f = io.open(buf_path, "rb")
    if f == nil then
        shred_file(buf_path)
        return nil
    end
    io.input(f)
    out = io.read("*a")
    io.close(f)
    io.input(io.stdin)
    shred_file(buf_path)
    return out
end

-- Load and parse the decrypted index
function load_index(store_path)
    store_path = resolve_path(store_path)
    index_file = store_path .. "/index.gpg"
    if not file_exists(index_file) then
        return nil
    end

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
            colon_idx = string.find(line, ":", 1, true)
            if colon_idx != nil then
                key = trim(string.sub(line, 1, colon_idx - 1))
                val = trim(string.sub(line, colon_idx + 1))
                if key != "" and val != "" then
                    mappings[key] = val
                end
            end
        end
        i = i + 1
    end
    return mappings
end

-- Load existing index.gpg (failing safely if decryption fails), or initialize a fresh mapping table if index.gpg does not exist yet
function load_or_create_index(store_path)
    store_path = resolve_path(store_path)
    index_file = store_path .. "/index.gpg"
    if file_exists(index_file) then
        mappings = load_index(store_path)
        if mappings == nil then
            return nil, "Could not decrypt index.gpg in " .. store_path
        end
        if mappings["__salt__"] == nil or mappings["__salt__"] == "" then
            mappings["__salt__"] = generate_salt()
        end
        return mappings, nil
    end

    return { ["__salt__"] = generate_salt() }, nil
end

-- Serialize and encrypt mappings table into <store_path>/index.gpg via RAM buffer
function save_index(store_path, mappings, gpg_id)
    store_path = resolve_path(store_path)
    salt = mappings["__salt__"]
    if salt == nil or salt == "" then
        salt = generate_salt()
        mappings["__salt__"] = salt
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

    index_lines = {}
    i = 1
    while i <= #keys do
        key = keys[i]
        table.insert(index_lines, key .. " : " .. mappings[key])
        i = i + 1
    end
    table.insert(index_lines, "__salt__ : " .. salt)

    idx_content = table.concat(index_lines, "\n") .. "\n"
    return encrypt_text_to_file(idx_content, gpg_id, store_path .. "/index.gpg")
end

-- Statelessly insert or update a single credential directly in the obfuscated store (zero plain_store on disk)
function upsert_entry(store_path, entry_name, content)
    store_path = resolve_path(store_path)
    entry_name = trim(entry_name)
    if entry_name == "" or entry_name == "__salt__" then
        return false, "Invalid entry name."
    end

    gpg_id, err = read_gpg_id(store_path)
    if gpg_id == nil then
        return false, err
    end

    mappings, idx_err = load_or_create_index(store_path)
    if mappings == nil then
        return false, idx_err
    end

    salt = mappings["__salt__"]
    obf_name = mappings[entry_name]
    if obf_name == nil or obf_name == "" then
        obf_name = compute_obf_name(entry_name, salt)
        if obf_name == nil then
            return false, "Failed to compute obfuscated identifier for: " .. entry_name
        end
    end

    payload = content
    if string.sub(payload, -1) != "\n" then
        payload = payload .. "\n"
    end

    ok, enc_err = encrypt_text_to_file(payload, gpg_id, store_path .. "/" .. obf_name .. ".gpg")
    if not ok then
        return false, enc_err
    end

    mappings[entry_name] = obf_name
    ok_idx, save_err = save_index(store_path, mappings, gpg_id)
    if not ok_idx then
        return false, save_err
    end

    return true, obf_name
end

-- Statelessly remove a single credential directly from the obfuscated store
function remove_entry(store_path, entry_name)
    store_path = resolve_path(store_path)
    entry_name = trim(entry_name)

    gpg_id, err = read_gpg_id(store_path)
    if gpg_id == nil then
        return false, err
    end

    mappings = load_index(store_path)
    if mappings == nil then
        return false, "Could not load or decrypt index.gpg from " .. store_path
    end

    obf_name = mappings[entry_name]
    if obf_name == nil then
        return false, "Entry '" .. entry_name .. "' not found in index."
    end

    target_file = store_path .. "/" .. obf_name .. ".gpg"
    shred_file(target_file)

    mappings[entry_name] = nil
    ok_idx, save_err = save_index(store_path, mappings, gpg_id)
    if not ok_idx then
        return false, save_err
    end

    return true, "Removed '" .. entry_name .. "' from store."
end

-- Statelessly edit a single credential via a shredded /dev/shm RAM buffer and $EDITOR
function edit_entry(store_path, entry_name)
    store_path = resolve_path(store_path)
    entry_name = trim(entry_name)
    if entry_name == "" or entry_name == "__salt__" then
        return false, "Invalid entry name."
    end

    gpg_id, err = read_gpg_id(store_path)
    if gpg_id == nil then
        return false, err
    end

    mappings, idx_err = load_or_create_index(store_path)
    if mappings == nil then
        return false, idx_err
    end

    existing = ""
    existing_obf = mappings[entry_name]
    if existing_obf != nil then
        obf_file = store_path .. "/" .. existing_obf .. ".gpg"
        if file_exists(obf_file) then
            decrypted = decrypt_file(obf_file)
            if decrypted == nil then
                return false, "Failed to decrypt existing entry: " .. entry_name
            end
            existing = decrypted
        end
    end

    buf_path, buf_err = create_ram_buffer("edit", existing)
    if buf_path == nil then
        return false, buf_err
    end

    editor = os.getenv("EDITOR")
    if editor == nil or editor == "" then
        editor = os.getenv("VISUAL")
    end
    if editor == nil or editor == "" then
        editor = "vi"
    end

    edit_status = os.execute(editor .. " " .. shell_quote(buf_path))
    if not exec_ok(edit_status) then
        shred_file(buf_path)
        return false, "Editor exited with non-zero status; aborting edit."
    end

    f = io.open(buf_path, "rb")
    if f == nil then
        shred_file(buf_path)
        return false, "Temporary buffer missing after editor closed."
    end
    io.input(f)
    updated = io.read("*a")
    io.close(f)
    io.input(io.stdin)
    shred_file(buf_path)

    if updated == nil or trim(updated) == "" then
        return false, "Empty credential content; aborting edit."
    end

    if updated == existing then
        return true, "Password unchanged."
    end

    ok, up_err = upsert_entry(store_path, entry_name, updated)
    if not ok then
        return false, up_err
    end

    return true, "Updated '" .. entry_name .. "'."
end

-- Safety check retained for backwards compatibility with callers migrating from a plain_store
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
            if not file_exists(plain_store .. "/" .. k .. ".gpg") then
                table.insert(missing, k)
            end
        end
        k, v = next(mappings, k)
    end

    if #missing > 0 then
        return false, missing
    end
    return true, nil
end

-- Perform a full one-shot metadata obfuscation from an existing standard pass directory
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

    os.execute("mkdir -p " .. shell_quote(target_path))

    salt = nil
    existing_mappings = load_index(target_path)
    if existing_mappings != nil then
        salt = existing_mappings["__salt__"]
    end

    if salt == nil or salt == "" then
        salt = generate_salt()
    end

    new_mappings = { ["__salt__"] = salt }
    valid_obf_names = { ["index"] = true }
    i = 1
    while i <= #files do
        filepath = files[i]
        rel_path = string.sub(filepath, string.len(source_path) + 2)
        human_name = string.sub(rel_path, 1, -5)

        obf_name = compute_obf_name(human_name, salt)
        if obf_name == nil then
            return false, "Failed to compute stable hash for credential: " .. human_name
        end
        valid_obf_names[obf_name] = true

        target_file = target_path .. "/" .. obf_name .. ".gpg"
        os.execute("cp " .. shell_quote(filepath) .. " " .. shell_quote(target_file))

        new_mappings[human_name] = obf_name
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
            shred_file(t_filepath)
        end
        i = i + 1
    end

    ok_idx, idx_err = save_index(target_path, new_mappings, gpg_id)
    if not ok_idx then
        return false, idx_err
    end

    if file_exists(source_path .. "/.gpg-id") then
        os.execute("cp " .. shell_quote(source_path .. "/.gpg-id") .. " " .. shell_quote(target_path .. "/.gpg-id"))
    else
        f = io.open(target_path .. "/.gpg-id", "w")
        if f != nil then
            io.output(f)
            io.write(gpg_id .. "\n")
            io.close(f)
            io.output(io.stdout)
        end
    end

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

    os.execute("mkdir -p " .. shell_quote(target_plain))

    count = 0
    k, v = next(mappings)
    while k != nil do
        if k != "__salt__" then
            human_name = k
            obf_name = v

            obf_file = source_obfuscated .. "/" .. obf_name .. ".gpg"
            plain_file = target_plain .. "/" .. human_name .. ".gpg"

            plain_dir = string.match(plain_file, "^(.*)/[^/]+$")
            if plain_dir != nil then
                os.execute("mkdir -p " .. shell_quote(plain_dir))
            end

            os.execute("cp " .. shell_quote(obf_file) .. " " .. shell_quote(plain_file))
            count = count + 1
        end
        k, v = next(mappings, k)
    end

    os.execute("cp " .. shell_quote(source_obfuscated .. "/.gpg-id") .. " " .. shell_quote(target_plain .. "/.gpg-id"))

    return true, "Successfully unhid " .. count .. " entries."
end

-- Public API. Luam makes bare function statements local to this file, so
-- callers reach these through the table require("obfuscator") returns.
obfuscator = {}
obfuscator.shell_quote = shell_quote
obfuscator.resolve_path = resolve_path
obfuscator.split = split
obfuscator.trim = trim
obfuscator.file_exists = file_exists
obfuscator.exec_ok = exec_ok
obfuscator.generate_password = generate_password
obfuscator.read_gpg_id = read_gpg_id
obfuscator.decrypt_file = decrypt_file
obfuscator.load_index = load_index
obfuscator.load_or_create_index = load_or_create_index
obfuscator.save_index = save_index
obfuscator.upsert_entry = upsert_entry
obfuscator.remove_entry = remove_entry
obfuscator.edit_entry = edit_entry
obfuscator.check_plain_store_sync = check_plain_store_sync
obfuscator.obfuscate_store = obfuscate_store
obfuscator.unhide_store = unhide_store

return obfuscator
