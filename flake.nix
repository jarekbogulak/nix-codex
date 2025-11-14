{
  description = "A Nix flake for the Codex CLI.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    # Track the Codex source as a non-flake input so updates are just
    # changes to the lockfile (no manual sha256 handling).
    codex-src = {
      # Pin to Rust CLI release 0.58.0
      url = "github:openai/codex?ref=rust-v0.58.0";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, codex-src }:
    let
      # System architectures to build for.
      supportedSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];

      # Helper function to generate packages for each system.
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

      # Function to get the Nixpkgs package set for a given system.
      pkgsFor = system: nixpkgs.legacyPackages.${system};

      # Define the package derivation as a function of `pkgs` to avoid repetition.
      mkCodexCli = pkgs: pkgs.stdenv.mkDerivation rec {
        pname = "codex-cli";
        version = "0.58.0";

        # Use the flake input for source; pinned via flake.lock
        src = codex-src;

        nativeBuildInputs = [
          pkgs.makeWrapper
          pkgs.cacert
          pkgs.rustc
          pkgs.cargo
        ];

        buildInputs = [ pkgs.nodejs ];

        buildPhase = ''
          runHook preBuild
          export HOME=$(mktemp -d)
          # Install production deps for the CLI package
          (cd codex-cli && npm ci --omit=dev || npm install --omit=dev)
          # Build the native Rust CLI
          (cd codex-rs && cargo build -p codex-cli --release --locked || cargo build -p codex-cli --release)
          runHook postBuild
        '';

        installPhase = ''
          runHook preInstall
          mkdir -p $out/lib/codex-cli
          # Copy the whole package including node_modules
          cp -r codex-cli/* $out/lib/codex-cli/
          # Ensure the entrypoint exists and is executable
          chmod +x $out/lib/codex-cli/bin/codex.js || true
          # Install the native binary in both the bin/ convenience location and the vendor/ layout used by the JS wrapper
          triple=${pkgs.stdenv.hostPlatform.config}
          nativeBinary="codex-rs/target/release/codex"
          install -D -m 755 "$nativeBinary" "$out/lib/codex-cli/bin/codex-$triple"
          install -D -m 755 "$nativeBinary" "$out/lib/codex-cli/vendor/$triple/codex/codex"
          # Add compatibility symlinks for triples expected by the JS wrapper
          (
            cd "$out/lib/codex-cli/bin"
            # Darwin: Node wrapper expects aarch64, Nix may report arm64
            if [ -e codex-arm64-apple-darwin ] && [ ! -e codex-aarch64-apple-darwin ]; then
              ln -s codex-arm64-apple-darwin codex-aarch64-apple-darwin
            fi
            # Linux: Node wrapper expects musl triples; provide symlinks from gnu
            if [ -e codex-x86_64-unknown-linux-gnu ] && [ ! -e codex-x86_64-unknown-linux-musl ]; then
              ln -s codex-x86_64-unknown-linux-gnu codex-x86_64-unknown-linux-musl
            fi
            if [ -e codex-aarch64-unknown-linux-gnu ] && [ ! -e codex-aarch64-unknown-linux-musl ]; then
              ln -s codex-aarch64-unknown-linux-gnu codex-aarch64-unknown-linux-musl
            fi
          )
          if [ -d "$out/lib/codex-cli/vendor" ]; then
            (
              cd "$out/lib/codex-cli/vendor"
              # Mirror the bin/ compatibility symlinks so the Node wrapper finds the native binary
              if [ -d arm64-apple-darwin ] && [ ! -e aarch64-apple-darwin ]; then
                ln -s arm64-apple-darwin aarch64-apple-darwin
              fi
              if [ -d x86_64-unknown-linux-gnu ] && [ ! -e x86_64-unknown-linux-musl ]; then
                ln -s x86_64-unknown-linux-gnu x86_64-unknown-linux-musl
              fi
              if [ -d aarch64-unknown-linux-gnu ] && [ ! -e aarch64-unknown-linux-musl ]; then
                ln -s aarch64-unknown-linux-gnu aarch64-unknown-linux-musl
              fi
            )
          fi
          # Create a wrapper for the CLI
          makeWrapper ${pkgs.nodejs}/bin/node $out/bin/codex \
            --add-flags "$out/lib/codex-cli/bin/codex.js"
          runHook postInstall
        '';
      };
    in
    {
      # `packages` maps each supported system to its set of packages.
      packages = forAllSystems (system: {
        codex-cli = mkCodexCli (pkgsFor system);
      });

      # `defaultPackage` maps each system to its default package for `nix build .`
      defaultPackage = forAllSystems (system: self.packages.${system}.codex-cli);

      # `devShells` maps each system to its set of shells for `nix develop .`
      devShells = forAllSystems (system: {
        default = (pkgsFor system).mkShell {
          # Pull in build dependencies like nodejs, makeWrapper, etc.
          inputsFrom = [ self.packages.${system}.codex-cli ];

          # Also add the final built package's executables to the PATH.
          packages = [ self.packages.${system}.codex-cli ];
        };
      });
    };
}
