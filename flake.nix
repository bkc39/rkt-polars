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

          racket = pkgs.stdenv.mkDerivation {
            pname = "rkt-polars";
            inherit version;
            src = pkgs.lib.cleanSource ./.;

            nativeBuildInputs = [ pkgs.racket ];
            buildInputs = [ rust ];

            buildPhase = ''
              runHook preBuild

              export PLTUSERHOME=$TMPDIR/racket-home
              export RKT_POLARS_COMPAT_LIB_PATH=${rust}
              mkdir -p $PLTUSERHOME

              mkdir -p ./polars/native-libs
              cp ${rust}/lib/libcompat.* ./polars/native-libs/

              raco pkg install --batch --deps fail --no-setup --copy --scope user \
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
        in
        {
          default = racket;
          inherit rust racket copy-native-libs;
        });

      apps = forAllSystems (system: {
        copy-native-libs = {
          type = "app";
          program = "${self.packages.${system}.copy-native-libs}/bin/copy-native-libs";
        };
      });

      checks = forAllSystems (system: {
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
              export PLTUSERHOME="$PWD/.racket-user"

              mkdir -p "$PWD/polars/native-libs"
              cp -f ${rust}/lib/libcompat.* "$PWD/polars/native-libs/"

              # Stamp is keyed on info.rkt so dep changes auto-invalidate it.
              info_hash=$(${pkgs.coreutils}/bin/sha256sum info.rkt | cut -c1-16)
              deps_stamp="$PLTUSERHOME/.setup-installed-$info_hash"
              if [ ! -f "$deps_stamp" ]; then
                echo "Setting up rkt-polars in $PLTUSERHOME (deps changed or first run)"
                mkdir -p "$PLTUSERHOME"
                rm -f "$PLTUSERHOME"/.setup-installed-* 2>/dev/null || true
                raco pkg install --batch --auto --no-setup --link --scope user --skip-installed \
                  --name rkt-polars "$PWD"
                raco setup --check-pkg-deps --unused-pkg-deps --pkgs rkt-polars
                touch "$deps_stamp"
                echo "Done. Run 'raco test -x -c polars' to test."
              fi
            '';
          };
        });
    };
}
