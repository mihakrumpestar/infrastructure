#!/usr/bin/env python3
"""Generate the Mermaid dependency graph for the den-based flake structure.

Usage: task generate-flake-graph
"""

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path

REPO_ROOT = Path(__file__).parent.parent

# Local (non-remote) flake input URL prefixes: in-repo relative, sibling
# absolute path:, and relative git+file forms.
LOCAL_PREFIXES = ("./", "path:", "git+file:./", "git+file:../")

README_PATH = REPO_ROOT / "README.md"
GENERATED_DIR = REPO_ROOT / "generated"
DEPS_START = "<!-- DEPS_START -->"
DEPS_END = "<!-- DEPS_END -->"

EXCLUDE_DIRS = {
    ".git",
    "result",
    "generated",
    "decommissioned",
    ".venv",
    ".devbox",
    ".devenv",
    "infrastructure-secrets",
    "node_modules",
    "devbox.d",
    "bin",
    "pkg",
    "docs",
}

# Maps system category dir -> mermaid ID prefix and label style
SYS_PREFIX = {"default": "sys", "optional": "opt", "type": "type"}

def _local_label(url):
    """Human label for a local input URL: relative to the repo where possible."""
    if url.startswith("path:"):
        p = url[len("path:") :]
        try:
            return os.path.relpath(p, REPO_ROOT)
        except ValueError:
            return os.path.basename(p)
    return re.sub(r"^git\+file:", "", url)

def find_nix_files():
    files = []
    for root, dirs, fnames in os.walk(REPO_ROOT):
        dirs[:] = [d for d in dirs if d not in EXCLUDE_DIRS]
        files += [
            Path(root) / f for f in fnames if f.endswith(".nix") and f != "flake.lock"
        ]
    return sorted(files)

def _match_pair(text, start, opn, cls):
    depth = 0
    for i in range(start, len(text)):
        if text[i] == opn:
            depth += 1
        elif text[i] == cls:
            depth -= 1
            if depth == 0:
                return i
    return -1

def _resolve_rel(import_path, current_file):
    path = current_file.parent
    for part in import_path.strip("\"'").rstrip("/").split("/"):
        if part == "..":
            path = path.parent
        elif part != ".":
            path = path / part
    path = path.resolve()
    if path.is_file():
        return str(path.relative_to(REPO_ROOT))
    if path.is_dir() and (path / "default.nix").exists():
        return str((path / "default.nix").relative_to(REPO_ROOT))
    return None

def _stem(parts, idx):
    """``.nix``-stripped filename at parts[idx], with the design's aliases."""
    name = parts[idx].replace(".nix", "")
    if name == "_hardware-configuration":
        return "hardware"
    return name.lstrip("_") if name.startswith("_") else name

def node_id_and_label(path):
    """Return (mermaid_node_id, display_label) for a file path."""
    p = path.split("/")

    if path == "flake.nix":
        return "flake", "flake"
    if path == "modules/den.nix":
        return "den", "den"
    if path.startswith("modules/hosts/"):
        host = p[2]
        if len(p) >= 4 and _stem(p, 3) == "hardware":
            return f"host_{_sid(host)}_hardware", "hardware"
        return f"host_{_sid(host)}", host
    if path.startswith("modules/users/"):
        user = p[-1].replace(".nix", "")
        return f"user_{_sid(user)}", user

    if path.startswith("modules/home/"):
        if path == "modules/home/default.nix":
            return "home_common", "common"
        aspect = p[2].replace(".nix", "")
        if len(p) == 3:
            return f"home_{_sid(aspect)}", aspect
        if len(p) == 4:
            stem = _stem(p, 3)
            return (
                (f"home_{_sid(aspect)}", aspect)
                if stem == "default"
                else (f"home_{_sid(aspect)}_{_sid(stem)}", f"{aspect}/{stem}")
            )
        parent, stem = p[-2], _stem(p, -1)
        if stem == "default":
            return f"home_{_sid(aspect)}_{_sid(parent)}", f"{aspect}/{parent}"
        return f"home_{_sid(aspect)}_{_sid(parent)}_{_sid(stem)}", f"{aspect}/{parent}/{stem}"

    if path.startswith("modules/system/"):
        prefix = SYS_PREFIX.get(p[2], "sys")
        if len(p) == 4:
            stem = _stem(p, 3)
            return (prefix, stem) if stem == "default" else (f"{prefix}_{_sid(stem)}", stem)
        if len(p) == 5:
            parent, stem = p[3], _stem(p, 4)
            if stem in ("default", parent):
                return f"{prefix}_{_sid(parent)}", parent
            return f"{prefix}_{_sid(parent)}_{_sid(stem)}", f"{parent}/{stem}"
        parent, stem, sub = p[3], _stem(p, -1), p[-2]
        if stem == "default":
            return f"{prefix}_{_sid(parent)}_{_sid(sub)}", f"{parent}/{sub}"
        return f"{prefix}_{_sid(parent)}_{_sid(sub)}_{_sid(stem)}", f"{parent}/{sub}/{stem}"

    if path.startswith(("packages/", "lib/")):
        prefix = "pkg" if p[0] == "packages" else "lib"
        stem = p[-1].replace(".nix", "")
        node = f"{prefix}_{_sid(p[1])}"
        if stem != "flake":
            node = f"{node}_{_sid(stem)}"
        return node, p[1]

    name = p[-1].replace(".nix", "")
    if name == "default" and len(p) > 1:
        name = p[-2]
    return _sid(name), name

def _sid(name):
    """Sanitize to valid Mermaid ID."""
    return re.sub(r"_+", "_", re.sub(r"[^a-zA-Z0-9_]", "_", name)).strip("_") or "node"

def find_aspect_file(name, all_files):
    """Find the file defining den.aspects.<name> or home.<name>."""
    candidates = [
        f"modules/system/{cat}/{name}{suffix}"
        for cat in ("default", "optional")
        for suffix in (".nix", "/default.nix")
    ]
    candidates += [
        f"modules/system/type/{name}.nix",
        f"modules/home/{name}.nix",
        f"modules/home/{name}/default.nix",
        f"modules/hosts/{name}/default.nix",
    ]
    if name == "common":
        candidates.append("modules/home/default.nix")
    if "-" in name:
        # Hyphens can also separate path segments (llm-agent -> llm/agent).
        parent, _, child = name.rpartition("-")
        candidates += [
            f"modules/system/{cat}/{parent}/{part}.nix"
            for cat in ("default", "optional", "type")
            for part in (name, child)
        ]
        candidates += [
            f"modules/home/{parent}/{child}.nix",
            f"modules/home/{parent}/{child}/default.nix",
        ]
    for candidate in candidates:
        if candidate in all_files:
            return candidate
    return next(
        (
            f
            for f in sorted(all_files)
            if f.endswith(f"/{name}.nix") or f.endswith(f"/{name}/default.nix")
        ),
        None,
    )

def extract_aspects(content, file_path):
    """Extract den.aspects.* and home.* definitions with their includes."""
    aspects = {}
    for pattern, prefix in [
        (r"den\.aspects\.([\w-]+)\s*=\s*\{", "aspects"),
        (r"\bhome\.([\w-]+)\s*=\s*\{", "home"),
    ]:
        for m in re.finditer(pattern, content):
            name = m.group(1)
            brace_end = _match_pair(content, m.end() - 1, "{", "}")
            if brace_end == -1:
                continue
            block = content[m.end() - 1 : brace_end + 1]
            info = aspects.setdefault(
                f"{prefix}.{name}", {"includes": [], "home_refs": [], "imports": []}
            )
            for inc in re.finditer(r"den\.aspects\.([\w-]+)", block):
                if inc.group(1) != name:
                    info["includes"].append(inc.group(1))
            inc_m = re.search(r"includes\s*=\s*\[", block)
            if inc_m:
                bk = _match_pair(block, inc_m.end() - 1, "[", "]")
                if bk != -1:
                    for hm in re.finditer(
                        r"\bhome\.([\w-]+)", block[inc_m.start() : bk]
                    ):
                        info["home_refs"].append(hm.group(1))
            for rel in re.finditer(r"(?:\.\./|\./)([\w./-]+\.nix)", block):
                resolved = _resolve_rel(rel.group(0), file_path)
                if resolved:
                    info["imports"].append(resolved)
    return aspects

def extract_raw_imports(content, file_path):
    """Extract resolved paths from every ``imports = [ ... ]`` block."""
    marker = "imports = ["
    imports = set()
    pos = 0
    while (start := content.find(marker, pos)) >= 0:
        end = _match_pair(content, start + len(marker) - 1, "[", "]")
        if end == -1:
            break
        for m in re.finditer(
            r"(?:\.\./|\./)[\w./-]+", content[start + len(marker) : end]
        ):
            if m.group(0) not in ("./.", "././"):
                resolved = _resolve_rel(m.group(0), file_path)
                if resolved:
                    imports.add(resolved)
        pos = end + 1
    return imports

def get_flake_inputs():
    try:
        r = subprocess.run(
            ["nix", "flake", "metadata", "--json"],
            capture_output=True,
            text=True,
            cwd=REPO_ROOT,
        )
        if r.returncode != 0:
            return [], {}
        data = json.loads(r.stdout)
        fc = (REPO_ROOT / "flake.nix").read_text()
        external, local = set(), {}
        for name in data.get("locks", {}).get("nodes", {}):
            if name == "root":
                continue
            match = re.search(rf'{name}\.url\s*=\s*"([^"]+)"', fc) or re.search(
                rf'{name}\s*=\s*\{{[^}}]*url\s*=\s*"([^"]+)"[^}}]*\}}',
                fc,
                re.DOTALL,
            )
            if match and match.group(1).startswith(LOCAL_PREFIXES):
                local[name] = match.group(1)
            elif match or re.search(rf"^\s*{name}\s*[.{{=]", fc, re.MULTILINE):
                external.add(name)
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
            if a:
                aspect_info[rel] = a
        except Exception as e:
            print(f"⚠ Error parsing {rel}: {e}", file=sys.stderr)
    return dict(deps), aspect_info, all_files

#: Theme: input blue, local amber, core cyan, hosts teal, users violet, aspects
#: as light steel cards, hardware neutral slate. Every label clears 4.5:1 on
#: its fill and every fill clears 3:1 on both GitHub canvases.
STYLES = {
    "input": "fill:#2563eb,stroke:#60a5fa,stroke-width:1px,color:#ffffff",
    "local": "fill:#b45309,stroke:#fbbf24,stroke-width:1px,color:#ffffff",
    "flake": "fill:#0e7490,stroke:#22d3ee,stroke-width:1.5px,color:#ecfeff",
    "hosts": "fill:#0f766e,stroke:#2dd4bf,stroke-width:1px,color:#f0fdfa",
    "users": "fill:#7c3aed,stroke:#a78bfa,stroke-width:1px,color:#f5f3ff",
    "aspect": "fill:#e9eff6,stroke:#5a7086,stroke-width:1.5px,color:#1f2328",
    "config": "fill:#64748b,stroke:#cbd5e1,stroke-width:1px,color:#ffffff",
}

#: One neutral clears 4:1 on both canvases. GitHub ignores subgraph textColor,
#: so clusterLabelColor and titleColor are both set; cluster backgrounds stay
#: transparent so the page background shows through.
INIT = (
    "%%{init: {",
    "  'theme': 'base',",
    "  'themeVariables': {",
    "    'fontSize': '14px',",
    "    'fontFamily': 'system-ui',",
    "    'lineColor': '#6e7681',",
    "    'textColor': '#6e7681',",
    "    'titleColor': '#6e7681',",
    "    'clusterLabelColor': '#6e7681',",
    "    'clusterBkg': 'transparent',",
    "    'clusterBorder': '#7d8590'",
    "  },",
    "  'flowchart': {",
    "    'nodeSpacing': 3,",
    "    'rankSpacing': 40,",
    "    'padding': 2,",
    "    'diagramPadding': 3",
    "  }",
    "}}%%",
)

def generate_mermaid(deps, aspect_info, all_files):
    lines = ["```mermaid", *INIT, "", "flowchart LR", "", "    %% Styles"]
    lines += [f"    classDef {cls} {defn}" for cls, defn in STYLES.items()]
    lines.append("")

    def subgraph(title, nodes):
        lines.append(f"    subgraph {title}")
        lines.extend(f'        {nid}["{label}"]:::{cls}' for nid, label, cls in nodes)
        lines.extend(["    end", ""])

    hosts, host_hw, users, sys_aspects, home_aspects = set(), {}, set(), set(), set()
    for path in sorted(all_files):
        parts = path.split("/")
        if path.startswith("modules/hosts/") and len(parts) >= 3:
            hosts.add(parts[2])
            if len(parts) >= 4 and parts[3] == "_hardware-configuration.nix":
                host_hw[parts[2]] = path
        elif path.startswith("modules/users/") and not path.endswith("/default.nix"):
            users.add(parts[-1].replace(".nix", ""))
        elif path.startswith("modules/system/"):
            sys_aspects.add(path)
        elif path.startswith("modules/home/") and not path.endswith("namespace.nix"):
            home_aspects.add(path)

    host_nodes = []
    for h in sorted(hosts):
        host_nodes.append((f"host_{_sid(h)}", h, "hosts"))
        if h in host_hw:
            host_nodes.append((f"host_{_sid(h)}_hardware", "hardware", "config"))

    ext_inputs, local_inputs = get_flake_inputs()
    groups = [
        (
            "Inputs[Inputs]",
            [(f"input_{_sid(n)}", n, "input") for n in ext_inputs]
            + [
                (f"local_{_sid(n)}", _local_label(p), "local")
                for n, p in sorted(local_inputs.items())
            ],
        ),
        ("Core[Core]", [("flake", "flake", "flake"), ("den", "den", "flake")]),
        (
            "SystemAspects[System Aspects]",
            [(*node_id_and_label(p), "aspect") for p in sorted(sys_aspects)],
        ),
        (
            "HomeAspects[Home Namespace Aspects]",
            [(*node_id_and_label(p), "aspect") for p in sorted(home_aspects)],
        ),
        ("Hosts[Hosts]", host_nodes),
        ("Users[Users]", [(f"user_{_sid(u)}", u, "users") for u in sorted(users)]),
    ]
    for title, nodes in groups:
        subgraph(title, nodes)
    edges = {(f"input_{_sid(n)}", "flake") for n in ext_inputs}
    edges |= {(f"local_{_sid(n)}", "flake") for n in sorted(local_inputs)}
    edges.add(("flake", "den"))

    # den.nix -> baseline aspects + hosts + users
    den_path = REPO_ROOT / "modules" / "den.nix"
    try:
        den_content = den_path.read_text()
    except OSError:
        den_content = ""
    for m in re.finditer(r"den\.aspects\.([\w-]+)", den_content):
        target = find_aspect_file(m.group(1), all_files)
        if target:
            edges.add(("den", node_id_and_label(target)[0]))
    for h in sorted(hosts):
        target = find_aspect_file(h, all_files)
        if target:
            edges.add(("den", node_id_and_label(target)[0]))
    for u in sorted(users):
        uf = f"modules/users/{u}.nix"
        if uf in all_files:
            edges.add(("den", node_id_and_label(uf)[0]))

    # Aspect includes, home refs and resolved imports
    for path, aspects in aspect_info.items():
        src = node_id_and_label(path)[0]
        for info in aspects.values():
            for key in ("includes", "home_refs"):
                for name in info[key]:
                    target = find_aspect_file(name, all_files)
                    if target:
                        edges.add((src, node_id_and_label(target)[0]))
            for imp in info["imports"]:
                if imp in all_files:
                    edges.add((src, node_id_and_label(imp)[0]))

    # Raw import edges
    def skipped(path):
        return path.startswith(("packages/", "lib/")) or path.endswith("namespace.nix")

    for src_path in sorted(deps):
        if skipped(src_path):
            continue
        src_id = node_id_and_label(src_path)[0]
        for tgt_path in sorted(deps[src_path]):
            if tgt_path in all_files and not skipped(tgt_path):
                edges.add((src_id, node_id_and_label(tgt_path)[0]))

    lines.append("")
    lines += [f"    {s} --> {t}" for s, t in sorted(edges)]
    lines += ["", "```"]
    return "\n".join(lines)

def update_readme(content):
    if not README_PATH.exists():
        return
    txt = README_PATH.read_text()
    s, e = txt.find(DEPS_START), txt.find(DEPS_END)
    if s == -1 or e == -1:
        return
    updated = txt[: s + len(DEPS_START)] + "\n" + content + "\n" + txt[e:]
    if updated == txt:
        return
    README_PATH.write_text(updated)
    print("✓ Updated README.md", file=sys.stderr)

def export_diagram(mermaid, output):
    """Export mermaid diagram to file. Format determined by output extension (pdf, png, svg)."""
    mmdc = shutil.which("mmdc")
    if not mmdc:
        print(
            f"⚠ mmdc not found, skipping {output.suffix.lstrip('.')} export",
            file=sys.stderr,
        )
        return

    content = mermaid.removeprefix("```mermaid\n").removesuffix("\n```\n").removesuffix("```")
    with tempfile.NamedTemporaryFile(mode="w", suffix=".mmd", delete=False) as handle:
        handle.write(content)
        tmp = handle.name
    try:
        cmd = [mmdc, "-i", tmp, "-o", str(output), "-b", "white", "-s", "4", "-w", "4096"]
        if output.suffix == ".pdf":
            cmd.append("-f")
        r = subprocess.run(cmd, capture_output=True, text=True)
        if r.returncode != 0:
            print(
                f"⚠ {output.suffix.lstrip('.').upper()} export failed: {r.stderr}",
                file=sys.stderr,
            )
        else:
            print(f"✓ Exported {output}", file=sys.stderr)
    finally:
        Path(tmp).unlink(missing_ok=True)

def main():
    print("Building dependency graph...", file=sys.stderr)
    deps, aspect_info, all_files = build_graph()
    print(
        f"Found {len(all_files)} files, {sum(len(v) for v in deps.values())} imports, "
        f"{len(aspect_info)} aspect definitions",
        file=sys.stderr,
    )

    mermaid = generate_mermaid(deps, aspect_info, all_files)
    update_readme(mermaid)

    out = GENERATED_DIR / f"flake-graph_{datetime.now(timezone.utc):%Y%m%d_%H%M%S}"
    out.mkdir(parents=True, exist_ok=True)
    diagram = out / "infrastructure-flake-graph.md"
    diagram.write_text(mermaid)
    print(f"✓ Saved {diagram}", file=sys.stderr)
    export_diagram(mermaid, out / "infrastructure-flake-graph.pdf")

if __name__ == "__main__":
    main()
