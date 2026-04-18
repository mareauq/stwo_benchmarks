[package]
name = "{{PROGRAM_ID}}"
version = "0.1.0"
edition = "2024_07"

[executable]

[cairo]
enable-gas = false

[dependencies]
cairo_execute = "{{CAIRO_EXECUTE_VERSION}}"
