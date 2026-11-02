# SiYuan {#module-services-siyuan}

[SiYuan](https://b3log.org/siyuan/) is a privacy-first personal knowledge
management system. This module runs the SiYuan kernel and serves its web UI.

## Quickstart {#module-services-siyuan-quickstart}

The following configuration starts SiYuan on `127.0.0.1:6806` with its data in
`/var/lib/siyuan`:

```nix
{
  services.siyuan = {
    enable = true;
    accessAuthCode = "replace-this";
  };
}
```

To make the instance reachable from other machines, enable
{option}`services.siyuan.networkServe` and optionally open the firewall:

```nix
{
  services.siyuan = {
    enable = true;
    networkServe = true;
    openFirewall = true;
    accessAuthCode = "replace-this";
  };
}
```

The access code is passed on the command line. For a secret that is not visible
in the Nix store, use an environment file instead:

```nix
{
  services.siyuan = {
    enable = true;
    networkServe = true;
    environmentFile = "/run/secrets/siyuan.env";
  };
}
```

The environment file can contain:

```text
SIYUAN_ACCESS_AUTH_CODE=replace-this
```

The kernel's data directory is managed by systemd as
{file}`/var/lib/siyuan`. Configuration written by the web UI is kept in
{file}`/var/lib/siyuan/conf/conf.json`.

## LAN sync {#module-services-siyuan-lan-sync}

LAN sync is separate from {option}`services.siyuan.networkServe`. It opens a
TLS listener on an ephemeral port and uses mDNS to find peers on the local
network. To make that listener and mDNS reachable when the NixOS firewall is
enabled:

```nix
{
  networking.nftables.enable = true;

  services.siyuan = {
    enable = true;
    openLANSyncFirewall = true;
  };
}
```

The option requires the nftables firewall backend. It creates a dedicated
`inet siyuan_lan_sync` table and adds the `siyuan.service` cgroup to its
`services` set. Inbound TCP and UDP traffic is accepted only when the target
socket belongs to that cgroup. This permits SiYuan's ephemeral listener
without opening an ephemeral port range, and it deliberately does not expose
{option}`services.siyuan.port`. UDP port 5353 and SiYuan's ephemeral UDP
sockets are needed for mDNS queries and replies. Other processes, including
Avahi, can share port 5353 through multicast socket reuse.

nftables sets cannot be referenced across tables, and systemd's `NFTSet=`
cannot address the NixOS firewall's hyphenated `nixos-fw` table name. The
dedicated table therefore marks matching packets with bit `0x40000000`, and
the NixOS `input-allow` chain accepts that mark. The option reserves this
packet mark bit.

LAN sync only accelerates an existing SiYuan sync configuration. Enable cloud
sync and the LAN option in SiYuan's web UI, and configure the same repository
key and sync target on every device. The cloud service remains authoritative;
LAN peers are used to fetch object chunks when available. The repository key
also scopes mDNS discovery, so unrelated SiYuan instances do not appear as
peers.

To audit the firewall rule and the dynamic cgroup membership:

```ShellSession
# nft list table inet siyuan_lan_sync
# nft list table inet nixos-fw | grep 'SiYuan LAN sync'
# curl -u siyuan:ACCESS_CODE -X POST http://127.0.0.1:6806/api/sync/getSyncLANStatus
```

The API should report `"enabled": true`, `"active": true`, and eventually
`"connectedPeers": 1` when another authenticated device is present.

The system service disables the kernel's optional compatibility listener on
`6806`, so a desktop client on the same machine can keep using its fixed port.
Set {option}`services.siyuan.port` to `6806` if the server itself should own
that endpoint.

The kernel exits with status 0 when the web UI imports settings or calls
`/api/system/exit`, expecting a desktop client to restart it. The service uses
`Restart = "always"` with exponential backoff (2 s up to 1 min), so it comes
back on its own; five starts within five minutes leave the unit in `failed`
instead of spinning forever. `systemctl restart siyuan` remains the manual
equivalent. This matches the official container deployment, whose compose
examples use `restart: unless-stopped`; systemd never restarts a unit after
`systemctl stop`, so the two policies line up.

Starting the kernel also copies `appearance/` into the workspace after the HTTP
server is already listening, so the first requests can still 404. An
`ExecStartPost` waits for those assets, which means `systemctl start` returns
only once the UI is servable.

## Network proxy {#module-services-siyuan-network-proxy}

By default the module leaves the network proxy setting in
{file}`conf.json` under the web UI's control. To make NixOS configuration
authoritative at startup, select a proxy mode and provide the proxy URLs
through a runtime environment file:

```nix
{
  services.siyuan = {
    networkProxy = "system";
    environmentFile = "/run/secrets/siyuan-proxy.env";
  };
}
```

The environment file should be readable only by the service user, for example
mode `0600`, and can contain:

```text
HTTP_PROXY=http://127.0.0.1:7890
HTTPS_PROXY=http://127.0.0.1:7890
NO_PROXY=localhost,127.0.0.1,::1
```

`networkProxy = "system"` tells the kernel to retain these variables. Setting
only `HTTP_PROXY` or `HTTPS_PROXY` is not sufficient: the kernel otherwise
clears them from its environment during startup. Use `"direct"` to disable
proxying. Leaving the option at `null`, the default, keeps the web UI in
control.

The module compares the desired proxy mode with {file}`conf.json` and replaces
the file atomically only when the value differs. Other settings and web UI
changes are preserved, but a proxy change made in the web UI lasts only until
the next service restart.

Keep the environment file outside the Nix store, such as a `sops-nix` template
under {file}`/run/secrets`, and pass its runtime path as a string. This keeps
proxy credentials out of {file}`conf.json`, the Nix store, and the generated
unit. Restart `siyuan.service` after changing either the proxy mode or the
environment file.

To audit the effective mode and environment-file path:

```ShellSession
# jq '.system.networkProxy' /var/lib/siyuan/conf/conf.json
# systemctl show siyuan.service -p EnvironmentFiles
# journalctl -u siyuan.service | grep 'network proxy'
```

## Reverse proxy {#module-services-siyuan-reverse-proxy}

When placing SiYuan behind a TLS-terminating reverse proxy, keep
`networkServe = false` if the proxy connects over loopback, or enable it when
the proxy connects over the network. Set {option}`services.siyuan.ssl` when the
public URL uses HTTPS so authentication cookies are marked secure.
