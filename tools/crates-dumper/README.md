### ℹ️ About
Process [`crates.io`](https://rust-lang.github.io/rfcs/3463-crates-io-policy-update.html#data-access) database dumps into JSON .<br>

### 🧰 Usage
```mathematica

❯ crates-dumper --help

Process crates.io database dumps into JSON

Usage: crates-dumper [OPTIONS]

Commands:
  download  Download and process the latest database dump
  process   Process an existing local database dump file
  help      Print this message or the help of the given subcommand(s)

Options:
  -j, --threads <THREADS>  Number of threads to use for parallel processing [default: 20]
  -v, --verbose            Verbose output
  -q, --quiet              Quiet output (suppress progress bars and info messages)
  -h, --help               Print help
  -V, --version            Print version

```

### 🛠️ Building
```bash
#! WARNING: gnu causes core dumps due to malloc
RUST_TARGET="$(uname -m)-unknown-linux-musl"
RUSTFLAGS="-C target-feature=+crt-static \
           -C link-self-contained=yes \
           -C default-linker-libraries=yes \
           -C prefer-dynamic=no \
           -C lto=yes \
           -C debuginfo=none \
           -C strip=symbols \
           -C link-arg=-Wl,--build-id=none \
           -C link-arg=-Wl,--discard-all \
           -C link-arg=-Wl,--strip-all"
           
export RUST_TARGET RUSTFLAGS
rustup target add "${RUST_TARGET}"

cargo build --target "${RUST_TARGET}" \
     --all-features \
     --jobs="$(($(nproc)+1))" \
     --release

"./target/${RUST_TARGET}/release/crates-dumper" --help
```