
let
  # An overlay that adds termonad to all haskell package sets.
  haskellPackagesOverlay = self: super: {
    haskell = super.haskell // {
      packageOverrides = hself: hsuper:
        super.haskell.packageOverrides hself hsuper // {
          termonad =
            let
              filesToIgnore = [
                "default.nix"
                "flake.nix"
                "flake.lock"
                ".git"
                ".nix-helpers"
                "result"
                "shell.nix"
                ".stack-work"
                "stack.yaml"
                "stack-nightly.yaml"
                ".travis.yml"
              ];

              src =
                builtins.path {
                  # Naming this path makes sure that people will get the same
                  # hash even if they checkout the termonad repo into a
                  # directory called something else.
                  name = "termonad-src";
                  path = ./..;
                  filter = path: type:
                    with self.lib;
                    ! elem (baseNameOf path) filesToIgnore &&
                    ! any (flip hasPrefix (baseNameOf path)) [ "dist" ".ghc" ];
                };

              extraCabal2nixOptions =
                self.lib.optionalString self.termonadBuildExamples "-fbuildexamples";

              termonadDrv =
                hself.callCabal2nixWithOptions
                  "termonad"
                  src
                  extraCabal2nixOptions
                  {
                    # There are Haskell packages called gtk3 and pcre2, which
                    # makes these system dependencies not able to be resolved
                    # correctly.
                    inherit (self) gtk3 pcre2;
                    vte_291 = self.vte;
                  };
            in
            termonadDrv;
        };
    };

    # This defines which compiler version is used to build Termonad.
    #
    # Either this, or termonadKnownWorkingHaskellPkgSet can be changed in an overlay
    # if you want to use a different GHC to build Termonad.
    termonadCompilerVersion = "ghc902";

    # A Haskell package set where we know the GHC version works to compile
    # Termonad.  This is basically just a shortcut so that other Nix files
    # don't need to figure out the correct compiler version to use when it is
    # not given by the user.
    termonadKnownWorkingHaskellPkgSet = self.haskell.packages.${self.termonadCompilerVersion};

    # See ./nixpkgs.nix for an explanation of that this does.
    termonadBuildExamples = false;

    # See ./nixpkgs.nix for an explanation of that this does.
    termonadIndexTermonad = false;

    # This is a shell environment for hacking on Termonad with cabal.  See the
    # top-level shell.nix for an explanation.
    termonadShell =
      let
        # Nix-shell environment for hacking on termonad.
        termonadEnv = self.termonadKnownWorkingHaskellPkgSet.termonad.env;

        # Build tools that are nice to have.  It is okay to get Haskell build tools
        # from any Haskell package set, since they do not depend on the GHC version
        # we are using.  We get these from the normal haskellPackages pkg set because
        # then they don't have to be compiled from scratch.
        convenientNativeBuildTools = [
          self.cabal-install
          self.glade
          self.haskellPackages.ghcid
          self.hlint
        ];
      in

      if self.termonadIndexTermonad
        then
          termonadEnv.overrideAttrs (oldAttrs: {
            nativeBuildInputs =
              let
                ghcEnvWithTermonad =
                  self.termonadKnownWorkingHaskellPkgSet.ghcWithHoogle (hpkgs: [ hpkgs.termonad ]);
              in
              oldAttrs.nativeBuildInputs ++ convenientNativeBuildTools ++ [ ghcEnvWithTermonad ];
          })
        else
          self.termonadKnownWorkingHaskellPkgSet.shellFor {
            withHoogle = true;
            packages = hpkgs: [ hpkgs.termonad ];
            nativeBuildInputs = termonadEnv.nativeBuildInputs ++ convenientNativeBuildTools;
          };

    # Default Haskell packages that you can use in your Termonad configuration.
    # This is only used if the user doesn't specify the extraHaskellPackages
    # option.
    termonadExtraHaskellPackages = hpkgs: with hpkgs; [
      colour
      lens
    ];

    termonad-with-packages =
      let
        # GHC environment that has termonad available, as well as the packages
        # specified above in extraHaskellPackages.
        env =
          self.termonadKnownWorkingHaskellPkgSet.ghcWithPackages
            (hpkgs: [ hpkgs.termonad ] ++ self.termonadExtraHaskellPackages hpkgs);
      in
      self.stdenv.mkDerivation {
        name = "termonad-with-packages-ghc-${env.version}";
        buildInputs = [
          self.gdk-pixbuf
          self.gnome.adwaita-icon-theme
          self.hicolor-icon-theme
        ];
        nativeBuildInputs = [ self.wrapGAppsHook ];
        dontBuild = true;
        unpackPhase = ":";
        # Using installPhase instead of buildCommand was recommended here:
        # https://github.com/cdepillabout/termonad/pull/109
        installPhase = ''
          runHook preInstall
          mkdir -p $out/bin
          ln -sf ${env}/bin/termonad $out/bin/termonad
          gappsWrapperArgs+=(
            --set NIX_GHC "${env}/bin/ghc"
          )
          runHook postInstall
        '';
        preferLocalBuild = true;
        allowSubstitutes = false;
      };
  };
in

[ haskellPackagesOverlay ]
