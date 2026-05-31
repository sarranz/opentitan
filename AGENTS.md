# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

This is the [OpenTitan](https://opentitan.org) monorepo (hardware + software for an open source silicon Root of Trust). **This checkout is used only for OTBN and documentation work**, so this file focuses on those two areas. The rest of the repo (top-level chip RTL, DV/UVM, FPGA, the bulk of `sw/device`) is intentionally not covered here.

## Environment setup (required before any build)

This checkout builds inside a **Nix dev shell** plus a Python **venv** (a non-standard local setup, see `flake.nix`, `LOCAL.md`, `.bazelrc-site`):

```sh
nix develop          # enters dev shell; exports NIX_LIBCLANG_LIB + populates PKG_CONFIG_PATH
source .venv/bin/activate   # Python tools (regtool, mdbook preprocessors, otbnsim, etc.)
```

- `flake.nix` provides the system toolchain (gcc, python311, openssl, libusb, ...). Bazel build actions run with a sealed environment, so `.bazelrc-site` (gitignored) forwards `PKG_CONFIG_PATH`, `NIX_LIBCLANG_LIB`, and an `openssl_pkg_config_path` flag from the shell. **Run Bazel from inside `nix develop` or these will be empty and the rust-bindgen / openssl-sys build actions fail.** See `third_party/nix/libclang.bzl` for why a Nix-provided libclang is substituted for the prebuilt clang+llvm-10.
- If you bump the `nixpkgs` input, refresh the pinned openssl store path in `.bazelrc-site` with `pkg-config --variable=pcfiledir openssl`.
- Bazel is invoked via `./bazelisk.sh` (a `bazel` wrapper that pins the version); commands below assume `bazel` is aliased to it.

## OTBN overview

OTBN (OpenTitan Big Number accelerator, `hw/ip/otbn/`) is a security-focused coprocessor for asymmetric crypto (RSA, ECC) and PQC (ML-DSA, ML-KEM). It has a custom, non-RISC-V-compatible ISA in two subsets: **base** (32b GPRs `x0`-`x31`, control flow) and **bignum** (`BN.*` instructions over 32 256b Wide Data Registers `w0`-`w31`, plus WSRs, flag groups, `ACC`/`MOD`, hardware loops). It runs to completion: Ibex loads IMEM/DMEM, sets the execute bit, and reads results back from DMEM when done. Strict Harvard architecture — IMEM and DMEM both start at address 0.

Read `hw/ip/otbn/doc/otbn_intro.md` first, then `theory_of_operation.md`, `isa.md`, and `developers_guide.md`.

### The ISA has multiple sources of truth — keep them in sync

- **`hw/ip/otbn/data/insns.yml`** is the machine-readable ISA definition (parsed by `hw/ip/otbn/util/shared/insn_yaml.py`). The docs ISA tables and the binutils toolchain are generated from it.
- **`hw/ip/otbn/dv/otbnsim/sim/insn.py`** is the instruction *semantics* (the Python ISS implementation). When adding/changing an instruction, `insns.yml` (encoding/operands) and `insn.py` (behavior) must agree, and the RTL in `hw/ip/otbn/rtl/` must match both.
- **CSR/WSR lists are replicated in five places.** The `README.md` flags this: the lists in `otbn_env_cov.sv`, `csr.py`, `wsr.py`, the RTL, and `dv/rig/model.py` must all be edited together. The README's CSR/WSR tables themselves are CMDGEN-generated from `data/csr.yml` / `data/wsr.yml` (see Documentation below).

## OTBN software (`sw/otbn/`)

Hand-written OTBN assembly (`.s`). `crypto/` is production code (P-256/P-384 ECDSA, Ed25519, RSA modexp, `mldsa87/`, etc.); `code-snippets/` holds small examples (`mul256.s`, `mul384.s`, ...). Follow the [OTBN style guide](doc/contributing/style_guides/otbn_style_guide.md): lowercase mnemonics/registers, no ABI register names (there is no calling convention), uppercase for flags and multiplication half-word identifiers.

Built with Bazel rules in `rules/otbn.bzl`:
- `otbn_library` — assembles one `.s` into a `.o`. Best practice: one `otbn_library` per file so binaries pull in only what they need (IMEM is small).
- `otbn_binary` — links `.o`s into `.elf` and `.rv32embed.{a,o}` (the latter for linking into an Ibex C program via the target's `deps`).
- `otbn_sim_test` — wraps `otbn_binary` so `bazel test` runs it on the ISS and checks the result.

## OTBN toolchain (`hw/ip/otbn/util/`)

Wrappers around RISC-V binutils (install via `util/get-toolchain.py`):
- `otbn_as.py` — assembler (like `riscv32-unknown-elf-as` but passes `-mno-relax`).
- `otbn_ld.py` — linker; supplies the default OTBN linker script (`.start`+`.text` → IMEM, `.data` → DMEM). The entry point must be the sole content of `.text.start`.
- `otbn_objdump.py` — objdump; `-d` disassembles the custom OTBN instructions.

Analysis tools also live here: `check_const_time.py`, `analyze_information_flow.py`, `check_call_stack.py`, `check_loop.py`, `get_instruction_count_range.py`.

## Running and testing OTBN programs

**Python ISS (instruction set simulator)** — fastest way to run a standalone program:
```sh
hw/ip/otbn/dv/otbnsim/standalone.py path/to/prog.elf   # --dmem-dump, --verbose for trace
```
`hw/ip/otbn/dv/otbnsim/stepped.py` is the CLI-driven variant used by UVM tests. The ISS test suite (`hw/ip/otbn/dv/otbnsim/`):
```sh
make test                       # also generates the bignum SIMD tests
pytest -vv -k <testname>.s      # single test
```

**Standalone RTL (Verilator) sim** — cross-checks RTL against the ISS:
```sh
fusesoc --cores-root=. run --target=sim --setup --build \
  --mapping=lowrisc:prim_generic:all:0.1 lowrisc:ip:otbn_top_sim --make_options="-j$(nproc)"
./build/lowrisc_ip_otbn_top_sim_0.1/sim-verilator/Votbn_top_sim --load-elf=prog.elf
```
Pass `-t` for an FST wave trace, `--otbn-trace-file=trace.log` for an instruction trace.

**Smoke test:** `hw/ip/otbn/dv/smoke/run_smoke.sh` (add `vectorized` to exercise the SIMD bignum instructions).

`hw/ip/otbn/dv/rig/` is a random instruction generator (`otbn-rig`); `hw/ip/otbn/dv/uvm/` is the full UVM testbench.

## Documentation

Docs are Markdown rendered with **mdbook** (`book.toml`). Build/serve locally (needs Cargo + mdbook in addition to the Nix/venv setup):
```sh
./util/site/build-docs.sh serve   # serves at http://0.0.0.0:9000; also: build, build-local, build-staging
```

OpenTitan uses custom mdbook **preprocessors** (configured in `book.toml`, implemented as `util/mdbook_*.py`). The OTBN-relevant ones:
- `mdbook_otbn.py` resolves `{{#otbn-insn-ref INSN}}` cross-references and `{{#otbn-isa base|bignum}}` ISA tables, generated from `insns.yml` via `hw/ip/otbn/util/yaml_to_doc.py`. **Use `{{#otbn-insn-ref ...}}` to link to instructions** rather than hand-written links.
- `mdbook_reggen.py` / `mdbook_testplan.py` render register and testplan tables from `*.hjson`.

### CMDGEN blocks — do not hand-edit generated content

Many `.md` files (including `hw/ip/otbn/README.md`) contain blocks like:
```
<!-- BEGIN CMDGEN <command> -->
...generated content (committed to the repo)...
<!-- END CMDGEN -->
```
The content between the markers is produced by running `<command>` and is checked in. **Edit the generating source/command, not the text between the markers** — CI (`ci/scripts/check-cmdgen.sh`) fails if they are stale. Regenerate with:
```sh
./util/cmdgen.py -u '**/*.md'
```
For example, the OTBN CSR/WSR tables in `README.md` are generated from `data/csr.yml` / `data/wsr.yml` via `hw/ip/otbn/util/docs/md_isrs.py`.

## Code style

- Python tooling: yapf (pep8-based, see `.style.yapf`), flake8, ruff (line length 100, `pyproject.toml`), isort, mypy. Vendored files (`*vendor*`) are excluded from linting.
- Commit messages: prefix the subject with the area in brackets, e.g. `[otbn] Fix ...`. Use `git commit -s` to add the required CLA sign-off.
