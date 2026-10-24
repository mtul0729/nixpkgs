# Upstream's pre-release channel: the highest of stable/beta/alpha, so it is
# sometimes the same version as `siyuan` right after a stable release. Kept in
# this fork only — the upstream PR carries the stable channel alone.
#
# Linux only: the pre-release is used on Linux, and nobody has verified the
# darwin leg of this channel.
{ siyuan }:
siyuan.override {
  channel = "preview";
}
