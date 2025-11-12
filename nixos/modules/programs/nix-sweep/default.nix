{
  config,
  lib,
  pkgs,
  ...
}:

let
  nixSweepConfig = config.services.nix-sweep; # CORRECTED: Local variable now uses 'nixSweepConfig'

  # --- Configuration Option Definitions (Helper) ---
  mkPresetOptions =
    { defaultProfiles }:
    let
      # A partial set of options used specifically for individual presets.
      presetAttrs = {
        profiles = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = defaultProfiles;
          description = "What profiles this preset should sweep (e.g., \"system\", \"user\").";
        };

        # Generation Limits (Note: Null/0 behavior matches Rust logic)
        keepMin = lib.mkOption {
          type = lib.types.nullOr lib.types.int;
          default = 25;
          description = "Keep at least <N> generations (--keep-min).";
        };

        keepMax = lib.mkOption {
          type = lib.types.nullOr lib.types.int;
          default = null;
          description = "Keep at most <N> generations (--keep-max).";
        };

        # Duration Limits
        keepNewer = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = "7d";
          description = "Keep all generations newer than this duration (--keep-newer).";
        };

        removeOlder = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = "90d";
          description = "Discard all generations older than this duration (--remove-older).";
        };

        # Interactive Mode (Default to false for silent operations)
        interactive = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "If true, will prompt before removing generations or running GC (--interactive).";
        };

        # GC Configuration
        gc = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "If true, run Nix garbage collection afterwards (--gc).";
        };
        gcBigger = lib.mkOption {
          type = lib.types.nullOr lib.types.int;
          default = null;
          description = "Only perform GC if the store is bigger than <N> GiB (--gc-bigger).";
        };
        gcQuota = lib.mkOption {
          type = lib.types.nullOr lib.types.int;
          default = null;
          description = "Only perform GC if the store uses more than <N>% of its device (--gc-quota).";
        };
        gcModest = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Collect just enough garbage to meet the quota or limit (--gc-modest).";
        };
      };
    in
    {
      options = presetAttrs;
    };

  # --- Helper to convert Nix options to TOML structure (logically) ---
  toTomlPreset =
    preset:
    let
      # Maps Nix option names to Rust/TOML kebab-case names.
      # Filters out 'null' and 'false' for minimal output.
      filter =
        name: value: if value == null || (name != "interactive" && value == false) then null else value;
    in
    {
      "keep-min" = filter "keep-min" preset.keepMin;
      "keep-max" = filter "keep-max" preset.keepMax;
      "keep-newer" = filter "keep-newer" preset.keepNewer;
      "remove-older" = filter "remove-older" preset.removeOlder;
      "interactive" = filter "interactive" preset.interactive;
      "gc" = filter "gc" preset.gc;
      "gc-bigger" = filter "gc-bigger" preset.gcBigger;
      "gc-quota" = filter "gc-quota" preset.gcQuota;
      "gc-modest" = filter "gc-modest" preset.gcModest;
    };

  # Use the guaranteed YAML generator, as toTOML is missing in the current Nixpkgs version.
  yamlGenerator = lib.generators.toYAML { };

in
{
  options.services.nix-sweep = {
    enable = lib.mkEnableOption "Enable configuration for nix-sweep.";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.nix-sweep;
      description = "nix-sweep package to use.";
    };

    enableDefaultPreset = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "If true, enables the 'default' preset with sensible cleanup settings.";
    };

    defaultPreset = lib.mkOption {
      type = lib.types.submodule (mkPresetOptions {
        defaultProfiles = [ "system" ];
      });
      visible = nixSweepConfig.enableDefaultPreset;
      default = { };
      description = "Configuration for the 'default' preset.";
    };

    presets = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule (mkPresetOptions {
          defaultProfiles = [ "system" ];
        })
      );
      default = { };
      description = "User-defined custom cleanup presets for /etc/nix-sweep/presets.toml.";
    };
  };

  # --- CONFIGURATION IMPLEMENTATION ---
  config = lib.mkIf nixSweepConfig.enable {
    # 1. Collect and Map all Presets
    environment.etc."nix-sweep/presets.toml".source =
      let
        enabledPresets =
          (if nixSweepConfig.enableDefaultPreset then { "default" = nixSweepConfig.defaultPreset; } else { })
          // nixSweepConfig.presets;

        # Map the Nix preset structures to a structure suitable for YAML
        yamlPresets = lib.mapAttrs (name: preset: toTomlPreset preset) enabledPresets;

        # The content to be written to the file if it were YAML.
        yamlContent = lib.optionalString (lib.head (lib.attrNames yamlPresets) != null) (
          yamlGenerator yamlPresets
        );
      in
      pkgs.runCommand "nix-sweep-presets-toml" # Name of the derivation to generate the file
        # Add yq as a build input to perform the conversion
        { buildInputs = [ pkgs.yq ]; }
        ''
          # 1. Write the intermediate YAML content to a file
          # We use lib.escapeShellArg to ensure the multi-line content is safely passed to the shell.
          echo ${lib.escapeShellArg yamlContent} > presets.yaml

          # 2. Use yq to convert the YAML content to TOML format.
          # -P flag forces the output to be TOML (used to be -t in older versions, but -P is now preferred for TOML)
          ${pkgs.yq}/bin/yq -P < presets.yaml > $out
        '';

    # 2. Add a dependency on the package to ensure it exists
    environment.systemPackages = [ nixSweepConfig.package ];
  };
}
