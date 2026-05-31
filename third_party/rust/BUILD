# Copyright lowRISC contributors (OpenTitan project).
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

load("@bazel_skylib//rules:common_settings.bzl", "string_flag")
load("@rules_rust_bindgen//:defs.bzl", "rust_bindgen_toolchain")
load("@rules_cc//cc:defs.bzl", "cc_import")

package(default_visibility = ["//visibility:public"])

config_setting(
    name = "specify_bindgen_libstdcxx",
    values = {"define": "SPECIFY_BINDGEN_LIBSTDCXX=true"},
)

string_flag(
    name = "openssl_pkg_config_path",
    build_setting_default = "",
    make_variable = "OPENSSL_PKG_CONFIG_PATH",
)

# Since rules_rust 0.23.0, bindgen depends on the llvm project and builds the
# llvm libaries from source. Building llvm from source has a huge impact on
# build times. Instead, we depend on a pre-built llvm release and instantiate
# the bindgen toolchain with the prebuilt binaries.
#
# libclang itself comes from Nix rather than the prebuilt clang+llvm-10 release:
# that release is linked against libtinfo.so.5 / GNU libstdc++.so.6, which
# modern hosts (e.g. Ubuntu 24.04) do not ship, and the bindgen action's sealed
# loader only resolves /nix/store. The Nix libclang is self-contained. See
# //third_party/nix:libclang.bzl (it reads NIX_LIBCLANG_LIB from the dev shell).
cc_import(
    name = "libclang",
    shared_library = "@nix_libclang//:libclang.so",
)

cc_import(
    name = "libcxx",
    shared_library = "@llvm_toolchain_llvm//:lib/libc++.so",
)

rust_bindgen_toolchain(
    name = "bindgen_toolchain_impl",
    bindgen = "@rules_rust_bindgen//3rdparty:bindgen",
    clang = "@llvm_toolchain_llvm//:bin/clang",
    libclang = ":libclang",
    libstdcxx = ":libcxx",
)

toolchain(
    name = "bindgen_toolchain",
    toolchain = "bindgen_toolchain_impl",
    toolchain_type = "@rules_rust_bindgen//:toolchain_type",
)
