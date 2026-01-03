{ config, lib, pkgs, ... }:

let
  cfg = config.programs.clawdis;
  homeDir = config.home.homeDirectory;
  appPackage = if cfg.appPackage != null then cfg.appPackage else cfg.package;

  mkBaseConfig = workspaceDir: {
    gateway = { mode = "local"; };
    agent = { workspace = workspaceDir; };
  };

  mkTelegramConfig = inst: lib.optionalAttrs inst.providers.telegram.enable {
    telegram = {
      enabled = true;
      tokenFile = inst.providers.telegram.botTokenFile;
      allowFrom = inst.providers.telegram.allowFrom;
      requireMention = inst.providers.telegram.requireMention;
    };
  };

  mkRoutingConfig = inst: {
    routing = {
      queue = {
        mode = inst.routing.queue.mode;
        bySurface = inst.routing.queue.bySurface;
      };
      groupChat = {
        requireMention = inst.routing.groupChat.requireMention;
      };
    };
  };

  instanceModule = { name, config, ... }: {
    options = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable this Clawdis instance.";
      };

      package = lib.mkOption {
        type = lib.types.package;
        default = cfg.package;
        description = "Clawdis batteries-included package.";
      };

      stateDir = lib.mkOption {
        type = lib.types.str;
        default = if name == "default"
          then "${homeDir}/.clawdis"
          else "${homeDir}/.clawdis-${name}";
        description = "State directory for this Clawdis instance (logs, sessions, config).";
      };

      workspaceDir = lib.mkOption {
        type = lib.types.str;
        default = "${config.stateDir}/workspace";
        description = "Workspace directory for this Clawdis instance.";
      };

      configPath = lib.mkOption {
        type = lib.types.str;
        default = "${config.stateDir}/clawdis.json";
        description = "Path to generated Clawdis config JSON.";
      };

      logPath = lib.mkOption {
        type = lib.types.str;
        default = if name == "default"
          then "/tmp/clawdis/clawdis-gateway.log"
          else "/tmp/clawdis/clawdis-gateway-${name}.log";
        description = "Log path for this Clawdis gateway instance.";
      };

      gatewayPort = lib.mkOption {
        type = lib.types.int;
        default = 18789;
        description = "Gateway port used by the Clawdis desktop app.";
      };

      providers.telegram = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Enable Telegram provider.";
        };

        botTokenFile = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Path to Telegram bot token file.";
        };

        allowFrom = lib.mkOption {
          type = lib.types.listOf lib.types.int;
          default = [];
          description = "Allowed Telegram chat IDs.";
        };

        requireMention = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Require @mention in Telegram groups.";
        };
      };

      providers.anthropic = {
        apiKeyFile = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Path to Anthropic API key file (used to set ANTHROPIC_API_KEY).";
        };
      };

      routing.queue = {
        mode = lib.mkOption {
          type = lib.types.enum [ "queue" "interrupt" ];
          default = "interrupt";
          description = "Queue mode when a run is active.";
        };

        bySurface = lib.mkOption {
          type = lib.types.attrs;
          default = {
            telegram = "interrupt";
            discord = "queue";
            webchat = "queue";
          };
          description = "Per-surface queue mode overrides.";
        };
      };

      routing.groupChat.requireMention = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Require mention for group chat activation.";
      };

      launchd.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Run Clawdis gateway via launchd (macOS).";
      };

      launchd.label = lib.mkOption {
        type = lib.types.str;
        default = if name == "default"
          then "com.steipete.clawdis.gateway"
          else "com.steipete.clawdis.gateway.${name}";
        description = "launchd label for this instance.";
      };

      app.install.enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Install Clawdis.app for this instance.";
      };

      app.install.path = lib.mkOption {
        type = lib.types.str;
        default = "${homeDir}/Applications/Clawdis.app";
        description = "Destination path for this instance's Clawdis.app bundle.";
      };

      appDefaults = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = name == "default";
          description = "Configure macOS app defaults for this instance.";
        };

        attachExistingOnly = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Attach existing gateway only (macOS).";
        };
      };

      configOverrides = lib.mkOption {
        type = lib.types.attrs;
        default = {};
        description = "Additional Clawdis config to merge into the generated JSON.";
      };
    };
  };

  legacyInstance = {
    enable = cfg.enable;
    package = cfg.package;
    stateDir = cfg.stateDir;
    workspaceDir = cfg.workspaceDir;
    configPath = "${cfg.stateDir}/clawdis.json";
    logPath = "/tmp/clawdis/clawdis-gateway.log";
    gatewayPort = 18789;
    providers = cfg.providers;
    routing = cfg.routing;
    launchd = cfg.launchd;
    configOverrides = {};
    appDefaults = {
      enable = true;
      attachExistingOnly = true;
    };
    app = {
      install = {
        enable = false;
        path = "${homeDir}/Applications/Clawdis.app";
      };
    };
  };

  instances = if cfg.instances != {}
    then cfg.instances
    else lib.optionalAttrs cfg.enable { default = legacyInstance; };

  enabledInstances = lib.filterAttrs (_: inst: inst.enable) instances;

  mkInstanceConfig = name: inst: let
    baseConfig = mkBaseConfig inst.workspaceDir;
    mergedConfig = lib.recursiveUpdate
      (lib.recursiveUpdate baseConfig (lib.recursiveUpdate (mkTelegramConfig inst) (mkRoutingConfig inst)))
      inst.configOverrides;
    configJson = builtins.toJSON mergedConfig;
    gatewayWrapper = pkgs.writeShellScriptBin "clawdis-gateway-${name}" ''
      set -euo pipefail

      if [ -n "${inst.providers.anthropic.apiKeyFile}" ]; then
        if [ ! -f "${inst.providers.anthropic.apiKeyFile}" ]; then
          echo "Anthropic API key file not found: ${inst.providers.anthropic.apiKeyFile}" >&2
          exit 1
        fi
        ANTHROPIC_API_KEY="$(cat "${inst.providers.anthropic.apiKeyFile}")"
        if [ -z "$ANTHROPIC_API_KEY" ]; then
          echo "Anthropic API key file is empty: ${inst.providers.anthropic.apiKeyFile}" >&2
          exit 1
        fi
        export ANTHROPIC_API_KEY
      fi

      exec "${inst.package}/bin/clawdis" "$@"
    '';
  in {
    homeFile = {
      name = inst.configPath;
      value = { text = configJson; };
    };

    dirs = [ inst.stateDir inst.workspaceDir (builtins.dirOf inst.logPath) ];

    launchdAgent = lib.optionalAttrs (pkgs.stdenv.hostPlatform.isDarwin && inst.launchd.enable) {
      "${inst.launchd.label}" = {
        enable = true;
        config = {
          Label = inst.launchd.label;
          ProgramArguments = [ "${gatewayWrapper}/bin/clawdis-gateway-${name}" ];
          RunAtLoad = true;
          KeepAlive = true;
          WorkingDirectory = inst.stateDir;
          StandardOutPath = inst.logPath;
          StandardErrorPath = inst.logPath;
          EnvironmentVariables = {
            CLAWDIS_CONFIG_PATH = inst.configPath;
            CLAWDIS_STATE_DIR = inst.stateDir;
            CLAWDIS_IMAGE_BACKEND = "sips";
            CLAWDIS_NIX_MODE = "1";
          };
        };
      };
    };

    appDefaults = lib.optionalAttrs (pkgs.stdenv.hostPlatform.isDarwin && inst.appDefaults.enable) {
      attachExistingOnly = inst.appDefaults.attachExistingOnly;
      gatewayPort = inst.gatewayPort;
    };

    appInstall = if !(pkgs.stdenv.hostPlatform.isDarwin && inst.app.install.enable && appPackage != null) then
      null
    else {
      name = lib.removePrefix "${homeDir}/" inst.app.install.path;
      value = {
        source = "${appPackage}/Applications/Clawdis.app";
        recursive = true;
        force = true;
      };
    };

    package = inst.package;
  };

  instanceConfigs = lib.mapAttrsToList mkInstanceConfig enabledInstances;
  appInstalls = lib.filter (item: item != null) (map (item: item.appInstall) instanceConfigs);

  appDefaults = lib.foldl' (acc: item: lib.recursiveUpdate acc item.appDefaults) {} instanceConfigs;

  appDefaultsEnabled = lib.filterAttrs (_: inst: inst.appDefaults.enable) enabledInstances;

  assertions = lib.flatten (lib.mapAttrsToList (name: inst: [
    {
      assertion = !inst.providers.telegram.enable || inst.providers.telegram.botTokenFile != "";
      message = "programs.clawdis.instances.${name}.providers.telegram.botTokenFile must be set when Telegram is enabled.";
    }
    {
      assertion = !inst.providers.telegram.enable || (lib.length inst.providers.telegram.allowFrom > 0);
      message = "programs.clawdis.instances.${name}.providers.telegram.allowFrom must be non-empty when Telegram is enabled.";
    }
  ]) enabledInstances);

in {
  options.programs.clawdis = {
    enable = lib.mkEnableOption "Clawdis (batteries-included)";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.clawdis;
      description = "Clawdis batteries-included package.";
    };

    appPackage = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = "Optional Clawdis app package (defaults to package if unset).";
    };

    installApp = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install Clawdis.app at the default location.";
    };

    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "${homeDir}/.clawdis";
      description = "State directory for Clawdis (logs, sessions, config).";
    };

    workspaceDir = lib.mkOption {
      type = lib.types.str;
      default = "${homeDir}/.clawdis/workspace";
      description = "Workspace directory for Clawdis agent skills.";
    };

    providers.telegram = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable Telegram provider.";
      };

      botTokenFile = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Path to Telegram bot token file.";
      };

      allowFrom = lib.mkOption {
        type = lib.types.listOf lib.types.int;
        default = [];
        description = "Allowed Telegram chat IDs.";
      };

      requireMention = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Require @mention in Telegram groups.";
      };
    };

    providers.anthropic = {
      apiKeyFile = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Path to Anthropic API key file (used to set ANTHROPIC_API_KEY).";
      };
    };

    routing.queue = {
      mode = lib.mkOption {
        type = lib.types.enum [ "queue" "interrupt" ];
        default = "interrupt";
        description = "Queue mode when a run is active.";
      };

      bySurface = lib.mkOption {
        type = lib.types.attrs;
        default = {
          telegram = "interrupt";
          discord = "queue";
          webchat = "queue";
        };
        description = "Per-surface queue mode overrides.";
      };
    };

    routing.groupChat.requireMention = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Require mention for group chat activation.";
    };

    launchd.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Run Clawdis gateway via launchd (macOS).";
    };

    instances = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule instanceModule);
      default = {};
      description = "Named Clawdis instances (prod/test).";
    };
  };

  config = lib.mkIf (cfg.enable || cfg.instances != {}) {
    assertions = assertions ++ [
      {
        assertion = lib.length (lib.attrNames appDefaultsEnabled) <= 1;
        message = "Only one Clawdis instance may enable appDefaults.";
      }
    ];

    home.packages = lib.unique (map (item: item.package) instanceConfigs);

    home.file =
      (lib.listToAttrs (map (item: item.homeFile) instanceConfigs))
      // (lib.optionalAttrs (pkgs.stdenv.hostPlatform.isDarwin && appPackage != null && cfg.installApp) {
        "Applications/Clawdis.app" = {
          source = "${appPackage}/Applications/Clawdis.app";
          recursive = true;
          force = true;
        };
      })
      // (lib.listToAttrs appInstalls);

    home.activation.clawdisDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      /bin/mkdir -p ${lib.concatStringsSep " " (lib.concatMap (item: item.dirs) instanceConfigs)}
    '';

    home.activation.clawdisAppDefaults = lib.mkIf (pkgs.stdenv.hostPlatform.isDarwin && appDefaults != {}) (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        /usr/bin/defaults write com.steipete.Clawdis clawdis.gateway.attachExistingOnly -bool ${lib.boolToString (appDefaults.attachExistingOnly or true)}
        /usr/bin/defaults write com.steipete.Clawdis gatewayPort -int ${toString (appDefaults.gatewayPort or 18789)}
      ''
    );

    launchd.agents = lib.mkMerge (map (item: item.launchdAgent) instanceConfigs);
  };
}
