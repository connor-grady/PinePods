{ self, ... }:
{
  perSystem =
    { lib, pkgs, ... }:
    let
      toolchain = pkgs.rust-bin.fromRustupToolchainFile "${self}/rust-toolchain.toml";
      rustPlatform = pkgs.makeRustPlatform {
        cargo = toolchain;
        rustc = toolchain;
      };
      migrations = lib.fileset.toSource {
        root = ../..;
        fileset = lib.fileset.unions [
          ../../database_functions
          ../../startup/setup_database_new.py
        ];
      };
    in
    {
      packages = {
        pinepods-api = rustPlatform.buildRustPackage {
          pname = "pinepods-api";
          inherit ((lib.importTOML ../../rust-api/Cargo.toml).package) version;
          src = ../../rust-api;
          cargoLock.lockFile = ../../rust-api/Cargo.lock;
          nativeBuildInputs = [ pkgs.pkg-config ];
          buildInputs = [ pkgs.openssl ];
          cargoTestFlags = [
            "--lib"
            "--bins"
          ];
          meta.mainProgram = "pinepods-api";
        };

        pinepods-db-setup = pkgs.writeShellApplication {
          name = "pinepods-db-setup";
          runtimeInputs = [
            (pkgs.python3.withPackages (
              ps: with ps; [
                argon2-cffi
                cryptography
                psycopg
              ]
            ))
          ];
          text = ''
            exec python3 ${migrations}/startup/setup_database_new.py "$@"
          '';
        };
      };
    };
}
