# CamoPass

**CamoPass** is an open-source, stealthy, metadata-private password store enhancer for standard `pass`. It is written natively in **Luam** (a strict, safe, modern fork of Lua 5.1).

It resolves the primary privacy risk of standard `pass` stores: **plaintext metadata exposure**. 

While `pass` encrypts your password contents, it leaves your folder structures, account names, and file paths fully visible in plaintext. If you push your store to a private GitHub repository for backups or mobile sync, any observer can enumerate every single financial, email, or personal service you use.

CamoPass solves this by **obfuscating your entire password store filesystem** into generic, non-descriptive paths while maintaining a securely encrypted central lookup index (`index.gpg`).

---

## Key Features

* **Absolute Metadata Privacy:** Directory hierarchies, filenames, and change-history are replaced by completely opaque hash-based identifiers (e.g. `0a1b2c3d4e.gpg`). GitHub sees absolutely zero service names or account identities.
* **Perfect Security & Zero Decryption during Migration:** CamoPass migrates your store by copying already-encrypted `.gpg` files directly into their new obfuscated locations. **No passwords are decrypted in RAM or disk during obfuscation**, and you do not need to enter your GPG passphrase to migrate.
* **Stable Deterministic Hashing:** Uses salted SHA256 hashing to generate obfuscated names, ensuring your file mappings remain perfectly stable and consistent even as you add new entries.
* **Silent Clipboard Integration:** The `clip` command decrypts the entry and streams it directly to your system's Wayland clipboard (`wl-copy`) with **zero terminal output**. It forks a silent background process to automatically clear your clipboard after exactly 45 seconds.

---

## Dependencies & Compilation

CamoPass compiles into a completely standalone static binary (requiring zero external runtime libraries) by embedding the Luam engine.

### Dependencies:
1. **Luam Toolchain:** The `luam` compiler and core static runtime must be compiled in your system. By default, the build script expects your local `luam` repository to be located at `~/Projects/luam` (overrideable via `LUAM_DIR`).
2. **Standard Build Tools:** `gcc` and standard Unix compilation utilities.

### Building from Source:
You can build the static binary easily using the build script at the `bld/` directory:
```bash
# Build using default ~/Projects/luam path
bash bld/build.sh

# Or specify a custom Luam source path
LUAM_DIR=/path/to/luam bash bld/build.sh
```

This compiles a single standalone native binary at `bin/camopass`.

---

## Installation

To build and install CamoPass system-wide on your Linux environment:

```bash
git clone https://github.com/BenSiv/camopass.git
cd camopass
make
sudo make install
```

This will copy the statically compiled standalone binary `bin/camopass` directly to `/usr/local/bin/camopass`.

To uninstall:
```bash
sudo make uninstall
```

---

## Command Line Usage

### 1. Hide an Existing Password Store
To convert a standard readable `pass` repository into a secure, obfuscated repository:
```bash
camopass hide <source_store> <target_store> <gpg_recipient_id>
```
*Example:*
```bash
camopass hide /path/to/source-store /path/to/target-store my-gpg-key-id
```

This will create `/path/to/target-store` populated with:
* `index.gpg` - The securely encrypted lookup index.
* `0a1b2c3d4e.gpg`, `f1e2d3c4b5.gpg`, ... - Your fully encrypted GPG credentials under generic names.
* `.gpg-id` - Your GPG key recipient config.

### 2. List All Credentials
To view all your human-readable credential paths (requires GPG decryption of the index once):
```bash
camopass list /path/to/target-store
```

### 3. Print a Password
To print the decrypted password details to stdout:
```bash
camopass show /path/to/target-store google/username
```

### 4. Copy to Clipboard Silently
To silently copy the password to your Wayland clipboard (clears automatically in 45 seconds):
```bash
camopass clip /path/to/target-store google/username
```

---

## Restoring the Exact pass Muscle Memory

To make your day-to-day workflow incredibly fast, add this lightweight shell function helper to your `~/.bashrc` (or `~/.zshrc`):

```bash
kp() {
    local db="/path/to/target-store"
    if [ "$1" = "-c" ]; then
        camopass clip "$db" "$2"
    else
        camopass show "$db" "$1"
    fi
}
```

### The result:
* **`kp -c google/username`** -> Copies the password to your clipboard securely (completely silent, auto-clears in 45s).
* **`kp google/username`** -> Decrypts and prints the credentials directly.

---

## License

This project is open-source software, released under the **MIT License**.
