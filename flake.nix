{
  description = "libflux development environment";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in {
      devShells.${system}.default = pkgs.mkShell.override {
        # Keep system linkage behavior from the copied ROC shell.
        stdenv = pkgs.stdenvAdapters.keepSystem pkgs.stdenv;
      } {
        packages = with pkgs; [
          cmake
          clang
          clang-tools
          zig
        ];
      };
    };
}
