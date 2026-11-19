#!/usr/bin/env python3
"""Read nixpkgs-ci/branches.toml for the CI workflows.

The file is the single source of truth for the branches CI maintains. Keeping
its one parser here means `ci-check`, `update` and `integrate` cannot drift on
what a valid entry is.
"""

import argparse
import json
import re
import sys
import tomllib
from datetime import datetime, timezone

INTERVALS = ("1h", "2h", "3h", "4h", "6h", "8h", "12h", "daily", "weekly")
ATTR = re.compile(r"^[A-Za-z0-9_+-]+$")


class ConfigError(Exception):
    pass


def load(path):
    try:
        with open(path, "rb") as fh:
            return tomllib.load(fh)
    except (OSError, tomllib.TOMLDecodeError) as e:
        raise ConfigError(f"{path} 读不了或不是合法的 TOML：{e}") from e


def units(branch):
    """Every scheduling unit of a branch: attrs and the unit's interval.

    An attribute named in `attrs` is its own unit at the default interval. A
    `[[branch.unit]]` table names the attributes one `nix-update` rewrites
    together and gives that whole group one interval.
    """
    result = [{"attrs": [attr], "interval": "1h"}
              for attr in branch.get("attrs", [])]
    result.extend({
        "attrs": unit["attrs"],
        "interval": unit.get("interval", "1h"),
    } for unit in branch.get("unit", []))
    return result


def columns(branch):
    """The attributes a branch declares, in file order and without duplicates."""
    return [attr for unit in units(branch) for attr in unit["attrs"]]


def validate(path, data):
    unknown = set(data) - {"branch"}
    if unknown:
        raise ConfigError(f"{path} 有未知顶层键：{sorted(unknown)}")

    branches = data.get("branch")
    if not isinstance(branches, list) or not branches:
        raise ConfigError(f"{path} 必须有一个非空的 [[branch]] 数组")

    seen = set()
    for i, branch in enumerate(branches, 1):
        where = f"第 {i} 个 [[branch]]"
        if not isinstance(branch, dict):
            raise ConfigError(f"{where} 不是表")

        unknown = set(branch) - {"name", "attrs", "unit"}
        if unknown:
            raise ConfigError(
                f"{where} 有未知键：{sorted(unknown)}"
                "（只接受 name/attrs/unit）")

        name = branch.get("name")
        if (not isinstance(name, str) or not name
                or any(c.isspace() for c in name) or ":" in name):
            raise ConfigError(f"{where} 的 name 必须是非空、无空白的分支名")
        if name in seen:
            raise ConfigError(f"分支 {name} 重复出现")
        seen.add(name)

        attrs = branch.get("attrs", [])
        if not isinstance(attrs, list):
            raise ConfigError(f"{name}: attrs 必须是字符串数组")
        if len(attrs) != len(set(attrs)):
            raise ConfigError(f"{name}: attrs 里有重复项")
        for attr in attrs:
            if not isinstance(attr, str) or not ATTR.match(attr):
                raise ConfigError(f"{name}: attrs 里的 {attr!r} 不是合法的属性名")

        seen_attrs = set(attrs)
        unit_tables = branch.get("unit", [])
        if not isinstance(unit_tables, list):
            raise ConfigError(f"{name}: unit 必须是 [[branch.unit]] 数组")
        for j, unit in enumerate(unit_tables, 1):
            where = f"{name} 的第 {j} 个 [[branch.unit]]"
            if not isinstance(unit, dict):
                raise ConfigError(f"{where} 不是表")
            unknown = set(unit) - {"attrs", "interval"}
            if unknown:
                raise ConfigError(
                    f"{where} 有未知键：{sorted(unknown)}"
                    "（只接受 attrs/interval）")

            unit_attrs = unit.get("attrs")
            if not isinstance(unit_attrs, list) or not unit_attrs:
                raise ConfigError(f"{where} 的 attrs 必须是非空字符串数组")
            if len(unit_attrs) != len(set(unit_attrs)):
                raise ConfigError(f"{where} 的 attrs 里有重复项")
            for attr in unit_attrs:
                if not isinstance(attr, str) or not ATTR.match(attr):
                    raise ConfigError(
                        f"{where} 的 {attr!r} 不是合法的属性名")
                if attr in seen_attrs:
                    raise ConfigError(
                        f"{name}: 属性 {attr} 出现了两次；一个属性只能属于一个"
                        "更新单元（attrs 里的属性和 unit 里的属性不要重复）")
                seen_attrs.add(attr)

            interval = unit.get("interval", "1h")
            if interval not in INTERVALS:
                raise ConfigError(
                    f"{where} 的更新间隔 {interval!r} 不认识；"
                    f"可用：{', '.join(INTERVALS)}")

    return branches


def read(path):
    return validate(path, load(path))


def find_branch(branches, name):
    for branch in branches:
        if branch["name"] == name:
            return branch
    names = ", ".join(b["name"] for b in branches)
    raise ConfigError(f"没有分支 {name}；branches.toml 里有：{names}")


def due(interval, hour, weekday):
    """Whether `interval` has a slot at this UTC hour and weekday."""
    if interval == "1h":
        return True
    if interval == "daily":
        return hour == 0
    if interval == "weekly":
        return hour == 0 and weekday == 7
    return hour % int(interval[:-1]) == 0


def cmd_plan(args):
    names = [b["name"] for b in read(args.file)]
    only = [b.strip() for b in (args.only or "").split(",") if b.strip()]
    if only:
        missing = [b for b in only if b not in names]
        if missing:
            print("::warning::only 里有 branches.toml 没有的分支："
                  + ", ".join(missing), file=sys.stderr)
        names = [b for b in names if b in only]
    print(json.dumps(names))


def cmd_show(args):
    branch = find_branch(read(args.file), args.branch)
    print(json.dumps({
        "attrs": branch.get("attrs", []),
        "units": units(branch),
    }))


def cmd_due(args):
    """One line per scheduling unit: index, interval, due, attrs.

    A unit is one `nix-update` run plus every attribute that run rewrites, so
    the decision belongs to the unit, not to a single attribute. Printing the
    members lets the caller log and skip the whole group together.
    """
    branch = find_branch(read(args.file), args.branch)
    now = datetime.now(timezone.utc)
    hour = now.hour if args.hour is None else args.hour
    weekday = now.isoweekday() if args.weekday is None else args.weekday
    for index, unit in enumerate(units(branch)):
        is_due = due(unit["interval"], hour, weekday)
        print("\t".join((
            str(index),
            unit["interval"],
            str(is_due).lower(),
            ",".join(unit["attrs"]),
        )))


def cmd_tsv(args):
    for branch in read(args.file):
        print(branch["name"] + "\t" + ",".join(columns(branch)))


def cmd_validate(args):
    names = [b["name"] for b in read(args.file)]
    with open(args.out, "w") as fh:
        fh.write("\n".join(names) + "\n")


def main():
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)

    plan = sub.add_parser("plan", help="branch names as a JSON array")
    plan.add_argument("--file", required=True)
    plan.add_argument("--only", default="")
    plan.set_defaults(func=cmd_plan)

    show = sub.add_parser("show", help="one branch's attrs and units as JSON")
    show.add_argument("--file", required=True)
    show.add_argument("branch")
    show.set_defaults(func=cmd_show)

    due_parser = sub.add_parser(
        "due", help="unit attrs and whether their unit is due now")
    due_parser.add_argument("--file", required=True)
    due_parser.add_argument("branch")
    due_parser.add_argument("--hour", type=int)
    due_parser.add_argument("--weekday", type=int, help="ISO weekday, Sunday = 7")
    due_parser.set_defaults(func=cmd_due)

    tsv = sub.add_parser("tsv", help="name<TAB>attrs for integrate")
    tsv.add_argument("--file", required=True)
    tsv.set_defaults(func=cmd_tsv)

    check = sub.add_parser("validate", help="validate and write branch names")
    check.add_argument("--file", required=True)
    check.add_argument("--out", required=True)
    check.set_defaults(func=cmd_validate)

    args = parser.parse_args()
    try:
        args.func(args)
    except ConfigError as e:
        # stderr, so a caller that captures stdout (`cfg=$(...)`) still shows
        # the reason. GitHub turns workflow commands on stderr into annotations
        # as well.
        print(f"::error::{e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
