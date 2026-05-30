{
  description = "rkt-polars - Racket bindings to polars built with Nix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      version = "0.0.1";
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          rust = pkgs.rustPlatform.buildRustPackage {
            pname = "rkt-polars-compat";
            inherit version;
            src = pkgs.lib.cleanSource ./rust;
            cargoLock.lockFile = ./rust/Cargo.lock;

            doCheck = true;

            installPhase =
              let ext = pkgs.stdenv.hostPlatform.extensions.sharedLibrary;
              in ''
                runHook preInstall
                mkdir -p $out/lib
                find target -name "libcompat${ext}" -exec cp {} $out/lib/ \;
                runHook postInstall
              '';
          };

          # gregor-lib and its non-distribution dependency closure, captured
          # as unpacked package source trees via a fixed-output derivation
          # (network is permitted here).  The sandboxed `racket` build below
          # installs these offline, so it never has to reach the package
          # catalog -- which is what made `nix flake check` fail on Linux,
          # whose build sandbox has no network.
          #
          # The sources are unpacked into directories rather than kept as
          # `raco pkg archive` zips on purpose: those zips embed each source
          # file's checkout mtime, so their bytes differ per build machine and
          # a fixed output hash never matches.  Nix's NAR hashing normalises
          # mtimes, so an unpacked tree hashes purely by content and is
          # identical on every platform.
          #
          # Bump `outputHash` when the gregor/cldr/tzinfo/memoize versions in
          # the Racket release catalog change; `nix build` prints the new hash
          # on mismatch.
          racket-deps = pkgs.stdenvNoCC.mkDerivation {
            name = "rkt-polars-racket-deps";
            dontUnpack = true;

            nativeBuildInputs = [ pkgs.racket pkgs.cacert pkgs.git pkgs.unzip ];

            buildPhase = ''
              runHook preBuild

              export HOME=$TMPDIR/home
              export PLTUSERHOME=$TMPDIR/plt
              export SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
              export GIT_SSL_CAINFO=$SSL_CERT_FILE
              mkdir -p "$PLTUSERHOME"

              # Resolve and download gregor-lib + its closure (network).  The
              # closure is whatever this Racket distribution does not already
              # provide, so enumerate it dynamically (below) rather than
              # hard-coding a list that drifts between distributions.
              #
              # tzdata is requested explicitly: tzinfo only depends on it on
              # Windows, falling back to the system /usr/share/zoneinfo
              # elsewhere -- but the Nix build sandbox has no system zoneinfo,
              # so we must ship the tzdata package's copy.
              raco pkg install --batch --auto --no-setup --scope user gregor-lib tzdata

              mapfile -t deps < <(racket -e \
                '(require pkg/lib)(for ([p (installed-pkg-names #:scope (quote user))]) (displayln p))')

              # Repack the closure, then unpack each into a per-package source
              # directory (content-addressed, mtime-free).
              raco pkg archive "$TMPDIR/archive" "''${deps[@]}"

              mkdir -p "$out"
              for z in "$TMPDIR"/archive/pkgs/*.zip; do
                name="$(basename "$z" .zip)"
                mkdir -p "$out/$name"
                unzip -q "$z" -d "$out/$name"
              done

              runHook postBuild
            '';

            dontInstall = true;

            outputHashMode = "recursive";
            outputHashAlgo = "sha256";
            outputHash = "sha256-atA4hZLWNvH3Kyrq7dyyC/EKqh0O5p13+vzXKIn9UB4=";
          };

          racket = pkgs.stdenv.mkDerivation {
            pname = "rkt-polars";
            inherit version;
            src = pkgs.lib.cleanSource ./.;

            nativeBuildInputs = [ pkgs.racket ];
            buildInputs = [ rust ];

            buildPhase = ''
              runHook preBuild

              export HOME=$TMPDIR/home
              export PLTUSERHOME=$TMPDIR/racket-home
              export RKT_POLARS_COMPAT_LIB_PATH=${rust}
              mkdir -p $PLTUSERHOME

              # Install gregor-lib's dependency closure offline from the
              # prefetched source trees so this sandboxed build needs no
              # network.  --copy moves them out of the read-only store so they
              # can be compiled.
              raco pkg install --batch --copy --no-docs --scope user ${racket-deps}/*/

              mkdir -p ./polars/native-libs
              cp ${rust}/lib/libcompat.* ./polars/native-libs/

              raco pkg install --batch --no-setup --copy --scope user \
                --name rkt-polars "$PWD"

              raco setup --check-pkg-deps --unused-pkg-deps --pkgs rkt-polars

              runHook postBuild
            '';

            doCheck = true;
            checkPhase = ''
              runHook preCheck
              export RKT_POLARS_COMPAT_LIB_PATH=${rust}
              raco test -x -c polars
              runHook postCheck
            '';

            installPhase = ''
              runHook preInstall
              mkdir -p $out/share
              cp -r $PLTUSERHOME $out/share/racket-home
              runHook postInstall
            '';
          };

          copy-native-libs = pkgs.writeShellApplication {
            name = "copy-native-libs";
            meta.description = "Copy the Nix-built libcompat shared library into polars/native-libs";
            text = ''
              DEST="$(pwd)/polars/native-libs"
              mkdir -p "$DEST"
              cp -v ${rust}/lib/libcompat.* "$DEST/"
              echo "Native libraries copied to $DEST"
              ls -la "$DEST"
            '';
          };

          # polyfill-glibc rewrites ELF binaries built against a newer glibc so
          # they resolve only symbols available on a chosen older target.  Used
          # by scripts/build-so.sh to lower the committed linux libcompat.so
          # floor to glibc 2.17, so it loads on pkg-build.racket-lang.org's
          # old-glibc test host.  Not in nixpkgs; pinned to a known-good commit.
          polyfill-glibc = pkgs.stdenv.mkDerivation {
            pname = "polyfill-glibc";
            version = "unstable-2025-dd59051";
            src = pkgs.fetchFromGitHub {
              owner = "corsix";
              repo = "polyfill-glibc";
              rev = "dd59051faaa10ee63c1b96f1b47bf9fcd3770ee2";
              hash = "sha256-Qkzy33dIGnv9BOmRwql+LpYaEukZZIADSux09Fz3h7E=";
            };
            nativeBuildInputs = [ pkgs.ninja ];
            dontConfigure = true;
            buildPhase = ''
              runHook preBuild
              ninja polyfill-glibc
              runHook postBuild
            '';
            installPhase = ''
              runHook preInstall
              install -Dm755 polyfill-glibc $out/bin/polyfill-glibc
              runHook postInstall
            '';
            meta = {
              description = "Patch ELF binaries to require an older glibc version";
              homepage = "https://github.com/corsix/polyfill-glibc";
              license = pkgs.lib.licenses.mit;
              platforms = [ "x86_64-linux" "aarch64-linux" ];
            };
          };
        in
        {
          default = racket;
          inherit rust racket racket-deps copy-native-libs;
        }
        # polyfill-glibc only builds/runs on Linux; expose it only there.
        // pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
          inherit polyfill-glibc;
        });

      apps = forAllSystems (system: {
        copy-native-libs = {
          type = "app";
          program = "${self.packages.${system}.copy-native-libs}/bin/copy-native-libs";
          meta.description = "Copy the Nix-built libcompat shared library into polars/native-libs";
        };
      });

      checks = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          rustfmt = pkgs.stdenvNoCC.mkDerivation {
            pname = "rkt-polars-rustfmt";
            inherit version;
            src = pkgs.lib.cleanSource ./.;

            nativeBuildInputs = [
              pkgs.cargo
              pkgs.rustfmt
            ];

            doCheck = true;
            dontConfigure = true;
            dontBuild = true;

            checkPhase = ''
              runHook preCheck
              cargo fmt --manifest-path rust/Cargo.toml --all --check
              runHook postCheck
            '';

            installPhase = ''
              runHook preInstall
              touch $out
              runHook postInstall
            '';
          };
        in
        {
          inherit rustfmt;
          inherit (self.packages.${system}) rust racket;
        });

      devShells = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          rust = self.packages.${system}.rust;
        in
        {
          default = pkgs.mkShell {
            buildInputs = [
              pkgs.racket
              pkgs.rustc
              pkgs.cargo
              pkgs.stdenv.cc
            ];

            shellHook = ''
              export RKT_POLARS_COMPAT_LIB_PATH="${rust}"

              # PLTUSERHOME must live outside $PWD: raco pkg install --link
              # rejects a link target that overlaps with a collects dir, and
              # PLTUSERHOME contains a collects dir.  Key the location on a
              # hash of the project path so multiple checkouts don't collide.
              cache_root="''${XDG_CACHE_HOME:-$HOME/.cache}/rkt-polars-devshell"
              project_id=$(printf '%s' "$PWD" | ${pkgs.coreutils}/bin/sha256sum | cut -c1-12)
              export PLTUSERHOME="$cache_root/$project_id"
              mkdir -p "$PLTUSERHOME"

              mkdir -p "$PWD/polars/native-libs"
              cp -f ${rust}/lib/libcompat.* "$PWD/polars/native-libs/"

              # Stamp is keyed on info.rkt so dep changes auto-invalidate it.
              info_hash=$(${pkgs.coreutils}/bin/sha256sum info.rkt | cut -c1-16)
              deps_stamp="$PLTUSERHOME/.setup-installed-$info_hash"
              if [ ! -f "$deps_stamp" ]; then
                echo "Setting up rkt-polars in $PLTUSERHOME (deps changed or first run)"
                rm -f "$PLTUSERHOME"/.setup-installed-* 2>/dev/null || true
                if raco pkg install --batch --auto --no-setup --link --scope user --skip-installed \
                     --name rkt-polars "$PWD" \
                  && raco setup --check-pkg-deps --unused-pkg-deps --pkgs rkt-polars; then
                  touch "$deps_stamp"
                  echo "Done. Run 'raco test -x -c polars' to test."
                else
                  echo "rkt-polars setup FAILED — stamp not written; will retry next shell entry." >&2
                fi
              fi
            '';
          };
        });
    };
}
