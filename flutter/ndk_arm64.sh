#!/usr/bin/env bash
# Utzil Remote: el job de Android no pasa por build.py; la marca se pone aquí.
python3 "$(dirname "$0")/../utzil/marca.py" || exit 1
cargo ndk --platform 21 --target aarch64-linux-android build --locked --release --features flutter,hwcodec
