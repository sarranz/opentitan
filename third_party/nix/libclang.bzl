# Copyright lowRISC contributors (OpenTitan project).
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

"""Expose a Nix-provided libclang to Bazel for the rust-bindgen toolchain.

The prebuilt clang+llvm-10 release used elsewhere as `libclang`
(`@llvm_toolchain_llvm`) is linked against `libtinfo.so.5` and GNU
`libstdc++.so.6`, neither of which modern distros (e.g. Ubuntu 24.04) ship.
The `rules_rust_bindgen` action additionally runs with a sealed environment
whose loader only resolves paths under `/nix/store`, so `LD_LIBRARY_PATH`
forwarding cannot help it. A libclang built by Nix is self-contained -- its
`RUNPATH` resolves `libstdc++.so.6` (and friends) from `/nix/store` -- so we
point bindgen at it instead.

The Nix dev shell (see `//:flake.nix`) exports `NIX_LIBCLANG_LIB`, the `lib`
directory of `llvmPackages.libclang.lib`. This repository rule symlinks the
libclang shared object out of it and exposes it as
`@nix_libclang//:libclang.so`.
"""

_NO_PATH_MSG = """
NIX_LIBCLANG_LIB is not set. The rust-bindgen toolchain needs a libclang that
is loadable on this host. Run Bazel from inside the Nix dev shell:

    nix develop

which exports NIX_LIBCLANG_LIB (see flake.nix).
"""

def _nix_libclang_impl(rctx):
    lib_dir = rctx.os.environ.get("NIX_LIBCLANG_LIB")
    if not lib_dir:
        fail(_NO_PATH_MSG)
    libclang = rctx.path(lib_dir).get_child("libclang.so")
    if not libclang.exists:
        fail("NIX_LIBCLANG_LIB ({}) does not contain libclang.so".format(lib_dir))
    rctx.symlink(libclang, "libclang.so")
    rctx.file(
        "BUILD.bazel",
        'exports_files(["libclang.so"], visibility = ["//visibility:public"])\n',
    )

_nix_libclang_repo = repository_rule(
    implementation = _nix_libclang_impl,
    environ = ["NIX_LIBCLANG_LIB"],
    # Resolved from the environment, so re-evaluate rather than cache across
    # dev-shell changes.
    local = True,
    doc = "Symlinks a Nix-provided libclang.so into an external repository.",
)

def _nix_libclang_ext_impl(_module_ctx):
    _nix_libclang_repo(name = "nix_libclang")

nix_libclang = module_extension(
    implementation = _nix_libclang_ext_impl,
    doc = "Creates @nix_libclang, exposing a Nix-provided libclang.so.",
)
