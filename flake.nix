{
  description = "OpenTitan";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
  };


  outputs = { self, nixpkgs }: {
    defaultPackage.x86_64-linux =
      with import nixpkgs { system = "x86_64-linux"; };
      stdenv.mkDerivation {
        name = "opentitan";
        src = self;
        # pkg-config must be a *native* build input so its setup hook runs and
        # populates PKG_CONFIG_PATH from buildInputs (udev, libcap, ...). In
        # buildInputs the hook never fires and PKG_CONFIG_PATH stays empty.
        nativeBuildInputs =
          [
            pkgconf
          ];
        buildInputs =
          [
            # build-essential / make / g++ are provided by stdenv (gcc, gnumake, ...)
            autoconf
            brotli
            cmake
            curl
            dfu-util
            file
            gcc
            git
            lcov
            libelf
            libftdi1
            ncurses5      # libncursesw5
            pcsclite      # libpcsclite-dev
            openssl       # libssl-dev / openssl
            libtool
            udev          # libudev-dev
            libcap        # required by libudev.pc (Requires.private: libcap)
            libusb1       # libusb-1.0-0
            lrzsz
            lsb-release
            gnumake
            perl
            python311     # python-is-python3 (OpenTitan's lockfile targets 3.11)
            python311Packages.pip
            python311Packages.setuptools
            python311Packages.wheel
            srecord
            tree
            xmlstarlet
            libxslt       # xsltproc
            xxd
            xz            # xz-utils
            zip
            zlib
          ];
        # rust-bindgen (host tooling / API docs) dlopens libclang. The prebuilt
        # clang+llvm-10 release used by Bazel's @llvm_toolchain_llvm is linked
        # against libtinfo.so.5 and GNU libstdc++.so.6, which Ubuntu 24.04 no
        # longer ships, and the bindgen action runs with a sealed environment
        # whose loader only resolves /nix/store -- so LD_LIBRARY_PATH forwarding
        # cannot reach it. Instead we point bindgen at this self-contained Nix
        # libclang (its RUNPATH resolves its deps from /nix/store). The Bazel
        # repository rule in //third_party/nix:libclang.bzl reads this variable;
        # .bazelrc-site forwards it via --repo_env.
        shellHook = ''
          export NIX_LIBCLANG_LIB="${llvmPackages_18.libclang.lib}/lib"
        '';
        buildPhase = "";
        installPhase = "touch $out";
      };
  };
}
