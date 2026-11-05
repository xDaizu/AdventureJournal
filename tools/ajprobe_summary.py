#!/usr/bin/env python3
"""Summarise AJProbe's SavedVariables as Markdown for AdventureJournal/REFERENCE_SAMPLES.md.

Read-only: opens the file for reading and prints to stdout. It never writes to
AJProbe data (AJProbeDB.log / AJProbeDB.chat are the safety net, see ROADMAP M4b).

    py -3 tools/ajprobe_summary.py                       # newest Forever AJProbe.lua
    py -3 tools/ajprobe_summary.py --flavor classic      # newest Classic Era one
    py -3 tools/ajprobe_summary.py path\\to\\AJProbe.lua   # an explicit file

Message text from AJProbeDB.chat is never printed (only counts), because it is
other people's conversation. Event samples (loot messages etc.) are printed.
"""
import glob
import importlib.util
import json
import os
import re
import sys
from collections import Counter

WOW = r"D:\Games\Battle.net\World of Warcraft"
FLAVORS = {"forever": "_forever_", "classic": "_classic_era_"}
SECRET = "[SECRET]"
HERE = os.path.dirname(os.path.abspath(__file__))


def load_parser():
    """Reuse the exporter's minimal Lua-table reader."""
    path = os.path.join(HERE, "..", "ExportarDiario.py")   # tools/ lives inside the addon folder
    spec = importlib.util.spec_from_file_location("exportar_diario", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.LuaParser


def find_file(flavor):
    pattern = os.path.join(WOW, FLAVORS[flavor], "WTF", "Account", "*", "SavedVariables", "AJProbe.lua")
    found = sorted(glob.glob(pattern), key=os.path.getmtime, reverse=True)
    return found[0] if found else None


def read_db(path):
    with open(path, "r", encoding="utf-8", errors="replace") as handle:
        source = handle.read()
    match = re.search(r"\bAJProbeDB\s*=\s*\{", source)
    if not match:
        raise SystemExit("AJProbeDB not found in " + path)
    parser = load_parser()(source[match.start():])
    parser.pop()
    parser.pop()
    return parser.value()


def count_secrets(value):
    """Number of [SECRET] strings anywhere inside value."""
    if value == SECRET:
        return 1
    if isinstance(value, dict):
        return sum(count_secrets(v) for v in value.values())
    return 0


def secret_paths(value, prefix=""):
    if value == SECRET:
        return [prefix or "(value)"]
    out = []
    if isinstance(value, dict):
        for key, inner in value.items():
            out += secret_paths(inner, f"{prefix}.{key}" if prefix else str(key))
    return out


def arg(args, index):
    """Event argument by position (the Lua reader gives integer keys)."""
    args = args or {}
    return args.get(index, args.get(str(index)))


def short(value, limit=160):
    text = json.dumps(value, ensure_ascii=False)
    return text if len(text) <= limit else text[: limit - 3] + "..."


OWN_LOOT_GLOBALS = ("LOOT_ITEM_SELF", "LOOT_ITEM_SELF_MULTIPLE",
                    "LOOT_ITEM_PUSHED_SELF", "LOOT_ITEM_PUSHED_SELF_MULTIPLE")


def own_loot_regexes(strings):
    """The same patterns AdventureJournal builds in Compat.lua (ns.GetOwnLootPatterns)."""
    out = []
    for name in OWN_LOOT_GLOBALS:
        fmt = (strings or {}).get(name)
        if not isinstance(fmt, str) or not fmt:
            continue
        # Split on %s, %d, %1$s, %2$d ... and join the escaped pieces with a capture.
        parts = re.split(r"%(?:\d\$)?([sd])", fmt)
        pattern = re.escape(parts[0])
        for kind, literal in zip(parts[1::2], parts[2::2]):
            pattern += (r"(.+)" if kind == "s" else r"(\d+)") + re.escape(literal)
        out.append(re.compile("^" + pattern + "$"))
    return out


def section_env(db, out):
    env = db.get("env") or {}
    out.append("### Environment\n")
    out.append(f"- `GetBuildInfo()`: `{env.get('version')}`, `{env.get('build')}`, `{env.get('buildDate')}`, `{env.get('toc')}`. "
               f"`WOW_PROJECT_ID` = `{env.get('projectID')}`, locale `{env.get('locale')}`.")
    api = env.get("api") or {}
    present = sorted(k for k, v in api.items() if v)
    missing = sorted(k for k, v in api.items() if not v)
    out.append(f"- API present: {', '.join('`%s`' % k for k in present) or 'none'}.")
    out.append(f"- API **missing**: {', '.join('`%s`' % k for k in missing) or 'none'}.")
    events = env.get("events") or {}
    bad = {k: v for k, v in events.items() if v is not True}
    out.append(f"- Events registered by the probe: {len(events) - len(bad)} of {len(events)}.")
    for name, reason in sorted(bad.items()):
        out.append(f"  - **{name}** failed: `{reason}`")
    strings = env.get("strings") or {}
    if strings:
        out.append("\n| Global | Value |\n|---|---|")
        for key in sorted(strings):
            out.append(f"| `{key}` | `{strings[key]}` |")
    out.append("")


def section_samples(db, out):
    samples = db.get("samples") or {}
    out.append("### Event samples\n")
    out.append("Secret fields are listed by argument number. `SECRET` means the probe stored the marker.\n")
    out.append("| Event | Samples | Fields that were secret |\n|---|---|---|")
    for event in sorted(samples):
        entries = list(samples[event].values()) if isinstance(samples[event], dict) else samples[event]
        paths = Counter()
        for entry in entries:
            for path in secret_paths(entry):
                paths[path] += 1
        shown = ", ".join(f"`{p}` x{n}" for p, n in sorted(paths.items())) or "none"
        out.append(f"| `{event}` | {len(entries)} | {shown} |")
    out.append("")

    def first(event):
        data = samples.get(event)
        if not data:
            return []
        return list(data.values()) if isinstance(data, dict) else data

    loot = first("CHAT_MSG_LOOT")
    if loot:
        out.append("#### `CHAT_MSG_LOOT` (first sample, then every distinct colour prefix)\n")
        seen = set()
        for entry in loot:
            prefix = entry.get("colorPrefix")
            if prefix in seen:
                continue
            seen.add(prefix)
            args = entry.get("args") or {}
            out.append(f"- arg1 = `{short(arg(args, 1))}`; colour prefix `{prefix}`; current pattern matches: "
                       f"`{entry.get('matchesCurrentPattern')}`; item info: `{short(entry.get('itemInfo'))}`; "
                       f"arg5 (player) = `{short(arg(args, 5))}`")
        regexes = own_loot_regexes((db.get("env") or {}).get("strings"))
        if regexes:
            own = [bool(arg(e.get("args"), 1)) and any(r.match(arg(e.get("args"), 1)) for r in regexes) for e in loot]
            out.append(f"- **Own-loot patterns (M4):** {sum(own)} of {len(loot)} loot samples match the {len(regexes)} patterns built "
                       "from the `LOOT_ITEM*` strings above. Samples about other players' loot should NOT match; "
                       "a message of your own that does not match means own loot is being ignored.")
            for entry, matched in zip(loot, own):
                out.append(f"  - `{matched}`: `{short(arg(entry.get('args'), 1), 110)}`")
        else:
            out.append("- **Own-loot patterns (M4):** no `LOOT_ITEM*` strings in the data, so every loot message would be accepted.")
        out.append("- **Verify:** does the AdventureJournal pattern `|c[^|]*|Hitem:.-|h%[.-%]|h|r` match every prefix above?")
        out.append("")

    quest = first("QUEST_TURNED_IN")
    if quest:
        out.append("#### `QUEST_TURNED_IN`\n")
        for entry in quest[:3]:
            out.append(f"- args `{short(entry.get('args'))}`; title now `{short(entry.get('titlesNow'))}`; "
                       f"1 s later `{short(entry.get('titlesAfter1s'))}`")
        out.append("")

    for event in ("GOSSIP_SHOW", "BOSS_KILL", "ENCOUNTER_START", "ENCOUNTER_END", "PLAYER_ENTERING_WORLD"):
        entries = first(event)
        if not entries:
            continue
        out.append(f"#### `{event}`\n")
        for entry in entries[:4]:
            ctx = entry.get("ctx") or {}
            extra = {k: v for k, v in entry.items() if k not in ("ctx",)}
            out.append(f"- instance `{ctx.get('instanceType')}`, combat `{ctx.get('inCombat')}`: `{short(extra)}`")
        out.append("")


def section_log(db, out):
    log = db.get("log") or {}
    records = list(log.values()) if isinstance(log, dict) else list(log)
    out.append("### Activity log (`AJProbeDB.log`)\n")
    out.append(f"- {len(records)} records, {len({r.get('c') for r in records})} character(s).")
    by_event = Counter(r.get("e") for r in records)
    out.append("- By event: " + ", ".join(f"`{e}` {n}" for e, n in by_event.most_common()) + ".")
    by_instance = Counter(r.get("i") for r in records)
    out.append("- By instance type: " + ", ".join(f"`{i}` {n}" for i, n in by_instance.most_common()) + ".")
    secret_by_event = Counter()
    secret_fields = Counter()
    for record in records:
        for key, value in record.items():
            if value == SECRET:
                secret_by_event[record.get("e")] += 1
                secret_fields[f"{record.get('e')}.{key}"] += 1
    if secret_fields:
        out.append("- **Secret fields in the log:** " + ", ".join(f"`{k}` x{n}" for k, n in secret_fields.most_common()) + ".")
    else:
        out.append("- No secret field in the log.")
    zone_nil = sum(1 for r in records if r.get("z") == "<nil>")
    out.append(f"- Records with a nil zone: {zone_nil} (login happens before the zone is known).")
    chat = db.get("chat") or {}
    lines = list(chat.values()) if isinstance(chat, dict) else list(chat)
    if lines:
        channels = Counter(line.get("ch") or line.get("channel") for line in lines if isinstance(line, dict))
        secret_lines = sum(1 for line in lines if count_secrets(line))
        out.append(f"- Conversation log: {len(lines)} lines ({secret_lines} contain a secret); by channel: "
                   + ", ".join(f"`{c}` {n}" for c, n in channels.most_common()) + ". Text not printed.")
    out.append("")
    errors = db.get("errors")
    out.append("### Probe errors\n")
    out.append("none\n" if not errors else "```\n" + json.dumps(errors, ensure_ascii=False, indent=1)[:3000] + "\n```\n")


def main(argv):
    flavor = "forever"
    path = None
    args = list(argv)
    while args:
        arg = args.pop(0)
        if arg == "--flavor":
            flavor = args.pop(0)
        else:
            path = arg
    path = path or find_file(flavor)
    if not path or not os.path.exists(path):
        raise SystemExit(f"No AJProbe.lua found for {flavor} (log in once and /reload or log out so WoW writes it).")
    db = read_db(path)
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    out = [f"<!-- generated by tools/ajprobe_summary.py from {path} -->\n"]
    section_env(db, out)
    section_samples(db, out)
    section_log(db, out)
    print("\n".join(out))


if __name__ == "__main__":
    main(sys.argv[1:])
