{ self, ... }: {
  perSystem = { pkgs, ... }: {
    devShells.rust = pkgs.mkShell {
      name = "pinepods-rust";
      packages = with pkgs; [
        (rust-bin.fromRustupToolchainFile "${self}/rust-toolchain.toml")
        binaryen
        pkg-config
        trunk
      ];
      buildInputs = with pkgs; [ openssl ];
    };
  };
}
