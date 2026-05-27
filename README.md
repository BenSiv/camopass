# CamoPass

**CamoPass** is an open-source, stealthy, metadata-private password store enhancer for standard `pass`. It is written natively in **Luam** (a strict, safe, modern fork of Lua 5.1).

It resolves the primary privacy risk of standard `pass` stores: **plaintext metadata exposure**. 

While `pass` encrypts your password contents, it leaves your folder structures, account names, and file paths fully visible in plaintext. If you push your store to a private GitHub repository for backups or mobile sync, any observer can enumerate every single financial, email, or personal service you use.

CamoPass solves this by **obfuscating your entire password store filesystem** into generic, non-descriptive paths while maintaining a securely encrypted central lookup index (`index.gpg`).

---

## Key Features

* **Absolute Metadata Privacy:** Directory hierarchies, filenames, and change-history are replaced by completely opaque sequential IDs (e.g. `e1.gpg`, `e2.gpg`). GitHub sees absolutely zero service names or account identities.
* **Perfect Security & Zero Decryption during Migration:** CamoPass migrates your store by copying already-encrypted `.gpg` files directly into their new obfuscated locations. **No passwords are decrypted in RAM or disk during obfuscation**, and you do not need to enter your GPG passphrase to migrate.
* **Deterministic Sorted Mappings:** Scans are automatically sorted alphabetically, ensuring your sequential IDs remain perfectly stable and consistent.
* **Silent Clipboard Integration:** The `clip` command decrypts the entry and streams it directly to your system's Wayland clipboard (`wl-copy`) with **zero terminal output**. It forks a silent background process to automatically clear your clipboard after exactly 45 seconds.
* **Written in Luam:** Complies strictly with your safe language fork constraints (implicit locals, no `local` keyword, inequality via `!=`, and pure `while` iterative structures).

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

### 1. Obfuscate an Existing Password Store
To convert a standard readable `pass` repository into a secure, obfuscated repository:
```bash
camopass obfuscate <source_store> <target_store> <gpg_recipient_id>
```
*Example:*
```bash
camopass obfuscate ~/.password-store ~/Projects/passwords A748A133F7C13732
```

This will create `~/Projects/passwords` populated with:
* `index.gpg` - The securely encrypted lookup index.
* `e1.gpg`, `e2.gpg`, ... - Your fully encrypted GPG credentials under generic names.
* `.gpg-id` - Your GPG key recipient config.

### 2. List All Credentials
To view all your human-readable credential paths (requires GPG decryption of the index once):
```bash
camopass list ~/Projects/passwords
```

### 3. Print a Password
To print the decrypted password details to stdout:
```bash
camopass show ~/Projects/passwords google/bensiv92
```

### 4. Copy to Clipboard Silently
To silently copy the password to your Wayland clipboard (clears automatically in 45 seconds):
```bash
camopass clip ~/Projects/passwords google/bensiv92
```

---

## Restoring the Exact pass Muscle Memory

To make your day-to-day workflow incredibly fast, add this lightweight shell function helper to your `~/.bashrc` (or `~/.zshrc`):

```bash
kp() {
    local db="$HOME/Projects/passwords"
    if [ "$1" = "-c" ]; then
        camopass clip "$db" "$2"
    else
        camopass show "$db" "$1"
    fi
}
```

### The result:
* **`kp -c google/bensiv92`** -> Copies the password to your clipboard securely (completely silent, auto-clears in 45s).
* **`kp google/bensiv92`** -> Decrypts and prints the credentials directly.

---

## License

This project is open-source software, released under the **MIT License**.
