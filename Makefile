# Define variables
CARGO_CMD = cargo build --manifest-path=compat/Cargo.toml --release
RACKET_CMD = raco make main.rkt
COPY_LIB_CMD = racket copy-lib.rkt

.PHONY: all compat copy-lib main clean

# Default target
all: compat copy-lib main

# Build Rust library
compat:
	$(CARGO_CMD)

# Run Racket script to copy the shared object
copy-lib:
	$(COPY_LIB_CMD)

# Build the Racket collection
main:
	$(RACKET_CMD)

# Clean Rust and Racket builds
clean:
	cargo clean --manifest-path=compat/Cargo.toml
	rm -rf compat/target
	find . -type f -name "*.zo" -delete
	find . -type f -name "*.dep" -delete

# Clean only Rust build
clean-rust:
	cargo clean --manifest-path=compat/Cargo.toml
	rm -rf compat/target

# Clean only Racket build
clean-racket:
	find . -type f -name "*.zo" -delete
	find . -type f -name "*.dep" -delete
