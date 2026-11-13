# CamoPass

**CamoPass** is an open-source, stealthy, metadata-private password store enhancer for standard `pass`. It is written natively in **Luam** (a strict, safe, modern fork of Lua 5.1).

It resolves the primary privacy risk of standard `pass` stores: **plaintext metadata exposure**. 

While `pass` encrypts your password contents, it leaves your folder structures, account names, and file paths fully visible in plaintext. If you push your store to a private GitHub repository for backups or mobile sync, any observer can enumerate every single financial, email, or personal service you use.

CamoPass solves this by **obfuscating your entire password store filesystem** into generic, non-descriptive paths while maintaining a securely encrypted central lookup index (`index.gpg`).

---

## Key Features

* **Absolute Metadata Privacy (Local & Remote):** Directory hierarchies, filenames, and change-history are replaced by completely opaque hash-based identifiers (e.g. `0a1b2c3d4e.gpg`) both locally and on Git remotes. Neither your local disk nor GitHub sees any service names or account identities.
* **Stateless Direct Mutations (Zero `plain_store` Required):** `insert`, `generate`, `edit`, and `remove` operate directly on the obfuscated CamoPass store via private `0600` `/dev/shm` RAM buffers that are immediately wiped with `shred`. No `pass` CLI or shadow plaintext-tree vault is needed on disk.
* **Perfect Security & Zero Decryption during Migration:** CamoPass migrates an existing `pass` store by copying already-encrypted `.gpg` files directly into their new obfuscated locations. **No passwords are decrypted in RAM or disk during migration**, and you do not need to enter your GPG passphrase to migrate.
* **Stable Deterministic Hashing:** Uses salted SHA256 hashing to generate obfuscated names, ensuring your file mappings remain perfectly stable and consistent across updates and Git commits.
* **Silent Clipboard Integration:** The `clip` command decrypts the entry and streams it directly to your system's Wayland/X11 clipboard (`wl-copy` or `xclip`) with **zero terminal output**, automatically clearing the clipboard after 45 seconds.

---

## Dependencies & Compilation

CamoPass compiles into a completely standalone static binary (requiring zero external runtime libraries) by embedding the Luam engine.

### Dependencies:
1. **Luam Toolchain:** The `luam` compiler and core static runtime must be compiled in your system. By default, the build script expects your local `luam` repository to be located at `~/Projects/luam` (overrideable via `LUAM_DIR`).
2. **Standard Build Tools:** `gcc` and standard Unix compilation utilities.

### Building from Source:
You can build the static binary easily using the build script at the `bld/` directory:
```bash
# Build using a sibling ../luam checkout (already built)
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

### 1. Initialize or Point to an Obfuscated Store
Initialize a brand-new obfuscated store (or point `~/.config/camopass/settings.json` to an existing one):
```bash
camopass init <store_path> [<gpg_recipient_id>]
```

### 2. Add, Generate, Edit, or Remove Credentials Directly
Operate directly on the obfuscated store without maintaining any un-obfuscated `plain_store` on disk:
```bash
# Insert a single-line or multiline (-m) credential
camopass insert github/personal
camopass insert -m work/aws

# Generate a cryptographically random password (default 25 chars; -n for alphanumeric)
camopass generate finance/bank 32
camopass generate -n wifi/home 24

# Edit an entry inside a private shredded /dev/shm RAM buffer via $EDITOR
camopass edit github/personal

# Shred and remove an entry from the obfuscated store and index.gpg
camopass remove wifi/home
```
If `<store_path>` is a Git repository, mutations automatically commit (and push if a remote is configured).

### 3. Migrate an Existing `pass` Store (`hide` / `unhide`)
To convert a standard readable `pass` repository into an obfuscated CamoPass repository:
```bash
camopass hide <source_store> <target_store> <gpg_recipient_id>
```
This populates `<target_store>` with:
* `index.gpg` - The encrypted lookup index.
* `0a1b2c3d4e.gpg`, `f1e2d3c4b5.gpg`, ... - Encrypted GPG credentials under opaque 10-hex-character names.
* `.gpg-id` - Your GPG recipient ID.

To reconstruct a standard `pass` directory tree if ever needed:
```bash
camopass unhide <obfuscated_store> <plain_store>
```

### 4. List, Show, and Copy Credentials
```bash
camopass list [<store_path>]
camopass show [<store_path>] google/username
camopass clip [<store_path>] google/username
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
