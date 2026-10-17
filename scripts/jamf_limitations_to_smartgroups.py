#!/usr/bin/env python3
"""
Convert Jamf Pro policy scope *Limitations* (directory users / user groups)
into computer smart groups, use the smart group as the policy *Target*, and
clear those limitations.  Uses jamf-cli (auth via your existing profile).

DRY RUN by default. --apply makes changes. Each policy's original XML is
saved to ./backup_<timestamp>/ before it is touched.

    python3 jamf_limitations_to_smartgroups.py --list                  # scan only; writes ids.txt + CSV
    python3 jamf_limitations_to_smartgroups.py --policy-id 42          # dry run, one policy
    python3 jamf_limitations_to_smartgroups.py --policy-id 42 52 --apply
    python3 jamf_limitations_to_smartgroups.py --ids-file batch1.txt --apply
    python3 jamf_limitations_to_smartgroups.py --apply                 # every matching policy

Optional: --profile <name> if you have multiple jamf-cli profiles.
"""
import argparse
import base64
import hashlib
import json
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
from pathlib import Path

# ---------------------------------------------------------------------------
# CONFIG - these match a Jamf Pro tenant using a cloud identity provider. Verify
# against a smart group built by hand in the UI:
#   jamf-cli pro classic-computer-groups get --name "<your test group>" -o raw
# and compare the <criterion><name> / <search_type> values.
# USER_CRITERION (individual-user limitations) is untested - check it before use.
# ---------------------------------------------------------------------------
GROUP_CRITERION = "Username directory service group"  # for limitation user_groups
GROUP_SEARCH_TYPE = "member of"
USER_CRITERION = "Username"                                # for limitation users
USER_SEARCH_TYPE = "is"
PREFIX = ""  # smart group is named exactly like the limitation group
# ---------------------------------------------------------------------------

BASE = ["jamf-cli"]


def cli(args, stdin=None, check=True):
    p = subprocess.run(BASE + args, input=stdin, capture_output=True, text=True)
    if check and p.returncode != 0:
        raise RuntimeError(
            f"jamf-cli {' '.join(args)} failed ({p.returncode})\n"
            f"--- stderr ---\n{p.stderr.strip()}\n--- stdout ---\n{p.stdout.strip()}\n"
            f"--- sent ---\n{stdin or ''}")
    return p


def list_policies():
    out = cli(["pro", "classic-policies", "list", "-o", "json", "--no-input"]).stdout
    data = json.loads(out)
    if isinstance(data, dict):  # tolerate {"policies":[...]} style
        data = next((v for v in data.values() if isinstance(v, list)), [])
    return [{"id": int(d["id"]), "name": d.get("name", "?")} for d in data]


def get_policy_xml(pid):
    out = cli(["pro", "classic-policies", "get", str(pid), "-o", "raw", "--no-input"]).stdout
    return ET.fromstring(out)


_blob_cache = {}


def group_blob(name):
    """Jamf stores the directory-group criterion value as base64({"uuid":..,"serverId":"..."}).
    Look the group up by exact name via `jamf-cli pro ldap groups`."""
    if name in _blob_cache:
        return _blob_cache[name]
    out = cli(["pro", "ldap", "groups", "--q", name, "-o", "json", "--no-input"]).stdout
    # jamf-cli may print hints after the JSON; keep only the JSON object
    data = json.JSONDecoder().raw_decode(out[out.index("{"):])[0]
    hits = [r for r in data.get("results", []) if r.get("name") == name]
    if len(hits) != 1:
        raise LookupError(f"directory group '{name}': {len(hits)} exact matches "
                          f"({data.get('totalCount', 0)} partial)")
    r = hits[0]
    blob = base64.b64encode(json.dumps(
        {"uuid": r["uuid"], "serverId": str(r["ldapServerId"])}, separators=(",", ":")).encode()).decode()
    _blob_cache[name] = blob
    return blob


def names(parent, tag):
    if parent is None:
        return []
    return [e.findtext("name") for e in parent.findall(tag) if e.findtext("name")]


def group_name_for(users, groups, prefix=PREFIX, suffix=""):
    label = ", ".join(sorted(groups) + sorted(users))
    name = f"{prefix}{label}{suffix}"
    if len(name) > 120:
        h = hashlib.sha1(label.encode()).hexdigest()[:8]
        name = f"{prefix}{label[:90]}... [{h}]{suffix}"
    return name


def criterion(parent, name, priority, and_or, search_type, value, op=False, cp=False):
    c = ET.SubElement(parent, "criterion")
    for k, v in (("name", name), ("priority", priority), ("and_or", and_or),
                 ("search_type", search_type), ("value", value),
                 ("opening_paren", "true" if op else "false"),
                 ("closing_paren", "true" if cp else "false")):
        ET.SubElement(c, k).text = str(v)


def build_group_xml(name, users, groups, target_groups):
    """(user/dirgroup OR ...) AND (member of original target group OR ...)"""
    root = ET.Element("computer_group")
    ET.SubElement(root, "name").text = name
    ET.SubElement(root, "is_smart").text = "true"
    crits = ET.SubElement(root, "criteria")
    who = [(GROUP_CRITERION, GROUP_SEARCH_TYPE, group_blob(g)) for g in sorted(groups)] + \
          [(USER_CRITERION, USER_SEARCH_TYPE, u) for u in sorted(users)]
    p = 0
    for i, (cn, st, val) in enumerate(who):
        criterion(crits, cn, p, "and" if p == 0 else "or", st, val,
                  op=(len(who) > 1 and i == 0), cp=(len(who) > 1 and i == len(who) - 1))
        p += 1
    tgs = sorted(target_groups)
    for i, tg in enumerate(tgs):
        criterion(crits, "Computer Group", p, "and" if i == 0 else "or", "member of", tg,
                  op=(len(tgs) > 1 and i == 0), cp=(len(tgs) > 1 and i == len(tgs) - 1))
        p += 1
    return ET.tostring(root, encoding="unicode")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--policy-id", type=int, nargs="+", help="one or more policy IDs")
    ap.add_argument("--ids-file", help="text file with one policy ID per line (# comments ok)")
    ap.add_argument("--list", action="store_true",
                    help="only scan: list policies that have user/user-group limitations, write ids.txt + CSV")
    ap.add_argument("--profile", help="jamf-cli profile name")
    ap.add_argument("--keep-targets", action="store_true",
                    help="also require membership in the policy's old target groups (default: replace them)")
    args = ap.parse_args()
    if args.profile:
        BASE.extend(["--profile", args.profile])

    backup = Path(f"backup_{time.strftime('%Y%m%d_%H%M%S')}")
    done_groups, changed, skipped = {}, [], []
    ids = list(args.policy_id or [])
    if args.ids_file:
        ids += [int(l.split("#")[0].strip()) for l in Path(args.ids_file).read_text().splitlines()
                if l.split("#")[0].strip()]
    policies = [{"id": i, "name": "?"} for i in ids] if ids else list_policies()

    if args.list:
        rows = []
        for pol in policies:
            px = get_policy_xml(pol["id"])
            sc = px.find("scope")
            lim = sc.find("limitations") if sc is not None else None
            if lim is None:
                continue
            u, g = names(lim.find("users"), "user"), names(lim.find("user_groups"), "user_group")
            if not u and not g:
                continue
            tg = names(sc.find("computer_groups"), "computer_group")
            other = any(sc.find(t) is not None and len(sc.find(t)) > 0 for t in ("computers", "buildings", "departments"))
            tgt = "ALL" if (sc.findtext("all_computers") or "").lower() == "true" else "; ".join(tg)
            rows.append((pol["id"], px.findtext("general/name"), "; ".join(g), "; ".join(u),
                         tgt + (" +computers/bldgs/depts" if other else "")))
        import csv
        with open("policies_with_limitations.csv", "w", newline="") as f:
            w = csv.writer(f)
            w.writerow(["id", "name", "limit_user_groups", "limit_users", "targets"])
            w.writerows(rows)
        Path("ids.txt").write_text("\n".join(f"{r[0]}  # {r[1]}" for r in rows) + "\n")
        for r in rows:
            print(f"{r[0]:>5}  {r[1]}  |  groups: {r[2] or '-'}  users: {r[3] or '-'}  targets: {r[4]}")
        print(f"\n{len(rows)} of {len(policies)} policies have limitations. Wrote ids.txt and policies_with_limitations.csv")
        return

    print(f"Scanning {len(policies)} policies ({'APPLY' if args.apply else 'DRY RUN'})...\n")

    for pol in policies:
        pid = pol["id"]
        px = get_policy_xml(pid)
        pname = px.findtext("general/name")
        scope = px.find("scope")
        lim = scope.find("limitations") if scope is not None else None
        if lim is None:
            continue
        users = names(lim.find("users"), "user")
        ugroups = names(lim.find("user_groups"), "user_group")
        if not users and not ugroups:
            continue

        all_comp = (scope.findtext("all_computers") or "false").lower() == "true"
        target_groups = names(scope.find("computer_groups"), "computer_group")
        if any(scope.find(t) is not None and len(scope.find(t)) > 0
               for t in ("computers", "buildings", "departments")):
            skipped.append((pid, pname, "targets include computers/buildings/departments - manual"))
            continue
        if not all_comp and not target_groups:
            skipped.append((pid, pname, "no recognizable targets"))
            continue

        prefix = PREFIX
        # Default: old targets (e.g. All Managed Clients) are replaced by the new smart group.
        keep = target_groups if (args.keep_targets and not all_comp) else []
        odd = [t for t in target_groups if t != "All Managed Clients"]
        if not all_comp and odd and not args.keep_targets:
            print(f"    NOTE: replacing non-default targets {odd} (use --keep-targets to intersect)")
        try:
            group_xml = build_group_xml("TMP", users, ugroups, keep)
        except LookupError as e:
            skipped.append((pid, pname, str(e)))
            print(f"    SKIPPED: {e}")
            continue
        gname = group_name_for(users, ugroups, prefix)
        # same name already used this run by a different definition (e.g. different original targets)? disambiguate
        sig = group_xml
        if gname in done_groups and done_groups[gname] != sig:
            gname = group_name_for(users, ugroups, prefix, f" [policy {pid}]")
        group_xml = build_group_xml(gname, users, ugroups, keep)
        print(f"[{pid}] {pname}\n    limits: users={users} groups={ugroups}"
              f"\n    old targets: {'ALL' if all_comp else target_groups}\n    -> {gname}")

        # Build new scope XML (keep exclusions + network segment limits)
        new_scope = ET.Element("scope")
        ET.SubElement(new_scope, "all_computers").text = "false"
        g = ET.SubElement(ET.SubElement(new_scope, "computer_groups"), "computer_group")
        ET.SubElement(g, "name").text = gname
        nl = ET.SubElement(new_scope, "limitations")
        ET.SubElement(nl, "users")
        ET.SubElement(nl, "user_groups")
        if lim.find("network_segments") is not None:
            nl.append(lim.find("network_segments"))
        if scope.find("exclusions") is not None:
            new_scope.append(scope.find("exclusions"))
        policy_xml = ET.Element("policy")
        gen = ET.SubElement(policy_xml, "general")
        ET.SubElement(gen, "name").text = pname
        policy_xml.append(new_scope)

        flags =["--yes", "--no-input"] + ([] if args.apply else ["--dry-run"])

        if args.apply:
            backup.mkdir(exist_ok=True)
            (backup / f"policy_{pid}.xml").write_text(ET.tostring(px, encoding="unicode"))

        if gname not in done_groups:
            cli(["pro", "classic-computer-groups", "apply"] + flags, stdin=group_xml)
            done_groups[gname] = sig
        cli(["pro", "classic-policies", "apply"] + flags, stdin=ET.tostring(policy_xml, encoding="unicode"))
        print("    " + ("group + policy updated" if args.apply else "[dry-run] ok"))
        changed.append(pid)

    print(f"\n{'Updated' if args.apply else 'Would update'}: {len(changed)} policies")
    for pid, n, why in skipped:
        print(f"  SKIPPED [{pid}] {n}: {why}")
    if args.apply and backup.exists():
        print(f"Backups in ./{backup}/")


if __name__ == "__main__":
    try:
        main()
    except RuntimeError as e:
        sys.exit(str(e))
