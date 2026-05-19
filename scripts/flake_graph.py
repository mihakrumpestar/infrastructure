#!/usr/bin/env python3
"""Generate Mermaid dependency graph for den-based Nix flake structure.

Usage: task generate-deps
"""

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from collections import defaultdict
from datetime import datetime
from pathlib import Path

REPO_ROOT = Path(__file__).parent.parent
README_PATH = REPO_ROOT / "README.md"
GENERATED_DIR = REPO_ROOT / "generated"
DEPS_START = "<!-- DEPS_START -->"
DEPS_END = "<!-- DEPS_END -->"

EXCLUDE_DIRS = {
    ".git", "result", "generated", ".venv", ".devbox",
    "infrastructure-secrets", "node_modules", "devbox.d", "bin", "pkg", "docs",
}

# Maps system category dir -> mermaid ID prefix and label style
SYS_PREFIX = {"default": "sys", "optional": "opt", "type": "type"}


def find_nix_files():
    files = []
    for root, dirs, fnames in os.walk(REPO_ROOT):
        dirs[:] = [d for d in dirs if d not in EXCLUDE_DIRS]
        files.extend(Path(root) / f for f in fnames if f.endswith(".nix") and f != "flake.lock")
    return sorted(files)


def _match_pair(text, start, opn, cls):
    depth = 0
    for i in range(start, len(text)):
        if text[i] == opn: depth += 1
        elif text[i] == cls:
            depth -= 1
            if depth == 0: return i
    return -1


def _resolve_rel(import_path, current_file):
    path = current_file.parent
    for part in import_path.strip("\"'").rstrip("/").split("/"):
        if part == "..": path = path.parent
        elif part != ".": path = path / part
    path = path.resolve()
    if path.is_file(): return str(path.relative_to(REPO_ROOT))
    if path.is_dir() and (path / "default.nix").exists():
        return str((path / "default.nix").relative_to(REPO_ROOT))
    return None


def _stem(path, parts, idx):
    """Get .nix-stripped filename at parts[idx], with special cases."""
    name = parts[idx].replace(".nix", "")
    if name == "_hardware-configuration": return "hardware"
    if name.startswith("_"): name = name.lstrip("_")
    return name


def node_id_and_label(path):
    """Return (mermaid_node_id, display_label) for a file path."""
    p = path.split("/")

    if path == "flake.nix": return "flake", "flake"
    if path == "modules/den.nix": return "den", "den"

    if path.startswith("modules/hosts/"):
        host = p[2]
        if len(p) >= 4:
            stem = _stem(path, p, 3)
            if stem == "hardware":
                return f"host_{_sid(host)}_hardware", "hardware"
            return f"host_{_sid(host)}", host
        return f"host_{_sid(host)}", host

    if path.startswith("modules/users/"):
        name = p[-1].replace(".nix", "")
        return f"user_{_sid(name)}", name

    if path.startswith("modules/home/"):
        if path == "modules/home/default.nix":
            return "home_common", "common"
        aspect = p[2]
        if len(p) == 3:
            return f"home_{_sid(p[2].replace('.nix', ''))}", p[2].replace(".nix", "")
        if len(p) == 4:
            stem = _stem(path, p, 3)
            return (f"home_{_sid(aspect)}", aspect) if stem == "default" \
                else (f"home_{_sid(aspect)}_{_sid(stem)}", f"{aspect}/{stem}")
        stem = _stem(path, p, -1)
        parent = p[-2]
        return (f"home_{_sid(aspect)}_{_sid(parent)}", f"{aspect}/{parent}") if stem == "default" \
            else (f"home_{_sid(aspect)}_{_sid(parent)}_{_sid(stem)}", f"{aspect}/{parent}/{stem}")

    if path.startswith("modules/system/"):
        prefix = SYS_PREFIX.get(p[2], "sys")
        if len(p) == 4:
            stem = _stem(path, p, 3)
            return (prefix, stem) if stem == "default" else (f"{prefix}_{_sid(stem)}", stem)
        if len(p) == 5:
            parent, stem = p[3], _stem(path, p, 4)
            if stem in ("default", parent):
                return f"{prefix}_{_sid(parent)}", parent
            return f"{prefix}_{_sid(parent)}_{_sid(stem)}", f"{parent}/{stem}"
        parent, stem = p[3], _stem(path, p, -1)
        sub = p[-2]
        if stem == "default":
            return f"{prefix}_{_sid(parent)}_{_sid(sub)}", f"{parent}/{sub}"
        return f"{prefix}_{_sid(parent)}_{_sid(sub)}_{_sid(stem)}", f"{parent}/{sub}/{stem}"

    if path.startswith("packages/"):
        stem = p[-1].replace(".nix", "")
        return (f"pkg_{_sid(p[1])}", p[1]) if stem == "flake" \
            else (f"pkg_{_sid(p[1])}_{_sid(stem)}", p[1])
    if path.startswith("home-modules/"):
        stem = p[-1].replace(".nix", "")
        return (f"hmod_{_sid(p[1])}", p[1]) if stem == "flake" \
            else (f"hmod_{_sid(p[1])}_{_sid(stem)}", p[1])

    name = p[-1].replace(".nix", "")
    if name == "default" and len(p) > 1: name = p[-2]
    return _sid(name), name


def _sid(name):
    """Sanitize to valid Mermaid ID."""
    return re.sub(r"_+", "_", re.sub(r"[^a-zA-Z0-9_]", "_", name)).strip("_") or "node"


def find_aspect_file(name, all_files):
    """Find the file defining den.aspects.<name> or home.<name>."""
    candidates = [
        f"modules/system/default/{name}.nix", f"modules/system/default/{name}/default.nix",
        f"modules/system/optional/{name}.nix", f"modules/system/optional/{name}/default.nix",
        f"modules/system/type/{name}.nix",
        f"modules/home/{name}.nix", f"modules/home/{name}/default.nix",
        f"modules/hosts/{name}/default.nix",
    ]
    if name == "common":
        candidates.append("modules/home/default.nix")
    if "-" in name:
        parent, _, child = name.rpartition("-")
        for cat in ("default", "optional", "type"):
            candidates += [f"modules/system/{cat}/{parent}/{name}.nix",
                           f"modules/system/{cat}/{parent}/{child}.nix"]
    for c in candidates:
        if c in all_files: return c
    for f in sorted(all_files):
        if f.endswith(f"/{name}.nix") or f.endswith(f"/{name}/default.nix"):
            return f
    return None


def extract_aspects(content, file_path):
    """Extract den.aspects.* and home.* definitions with their includes."""
    aspects = {}
    for pattern, prefix in [(r"den\.aspects\.([\w-]+)\s*=\s*\{", "aspects"),
                             (r"\bhome\.([\w-]+)\s*=\s*\{", "home")]:
        for m in re.finditer(pattern, content):
            name = m.group(1)
            brace_end = _match_pair(content, m.end() - 1, "{", "}")
            if brace_end == -1: continue
            block = content[m.end() - 1:brace_end + 1]
            info = aspects.setdefault(f"{prefix}.{name}",
                                      {"includes": [], "home_refs": [], "imports": []})
            for inc in re.finditer(r"den\.aspects\.([\w-]+)", block):
                if inc.group(1) != name: info["includes"].append(inc.group(1))
            inc_m = re.search(r"includes\s*=\s*\[", block)
            if inc_m:
                bk = _match_pair(block, inc_m.end() - 1, "[", "]")
                if bk != -1:
                    for hm in re.finditer(r"\bhome\.([\w-]+)", block[inc_m.start():bk]):
                        info["home_refs"].append(hm.group(1))
            for rel in re.finditer(r"(?:\.\./|\./)([\w./-]+\.nix)", block):
                resolved = _resolve_rel(rel.group(0), file_path)
                if resolved: info["imports"].append(resolved)
    return aspects


def extract_raw_imports(content, file_path):
    """Extract paths from imports = [ ... ] blocks."""
    imports = set()
    pos = 0
    while True:
        start = content.find("imports = [", pos)
        if start < 0: break
        end = _match_pair(content, start + len("imports = [") - 1, "[", "]")
        if end == -1: break
        for m in re.finditer(r"(?:\.\./|\./)[\w./-]+", content[start + len("imports = ["):end]):
            if m.group(0) not in ("./.", "././"):
                resolved = _resolve_rel(m.group(0), file_path)
                if resolved: imports.add(resolved)
        pos = end + 1
    return imports


def get_flake_inputs():
    try:
        r = subprocess.run(["nix", "flake", "metadata", "--json"], capture_output=True, text=True, cwd=REPO_ROOT)
        if r.returncode != 0: return [], {}
        data = json.loads(r.stdout)
        fc = (REPO_ROOT / "flake.nix").read_text()
        external, local = [], {}
        for name in data.get("locks", {}).get("nodes", {}):
            if name == "root": continue
            url = None
            im = re.search(rf'{name}\.url\s*=\s*"([^"]+)"', fc)
            if im: url = im.group(1)
            else:
                bm = re.search(rf'{name}\s*=\s*\{{[^}}]*url\s*=\s*"([^"]+)"[^}}]*\}}', fc, re.DOTALL)
                if bm: url = bm.group(1)
            if url:
                if url.startswith("./"): local[name] = url
                elif name not in external: external.append(name)
            elif name not in external and re.search(rf"^\s*{name}\s*[.{{=]", fc, re.MULTILINE):
                external.append(name)
        return sorted(external), local
    except Exception as e:
        print(f"⚠ Error getting flake inputs: {e}", file=sys.stderr)
        return [], {}


def build_graph():
    files = find_nix_files()
    deps, all_files, aspect_info = defaultdict(set), set(), {}
    for f in files:
        rel = str(f.relative_to(REPO_ROOT))
        all_files.add(rel)
        try:
            content = f.read_text()
            deps[rel].update(extract_raw_imports(content, f))
            a = extract_aspects(content, f)
            if a: aspect_info[rel] = a
        except Exception as e:
            print(f"⚠ Error parsing {rel}: {e}", file=sys.stderr)
    return dict(deps), aspect_info, all_files


STYLES = {
    "input": "fill:#e0f7fa,stroke:#00838f,stroke-width:1px,color:#006064",
    "local": "fill:#efebe9,stroke:#6d4c41,stroke-width:1px,color:#4e342e",
    "flake": "fill:#f3e5f5,stroke:#7b1fa2,stroke-width:1.5px,color:#7b1fa2",
    "hosts": "fill:#e8f5e9,stroke:#388e3c,stroke-width:1px,color:#2e7d32",
    "users": "fill:#fce4ec,stroke:#c2185b,stroke-width:1px,color:#ad1457",
    "aspect": "fill:#e3f2fd,stroke:#1565c0,stroke-width:1px,color:#1565c0",
    "config": "fill:#fafafa,stroke:#757575,stroke-width:0.5px,color:#424242",
}


def generate_mermaid(deps, aspect_info, all_files):
    L = ["```mermaid"]
    L.append("%%{init: {")
    L.append("  'theme': 'base',")
    L.append("  'themeVariables': {")
    L.append("    'fontSize': '14px',")
    L.append("    'fontFamily': 'system-ui',")
    L.append("    'lineColor': '#888'")
    L.append("  },")
    L.append("  'flowchart': {")
    L.append("    'nodeSpacing': 3,")
    L.append("    'rankSpacing': 40,")
    L.append("    'padding': 2,")
    L.append("    'diagramPadding': 3")
    L.append("  }")
    L.append("}}%%")
    L.append("")
    L.append("flowchart LR")

    # Categorize files
    hosts, host_hw, users, sys_aspects, home_aspects = set(), {}, set(), set(), set()
    for path in sorted(all_files):
        parts = path.split("/")
        if path.startswith("modules/hosts/") and len(parts) >= 3:
            hosts.add(parts[2])
            if len(parts) >= 4 and parts[3] == "_hardware-configuration.nix":
                host_hw[parts[2]] = path
        elif path.startswith("modules/users/") and not path.endswith("/default.nix"):
            users.add(parts[-1].replace(".nix", ""))
        elif path.startswith("modules/system/"): sys_aspects.add(path)
        elif path.startswith("modules/home/") and not path.endswith("namespace.nix"):
            home_aspects.add(path)

    ext_inputs, local_inputs = get_flake_inputs()

    # Styles
    L.append("")
    L.append("    %% Styles")
    for cls, defn in STYLES.items():
        L.append(f"    classDef {cls} {defn}")
    L.append("")

    # Subgraphs
    def subgraph(title, nodes):
        L.append(f"    subgraph {title}")
        for nid, label, cls in nodes:
            L.append(f'        {nid}["{label}"]:::{cls}')
        L.append("    end")
        L.append("")

    subgraph("Inputs[Inputs]", [
        (f"input_{_sid(n)}", n, "input") for n in ext_inputs
    ] + [
        (f"local_{_sid(n)}", p.lstrip("./"), "local") for n, p in sorted(local_inputs.items())
    ])

    subgraph("Core[Core]", [("flake", "flake", "flake"), ("den", "den", "flake")])

    subgraph("SystemAspects[System Aspects]", [
        (*node_id_and_label(p), "aspect") for p in sorted(sys_aspects)
    ])

    subgraph("HomeAspects[Home Namespace Aspects]", [
        (*node_id_and_label(p), "aspect") for p in sorted(home_aspects)
    ])

    host_nodes = []
    for h in sorted(hosts):
        host_nodes.append((f"host_{_sid(h)}", h, "hosts"))
        if h in host_hw:
            host_nodes.append((f"host_{_sid(h)}_hardware", "hardware", "config"))
    subgraph("Hosts[Hosts]", host_nodes)

    subgraph("Users[Users]", [
        (f"user_{_sid(u)}", u, "users") for u in sorted(users)
    ])

    # Edges (deduplicated)
    edges = set()

    for n in ext_inputs: edges.add((f"input_{_sid(n)}", "flake"))
    for n in sorted(local_inputs): edges.add((f"local_{_sid(n)}", "flake"))
    edges.add(("flake", "den"))

    # den.nix -> baseline aspects + hosts + users
    den_content = ""
    den_path = REPO_ROOT / "modules" / "den.nix"
    if den_path.exists():
        try: den_content = den_path.read_text()
        except Exception: pass
    for m in re.finditer(r"den\.aspects\.([\w-]+)", den_content):
        target = find_aspect_file(m.group(1), all_files)
        if target: edges.add(("den", node_id_and_label(target)[0]))
    for h in sorted(hosts):
        target = find_aspect_file(h, all_files)
        if target: edges.add(("den", node_id_and_label(target)[0]))
    for u in sorted(users):
        uf = f"modules/users/{u}.nix"
        if uf in all_files: edges.add(("den", node_id_and_label(uf)[0]))

    # Aspect includes
    for path, aspects in aspect_info.items():
        src = node_id_and_label(path)[0]
        for _, info in aspects.items():
            for inc in info["includes"]:
                target = find_aspect_file(inc, all_files)
                if target: edges.add((src, node_id_and_label(target)[0]))
            for href in info["home_refs"]:
                target = find_aspect_file(href, all_files)
                if target: edges.add((src, node_id_and_label(target)[0]))
            for imp in info["imports"]:
                if imp in all_files: edges.add((src, node_id_and_label(imp)[0]))

    # Raw import edges
    for src_path in sorted(deps):
        if src_path.startswith(("packages/", "home-modules/")) or src_path.endswith("namespace.nix"): continue
        src_id = node_id_and_label(src_path)[0]
        for tgt_path in sorted(deps[src_path]):
            if tgt_path.startswith(("packages/", "home-modules/")) or tgt_path.endswith("namespace.nix"): continue
            if tgt_path in all_files: edges.add((src_id, node_id_and_label(tgt_path)[0]))

    L.append("")
    for s, t in sorted(edges):
        L.append(f"    {s} --> {t}")

    L.extend(["", "```"])
    return "\n".join(L)


def update_readme(content):
    if not README_PATH.exists(): return
    txt = README_PATH.read_text()
    s, e = txt.find(DEPS_START), txt.find(DEPS_END)
    if s == -1 or e == -1: return
    README_PATH.write_text(txt[:s + len(DEPS_START)] + "\n" + content + "\n" + txt[e:])
    print("✓ Updated README.md", file=sys.stderr)


def export_png(mermaid, output):
    mmdc = shutil.which("mmdc")
    if not mmdc:
        for p in (REPO_ROOT / ".devbox/nix/profile/default/bin/mmdc",
                  Path.home() / ".devbox/nix/profile/default/bin/mmdc"):
            if p.exists(): mmdc = str(p); break
    if not mmdc:
        print("⚠ mmdc not found, skipping PNG", file=sys.stderr); return

    content = mermaid.removeprefix("```mermaid\n").removesuffix("\n```\n").removesuffix("```")
    with tempfile.NamedTemporaryFile(mode="w", suffix=".mmd", delete=False) as f:
        f.write(content)
        tmp = f.name
    try:
        r = subprocess.run([mmdc, "-i", tmp, "-o", str(output), "-b", "white", "-s", "4", "-w", "4096"],
                          capture_output=True, text=True)
        if r.returncode != 0: print(f"⚠ PNG export failed: {r.stderr}", file=sys.stderr)
        else: print(f"✓ Exported {output}", file=sys.stderr)
    finally:
        Path(tmp).unlink(missing_ok=True)


def main():
    print("Building dependency graph...", file=sys.stderr)
    deps, aspect_info, all_files = build_graph()
    print(f"Found {len(all_files)} files, {sum(len(v) for v in deps.values())} imports, "
          f"{len(aspect_info)} aspect definitions", file=sys.stderr)

    mermaid = generate_mermaid(deps, aspect_info, all_files)
    update_readme(mermaid)

    out = GENERATED_DIR / f"flake-graph_{datetime.now():%Y%m%d_%H%M%S}"
    out.mkdir(parents=True, exist_ok=True)
    (out / "infrastructure-flake-graph.md").write_text(mermaid)
    print(f"✓ Saved {out / 'infrastructure-flake-graph.md'}", file=sys.stderr)
    export_png(mermaid, out / "infrastructure-flake-graph.png")


if __name__ == "__main__":
    main()
