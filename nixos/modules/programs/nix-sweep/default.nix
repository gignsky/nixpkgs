{
  config,
  lib,
  pkgs,
  ...
}:

let
  nixSweepConfig = config.services.nix-sweep; # Local configuration variable

  # --- Configuration Option Definitions (Helper) ---
  mkPresetOptions =
    { defaultProfiles }:
    let
      presetAttrs = {
        profiles = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = defaultProfiles;
          description = "What profiles this preset should sweep (e.g., \"system\", \"user\").";
        };

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

        interactive = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "If true, will prompt before removing generations or running GC (--interactive).";
        };

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

  # Use the guaranteed YAML generator
  yamlGenerator = lib.generators.toYAML { };

in
{
  options.services.nix-sweep = {
    enable = lib.mkEnableOption "Enable configuration for nix-sweep.";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.nix-sweep;
      defaultText = "pkgs.nix-sweep"; # Added to fix sandboxed doc generation
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
      visible = true; # Fixed to avoid option doc generation errors
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

        yamlPresets = lib.mapAttrs (name: preset: toTomlPreset preset) enabledPresets;

        yamlContent = lib.optionalString (lib.head (lib.attrNames yamlPresets) != null) (
          yamlGenerator yamlPresets
        );
      in
      pkgs.runCommand "nix-sweep-presets-toml" # Derivation name
        { buildInputs = [ pkgs.yq ]; }
        ''
          # Write YAML content to a temporary file
          echo ${lib.escapeShellArg yamlContent} > presets.yaml

          # Convert YAML to TOML using the robust '-o=toml' flag
          ${pkgs.yq}/bin/yq -o=toml < presets.yaml > $out
        '';

    # 2. Add a dependency on the package to ensure it exists
    environment.systemPackages = [ nixSweepConfig.package ];
  };
}
