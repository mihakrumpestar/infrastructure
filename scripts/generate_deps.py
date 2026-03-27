#!/usr/bin/env python3
"""
Nix Configuration Dependency Graph Generator

Parses all Nix files to build a dependency graph and outputs
an interactive Mermaid diagram for README.md.

Usage:
    task generate-deps
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
from typing import Dict, List, Set, Tuple

REPO_ROOT = Path(__file__).parent.parent
README_PATH = REPO_ROOT / "README.md"
GENERATED_DIR = REPO_ROOT / "generated"
DEPS_START_MARKER = "<!-- DEPS_START -->"
DEPS_END_MARKER = "<!-- DEPS_END -->"

EXCLUDE_DIRS = {
    ".git",
    "result",
    "generated",
    ".venv",
    ".devbox",
    "infrastructure-secrets",
    "node_modules",
    "devbox.d",
    "bin",
    "pkg",
    "docs",
}


def find_all_nix_files() -> List[Path]:
    """Find all .nix, .json, .jsonc files in the repo."""
    files = []
    for root, dirs, files_in_dir in os.walk(REPO_ROOT):
        dirs[:] = [d for d in dirs if d not in EXCLUDE_DIRS]
        for f in files_in_dir:
            if f.endswith((".nix", ".json", ".jsonc")) and f not in (
                "devbox.json",
                "devbox.lock",
            ):
                files.append(Path(root) / f)
    return sorted(files)


def resolve_import(import_path: str, current_file: Path) -> Set[str]:
    """Resolve an import path to its actual file paths."""
    resolved = set()
    current_dir = current_file.parent
    parts = import_path.strip('"').strip("'").rstrip("/").split("/")
    path = current_dir

    for part in parts:
        if part == ".":
            pass
        elif part == "..":
            path = path.parent
        else:
            path = path / part

    path = path.resolve()

    if path.is_file():
        resolved.add(str(path.relative_to(REPO_ROOT)))
    elif path.is_dir():
        default_nix = path / "default.nix"
        if default_nix.exists():
            resolved.add(str(default_nix.relative_to(REPO_ROOT)))
    elif path.suffix == "":
        for ext in (".nix", ".json", ".jsonc"):
            candidate = path.with_suffix(ext)
            if candidate.exists():
                resolved.add(str(candidate.relative_to(REPO_ROOT)))
                break

    return resolved


def find_matching_bracket(text: str, start: int) -> int:
    """Find matching closing bracket for [...]. Returns -1 if not found."""
    depth = 0
    for i in range(start, len(text)):
        if text[i] == "[":
            depth += 1
        elif text[i] == "]":
            depth -= 1
            if depth == 0:
                return i
    return -1


def find_matching_brace(text: str, start: int) -> int:
    """Find matching closing brace for {...}. Returns -1 if not found."""
    depth = 0
    for i in range(start, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return i
    return -1


def is_inside_home_manager_users(text: str, pos: int) -> bool:
    """Check if position is inside home-manager.users block."""
    hm_match = re.search(r"home-manager\.users\s*=", text[:pos])
    if hm_match:
        brace_start = text.find("{", hm_match.end())
        if brace_start != -1:
            brace_end = find_matching_brace(text, brace_start)
            if brace_end != -1 and pos < brace_end:
                return True
    return False


def resolve_dynamic_pattern(pattern: str, base_dir: Path) -> List[str]:
    """Resolve dynamic patterns like ./${username}/system to actual paths."""
    paths = []
    var_match = re.search(r"\$\{(\w+)\}", pattern)
    if not var_match:
        return paths

    var = var_match.group(1)
    if not base_dir.exists():
        return paths

    for subdir in sorted(base_dir.iterdir()):
        if not subdir.is_dir() or subdir.name.startswith("."):
            continue
        if subdir.name == "default.nix":
            continue

        resolved = pattern.replace(f"${{{var}}}", subdir.name).lstrip("/")
        candidate = base_dir / subdir.name / resolved

        if candidate.exists():
            if candidate.is_dir() and (candidate / "default.nix").exists():
                paths.append(
                    f"./{subdir.name}/{resolved}/default.nix".replace("//", "/")
                )
            else:
                paths.append(f"./{subdir.name}/{resolved}")

    return paths


def extract_imports(content: str, file_path: Path) -> Tuple[List[str], List[str]]:
    """Extract import paths from Nix file content.

    Returns: (regular_imports, nested_imports)
    """
    regular_imports = []
    nested_imports = []
    current_dir = file_path.parent

    # Handle imports = map (var: (./. + "/${var}/path")) ...
    map_pattern = (
        r"imports\s*=\s*map\s*\(\s*\w+\s*:\s*\(\s*\./\.\s*\+\s*\"(/[^\"]+)\"\s*\)\s*\)"
    )
    for match in re.finditer(map_pattern, content):
        pattern = match.group(1)
        is_nested = is_inside_home_manager_users(content, match.start())
        for path in resolve_dynamic_pattern(pattern, current_dir):
            (nested_imports if is_nested else regular_imports).append(path)

    # Handle imports = [(./. + "/${username}/home")] inside home-manager.users
    single_pattern = r"imports\s*=\s*\[\s*\(\s*\./\.\s*\+\s*\"(/[^\"]+)\"\s*\)\s*\]"
    for match in re.finditer(single_pattern, content):
        pattern = match.group(1)
        is_nested = is_inside_home_manager_users(content, match.start())
        for path in resolve_dynamic_pattern(pattern, current_dir):
            (nested_imports if is_nested else regular_imports).append(path)

    # Handle imports = [ ... ] blocks
    pos = 0
    while True:
        import_start = content.find("imports = [", pos)
        if import_start < 0:
            break

        bracket_end = find_matching_bracket(
            content, import_start + len("imports = [") - 1
        )
        if bracket_end == -1:
            break

        import_content = content[import_start + len("imports = [") : bracket_end]
        is_nested = is_inside_home_manager_users(content, import_start)

        # Match static paths ./path or ../path
        for match in re.finditer(r"(?:\.\./|\./)[\w./-]+", import_content):
            path = match.group(0)
            if path not in ("./.", "././"):
                (nested_imports if is_nested else regular_imports).append(path)

        # Match dynamic patterns (./. + "/${var}/path")
        for match in re.finditer(r"\./\.\s*\+\s*\"(/[^\"]+)\"", import_content):
            pattern = match.group(1)
            for path in resolve_dynamic_pattern(pattern, current_dir):
                (nested_imports if is_nested else regular_imports).append(path)

        pos = bracket_end + 1

    # Handle dynamic imports with variables like ./${hostName}/configuration.nix
    for match in re.finditer(r"\./\$\{[^}]+\}/([\w/-]+\.nix)", content):
        pattern = match.group(1)
        for subdir in sorted(current_dir.iterdir()):
            if subdir.is_dir() and not subdir.name.startswith("."):
                candidate = subdir / pattern
                if candidate.exists():
                    regular_imports.append(f"./{subdir.name}/{pattern}")

    return list(set(regular_imports)), list(set(nested_imports))


def build_dependency_graph() -> Tuple[Dict[str, Set[str]], Set[str]]:
    """Build dependency graph from all Nix files."""
    nix_files = find_all_nix_files()
    dependencies = defaultdict(set)
    all_files = set()

    for nix_file in nix_files:
        rel_path = str(nix_file.relative_to(REPO_ROOT))
        all_files.add(rel_path)

        try:
            content = nix_file.read_text()
            regular_imports, nested_imports = extract_imports(content, nix_file)
            for imp in regular_imports + nested_imports:
                dependencies[rel_path].update(resolve_import(imp, nix_file))
        except Exception as e:
            print(f"⚠ Error parsing {rel_path}: {e}", file=sys.stderr)

    return dict(dependencies), all_files


def get_mermaid_node_id(path: str) -> str:
    """Convert path to valid Mermaid node ID for edges (preserves .nix as _nix)."""
    return path.replace("/", "__").replace(".", "_").replace("-", "_")


def get_flake_inputs() -> Tuple[List[str], Dict[str, str]]:
    """Get flake inputs using nix flake metadata."""
    try:
        result = subprocess.run(
            ["nix", "flake", "metadata", "--json"],
            capture_output=True,
            text=True,
            cwd=REPO_ROOT,
        )
        if result.returncode != 0:
            print(f"⚠ Failed to get flake metadata: {result.stderr}", file=sys.stderr)
            return [], {}

        data = json.loads(result.stdout)
        flake_content = (REPO_ROOT / "flake.nix").read_text()
        external = []
        local = {}

        for name, node in data.get("locks", {}).get("nodes", {}).items():
            if name == "root":
                continue

            url = None
            # Try inline format: name.url = "..."
            inline_match = re.search(rf'{name}\.url\s*=\s*"([^"]+)"', flake_content)
            if inline_match:
                url = inline_match.group(1)
            else:
                # Try block format: name = { ... url = "..." ... }
                block_match = re.search(
                    rf'{name}\s*=\s*\{{[^}}]*url\s*=\s*"([^"]+)"[^}}]*\}}',
                    flake_content,
                    re.DOTALL,
                )
                if block_match:
                    url = block_match.group(1)

            if url:
                if url.startswith("./"):
                    local[name] = url
                elif name not in external:
                    external.append(name)
            elif name not in external and re.search(
                rf"^\s*{name}\s*[.{{=]", flake_content, re.MULTILINE
            ):
                external.append(name)

        return sorted(external), local

    except Exception as e:
        print(f"⚠ Error getting flake inputs: {e}", file=sys.stderr)
        return [], {}


def generate_mermaid_graph(
    dependencies: Dict[str, Set[str]], all_files: Set[str]
) -> str:
    """Generate Mermaid diagram showing import dependencies with PHD styling."""
    lines = ["```mermaid"]
    lines.append("%%{init: {")
    lines.append("  'theme': 'base',")
    lines.append("  'themeVariables': {")
    lines.append("    'fontSize': '14px',")
    lines.append("    'fontFamily': 'system-ui',")
    lines.append("    'lineColor': '#888'")
    lines.append("  },")
    lines.append("  'flowchart': {")
    lines.append("    'nodeSpacing': 3,")
    lines.append("    'rankSpacing': 40,")
    lines.append("    'padding': 2,")
    lines.append("    'diagramPadding': 3")
    lines.append("  }")
    lines.append("}}%%")
    lines.append("")
    lines.append("flowchart TD")
    lines.append("")

    # Collect hosts and users
    hosts = set()
    users = set()
    for path in all_files:
        parts = path.split("/")
        if len(parts) >= 3 and parts[0] == "hosts":
            hosts.add(parts[1])
        if len(parts) >= 4 and parts[0] == "homeManagerModules" and parts[1] == "users":
            users.add(parts[2])

    # Get flake inputs
    external_inputs, local_inputs = get_flake_inputs()
    sorted_hosts = sorted(hosts)
    sorted_users = sorted(users)

    # Define CSS classes
    lines.append("    %% Styles")
    lines.append(
        "    classDef input fill:#e3f2fd,stroke:#1565c0,stroke-width:1px,color:#1565c0"
    )
    lines.append(
        "    classDef local fill:#fff8e1,stroke:#ef6c00,stroke-width:1px,color:#e65100"
    )
    lines.append(
        "    classDef flake fill:#f3e5f5,stroke:#7b1fa2,stroke-width:1.5px,color:#7b1fa2"
    )
    lines.append(
        "    classDef hosts fill:#e8f5e9,stroke:#388e3c,stroke-width:1px,color:#2e7d32"
    )
    lines.append(
        "    classDef users fill:#fce4ec,stroke:#c2185b,stroke-width:1px,color:#ad1457"
    )
    lines.append(
        "    classDef modules fill:#fff8e1,stroke:#f57c00,stroke-width:1px,color:#e65100"
    )
    lines.append(
        "    classDef config fill:#fafafa,stroke:#757575,stroke-width:0.5px,color:#424242"
    )
    lines.append("")

    # Subgraph: Inputs
    lines.append("    subgraph Inputs[Inputs]")
    for inp in external_inputs:
        lines.append(f'        input_{inp.replace("-", "_")}["{inp}"]:::input')
    for name, path in sorted(local_inputs.items()):
        short_path = path.replace("./packages/", "").replace("./home-modules/", "")
        lines.append(f'        local_{name.replace("-", "_")}["{short_path}"]:::local')
    lines.append("    end")
    lines.append("")

    # Subgraph: Core
    lines.append("    subgraph Core[Core]")
    lines.append('        flake["flake.nix"]:::flake')
    lines.append("    end")
    lines.append("")

    # Subgraph: Hosts
    lines.append("    subgraph Hosts[Hosts]")
    lines.append('        hosts_node["hosts"]:::hosts')
    for host in sorted_hosts:
        lines.append(f'        host_{host.replace("-", "_")}["{host}"]:::hosts')
    lines.append("    end")
    lines.append("")

    # Subgraph: Users
    lines.append("    subgraph Users[Users]")
    lines.append('        users_node["users"]:::users')
    for user in sorted_users:
        lines.append(f'        user_{user.replace("-", "_")}["{user}"]:::users')
    lines.append("    end")
    lines.append("")

    # Subgraph: Modules
    lines.append("    subgraph Modules[Modules]")
    files_with_deps = {
        f
        for f in (set(dependencies.keys()) | set().union(*dependencies.values()))
        if f in all_files
        and f.endswith(".nix")
        and not f.startswith(
            ("packages/", "home-modules/", "hosts/", "homeManagerModules/users/")
        )
        and f not in ("flake.nix", "default.nix")
    }

    for path in sorted(files_with_deps):
        name = path.split("/")[-1].replace(".nix", "")
        if name == "default":
            name = path.split("/")[-2] if len(path.split("/")) > 1 else "default"
        lines.append(f'        {get_mermaid_node_id(path)}["{name}"]:::modules')
    lines.append("    end")
    lines.append("")

    # Subgraph: Host configs
    lines.append("    subgraph HostConfigs[Host Configs]")
    for host in sorted_hosts:
        for path in sorted(all_files):
            if path.startswith(f"hosts/{host}/") and path.endswith(".nix"):
                filename = path.split("/")[-1].replace(".nix", "")
                label = (
                    "config"
                    if filename == "configuration"
                    else "hw"
                    if filename == "hardware-configuration"
                    else filename
                )
                lines.append(f'        {get_mermaid_node_id(path)}["{label}"]:::config')
    lines.append("    end")
    lines.append("")

    # Subgraph: User configs
    lines.append("    subgraph UserConfigs[User Configs]")
    for user in sorted_users:
        for path in sorted(all_files):
            if (
                path.startswith(f"homeManagerModules/users/{user}/")
                and path.endswith(".nix")
                and path != f"homeManagerModules/users/{user}/default.nix"
            ):
                parts = path[len(f"homeManagerModules/users/{user}/") :].split("/")
                if len(parts) >= 2:
                    category, filename = parts[0], parts[-1].replace(".nix", "")
                    if len(parts) == 2 and filename == "default":
                        label = category
                    elif len(parts) == 2:
                        label = filename
                    elif parts[-1] == "default.nix":
                        label = parts[-2]
                    else:
                        label = f"{parts[-2]}/{filename}"
                    lines.append(
                        f'        {get_mermaid_node_id(path)}["{label}"]:::config'
                    )
    lines.append("    end")
    lines.append("")

    # Edges from inputs to flake
    for inp in external_inputs:
        lines.append(f"    input_{inp.replace('-', '_')} --> flake")
    for name in sorted(local_inputs):
        lines.append(f"    local_{name.replace('-', '_')} --> flake")

    # flake connects to hosts, users, and modules
    lines.append("    flake --> hosts_node")
    lines.append("    flake --> users_node")
    if "nixosModules/default.nix" in all_files:
        lines.append("    flake --> nixosModules__default_nix")
    if "homeManagerModules/default.nix" in all_files:
        lines.append("    flake --> homeManagerModules__default_nix")

    # Hosts hierarchy
    for host in sorted_hosts:
        lines.append(f"    hosts_node --> host_{host.replace('-', '_')}")
    for user in sorted_users:
        lines.append(f"    users_node --> user_{user.replace('-', '_')}")

    # Host configs
    for host in sorted_hosts:
        host_id = f"host_{host.replace('-', '_')}"
        for path in sorted(all_files):
            if path.startswith(f"hosts/{host}/") and path.endswith(".nix"):
                lines.append(f"    {host_id} --> {get_mermaid_node_id(path)}")

    # User configs
    for user in sorted_users:
        user_id = f"user_{user.replace('-', '_')}"
        for config_type in ("system", "home"):
            config_path = f"homeManagerModules/users/{user}/{config_type}/default.nix"
            if config_path in all_files:
                lines.append(f"    {user_id} --> {get_mermaid_node_id(config_path)}")

    lines.append("")

    # Import edges
    for src in sorted(dependencies):
        if src in ("flake.nix", "default.nix") or not src.endswith(".nix"):
            continue
        if src.startswith(("hosts/", "homeManagerModules/users/")):
            continue
        for tgt in sorted(dependencies[src]):
            if tgt in ("flake.nix", "default.nix") or not tgt.endswith(".nix"):
                continue
            if tgt.startswith(
                ("packages/", "home-modules/", "hosts/", "homeManagerModules/users/")
            ):
                continue
            lines.append(
                f"    {get_mermaid_node_id(src)} --> {get_mermaid_node_id(tgt)}"
            )

    # User home config imports
    for user in sorted_users:
        home_path = f"homeManagerModules/users/{user}/home/default.nix"
        if home_path in dependencies:
            for tgt in sorted(dependencies[home_path]):
                if tgt.startswith("homeManagerModules/users/"):
                    lines.append(
                        f"    {get_mermaid_node_id(home_path)} --> {get_mermaid_node_id(tgt)}"
                    )

    lines.append("")
    lines.append("```")
    return "\n".join(lines)


def update_readme(mermaid_content: str):
    """Update the dependency graph section in README.md."""
    if not README_PATH.exists():
        print(f"⚠ README.md not found at {README_PATH}", file=sys.stderr)
        return

    readme_content = README_PATH.read_text()
    start_idx = readme_content.find(DEPS_START_MARKER)
    end_idx = readme_content.find(DEPS_END_MARKER)

    if start_idx == -1 or end_idx == -1:
        print("⚠ Could not find deps markers in README.md", file=sys.stderr)
        return

    new_readme = (
        readme_content[: start_idx + len(DEPS_START_MARKER)]
        + "\n"
        + mermaid_content
        + "\n"
        + readme_content[end_idx:]
    )
    README_PATH.write_text(new_readme)
    print("✓ Updated README.md with dependency graph", file=sys.stderr)


def find_mmdc() -> str:
    """Find mmdc executable."""
    if mmdc := shutil.which("mmdc"):
        return mmdc

    for profile in (
        REPO_ROOT / ".devbox" / "nix" / "profile" / "default" / "bin" / "mmdc",
        Path.home() / ".devbox" / "nix" / "profile" / "default" / "bin" / "mmdc",
    ):
        if profile.exists():
            return str(profile)
    return None


def export_mermaid_to_png(mermaid_content: str, output_path: Path):
    """Export Mermaid diagram to PNG."""
    mmdc = find_mmdc()
    if not mmdc:
        print("⚠ mmdc not found, skipping PNG export", file=sys.stderr)
        print("  Run: devbox install", file=sys.stderr)
        return

    # Strip mermaid code block markers
    content = mermaid_content
    if content.startswith("```mermaid"):
        content = content.split("\n", 1)[1]
    for ending in ("\n```\n", "```\n"):
        if content.endswith(ending):
            content = content.rsplit(ending, 1)[0]
            break
    if content.rstrip().endswith("```"):
        content = content.rsplit("```", 1)[0].rstrip()

    with tempfile.NamedTemporaryFile(mode="w", suffix=".mmd", delete=False) as f:
        f.write(content)
        temp_path = f.name

    try:
        result = subprocess.run(
            [mmdc, "-i", temp_path, "-o", str(output_path), "-b", "white", "-s", "32"],
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            print(f"⚠ Failed to export PNG:", file=sys.stderr)
            print(f"  stderr: {result.stderr}", file=sys.stderr)
        else:
            print(f"✓ Exported PNG to {output_path}", file=sys.stderr)
    finally:
        Path(temp_path).unlink(missing_ok=True)


def main():
    """Main entry point."""
    print("Building dependency graph...", file=sys.stderr)

    dependencies, all_files = build_dependency_graph()
    print(f"Found {len(all_files)} files", file=sys.stderr)
    print(
        f"Found {sum(len(v) for v in dependencies.values())} dependencies",
        file=sys.stderr,
    )

    mermaid_content = generate_mermaid_graph(dependencies, all_files)
    update_readme(mermaid_content)

    # Create timestamped output
    output_dir = GENERATED_DIR / f"deps_{datetime.now():%Y%m%d_%H%M%S}"
    output_dir.mkdir(parents=True, exist_ok=True)

    (output_dir / "dependencies.md").write_text(mermaid_content)
    print(f"✓ Saved {output_dir / 'dependencies.md'}", file=sys.stderr)

    export_mermaid_to_png(mermaid_content, output_dir / "dependencies.png")


if __name__ == "__main__":
    main()
