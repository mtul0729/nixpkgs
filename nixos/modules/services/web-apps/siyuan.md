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

## Reverse proxy {#module-services-siyuan-reverse-proxy}

When placing SiYuan behind a TLS-terminating reverse proxy, keep
`networkServe = false` if the proxy connects over loopback, or enable it when
the proxy connects over the network. Set {option}`services.siyuan.ssl` when the
public URL uses HTTPS so authentication cookies are marked secure.
