{
  config,
  lib,
  pkgs,
  utils,
  ...
}:

let
  cfg = config.services.siyuan;

  workspaceDir = "/var/lib/siyuan";
  workingDir = "${cfg.package}/lib/siyuan";

  args = [
    (lib.getExe' cfg.package "siyuan-kernel")
    "serve"
    "--workspace"
    workspaceDir
    "--wd"
    workingDir
    "--port"
    (toString cfg.port)
    "--mode"
    "prod"
  ]
  ++ lib.optionals (cfg.accessAuthCode != "") [
    "--accessAuthCode"
    cfg.accessAuthCode
  ]
  ++ lib.optionals cfg.readOnly [
    "--readonly"
    "true"
  ]
  ++ lib.optionals cfg.ssl [
    "--ssl"
  ]
  ++ lib.optionals (cfg.lang != null) [
    "--lang"
    cfg.lang
  ]
  ++ cfg.extraArgs;

  privilegedPort = cfg.port < 1024;
in
{
  meta = {
    maintainers = [ lib.maintainers.myul ];
    doc = ./siyuan.md;
  };

  options.services.siyuan = {
    enable = lib.mkEnableOption "SiYuan note server";

    package = lib.mkPackageOption pkgs "siyuan-server" { };

    user = lib.mkOption {
      type = lib.types.str;
      default = "siyuan";
      description = "User account under which SiYuan runs.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "siyuan";
      description = "Group under which SiYuan runs.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 6806;
      description = "Port on which the SiYuan HTTP server listens.";
    };

    networkServe = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether the kernel should listen on all interfaces instead of only
        `127.0.0.1`. Enable this when exposing SiYuan directly or through a
        reverse proxy on another host.
      '';
    };

    accessAuthCode = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = ''
        Access code used by SiYuan's lock screen. The value is passed on the
        kernel command line and is therefore visible to local users and in the
        Nix store. Prefer {option}`services.siyuan.environmentFile` with
        `SIYUAN_ACCESS_AUTH_CODE` for a secret.
      '';
    };

    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = "/run/secrets/siyuan.env";
      description = ''
        Optional environment file read by systemd. It can provide
        `SIYUAN_ACCESS_AUTH_CODE` and other runtime environment variables.
      '';
    };

    lang = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "en_US";
      description = "Kernel UI language. Leave unset to use the browser language.";
    };

    readOnly = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to start the kernel in read-only mode.";
    };

    ssl = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Pass `--ssl` to the kernel. This marks authentication cookies as secure
        and is normally used when SiYuan is served over HTTPS, for example
        behind a TLS-terminating reverse proxy.
      '';
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to open {option}`services.siyuan.port` in the firewall.";
    };

    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional arguments passed to `siyuan-kernel serve`.";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users = lib.mkIf (cfg.user == "siyuan") {
      siyuan = {
        isSystemUser = true;
        group = cfg.group;
      };
    };

    users.groups = lib.mkIf (cfg.group == "siyuan") {
      siyuan = { };
    };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];

    warnings =
      lib.optional (cfg.networkServe && cfg.accessAuthCode == "" && cfg.environmentFile == null)
        ''
          services.siyuan is listening on all interfaces without an access code or
          environment file. Set services.siyuan.accessAuthCode or provide
          SIYUAN_ACCESS_AUTH_CODE through services.siyuan.environmentFile.
        '';

    systemd.services.siyuan = {
      description = "SiYuan note server";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      environment.HOME = workspaceDir;

      preStart = ''
        umask 0077
        conf="${workspaceDir}/conf/conf.json"
        mkdir -p "$(dirname "$conf")"
        if [[ -s "$conf" ]]; then
          tmp="$(mktemp "$conf.XXXXXX")"
          trap 'rm -f "$tmp"' EXIT
          ${lib.getExe pkgs.jq} --argjson networkServe ${lib.boolToString cfg.networkServe} \
            '.system.networkServe = $networkServe' "$conf" > "$tmp"
          mv "$tmp" "$conf"
          trap - EXIT
        else
          printf '{"system":{"networkServe":%s}}\n' ${lib.boolToString cfg.networkServe} > "$conf"
        fi
      '';

      serviceConfig = {
        Type = "simple";
        ExecStart = utils.escapeSystemdExecArgs args;
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = workspaceDir;
        StateDirectory = "siyuan";
        StateDirectoryMode = "0700";
        EnvironmentFile = lib.mkIf (cfg.environmentFile != null) cfg.environmentFile;
        Restart = "on-failure";
        RestartSec = 5;

        NoNewPrivileges = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectKernelLogs = true;
        ProtectControlGroups = true;
        ProtectClock = true;
        ProtectHostname = true;
        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_INET"
          "AF_INET6"
        ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        SystemCallArchitectures = "native";
        UMask = "0077";

        AmbientCapabilities = lib.optional privilegedPort "CAP_NET_BIND_SERVICE";
        CapabilityBoundingSet = lib.optional privilegedPort "CAP_NET_BIND_SERVICE";
      };
    };
  };
}
