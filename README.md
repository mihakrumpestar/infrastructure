# Infrastructure

NixOS configuration repository for managing multiple hosts using flakes.

## Repository Structure

```sh
├── flake.nix               # Flake entry point
├── modules/
│   ├── den.nix             # Den framework: host declarations & aspect composition
│   ├── hosts/              # Per-host configurations & hardware configs
│   ├── users/              # User account definitions
│   ├── system/
│   │   ├── default/        # Baseline system aspects (core, disks, nix, networking, …)
│   │   ├── optional/       # Optional system aspects (plasma, containers, nvidia, …)
│   │   └── type/           # Host type aspects (client, server, vm-guest)
│   └── home/               # Home-manager aspects (git, ide, browser, scripts, …)
├── packages/               # Custom package flakes (consul-cni, virtualhere)
├── lib/                    # Standalone library/module flakes (mutable-file)
├── scripts/                # Utility scripts (generate_stats.py, flake_graph.py)
└── docs/                   # Documentation
```

## Hardware-config

Generate using (on remote):

```sh
nixos-generate-config --show-hardware-config
```

## TPM2 encryption key

Generate per machine TPM2 age key:

```sh
nix-shell -p age-plugin-tpm --command "sudo age-plugin-tpm -g"
```

## Stress test

Stress test:

```sh
nix-shell -p btop --command "btop"
nix-shell -p stress s-tui --command "s-tui"
```

## Build Statistics

<!-- STATS_START -->

commit hash: d18b9ee072a10035bbf34898d4f0cc869d3f7bde

nix (Nix) 2.34.7


## Lines of Code

**Table 1:** Non-blank lines across the flake's source tree.

LOC excludes blank lines but includes comments. All file types are counted
(`.nix`, `.json`, `.jsonc`, `.sh`, `.ini`, etc.) except Markdown (`.md`).

| Component        |   Lines |
|:-----------------|--------:|
| flake.nix        |      87 |
| modules/den.nix  |      95 |
| modules/hosts    |     421 |
| modules/system   |    2336 |
| modules/home     |    2521 |
| modules/users    |     182 |
| modules (total)  |    5555 |
| packages (total) |     293 |
| lib (total)      |      97 |
| **Total**        |    6032 |

## NixOS Configuration Sizes

**Table 2:** NixOS system configuration sizes for each host.

This table presents the closure size (total disk space required for all dependencies)
for each configured host in the infrastructure. Closure size is measured in GiB
(gibibytes, 2³⁰ bytes) and represents the complete set of packages, libraries,
and system components required for each configuration. System/Home Pkgs shows
the count of packages in each profile (excluding -doc, -man, -info, -dev, -bin outputs).
System/Home Refs shows the total recursive dependencies for each profile.

|                 Host |   Closure Size |   System Pkgs |   Home Pkgs |   System Refs |   Home Refs |
|---------------------:|---------------:|--------------:|------------:|--------------:|------------:|
|                kiosk |       9.78 GiB |          1422 |         461 |          2135 |         510 |
|      personal-laptop |      35.96 GiB |          6251 |        5541 |          8293 |        6886 |
|      personal-vps-02 |       3.25 GiB |           663 |           - |          1168 |           - |
| personal-workstation |      36.92 GiB |          6301 |        5541 |          8366 |        6887 |
|            server-01 |       5.02 GiB |           697 |           - |          1236 |           - |
|            server-03 |       5.03 GiB |           697 |           - |          1231 |           - |

## Eval Performance

**Statistics computed over 1 run(s)**

### Sequential

**Table 3:** Evaluation time per host with no concurrent evaluation.

Each host is evaluated in isolation using `nix eval --option eval-cache false` to ensure deterministic, cache-free measurements.

|                 Host |    Mean |   Median |   Std Dev |     Min |     Max |   Runs |
|---------------------:|--------:|---------:|----------:|--------:|--------:|-------:|
|                kiosk | 11.524s |  11.524s |    0.000s | 11.524s | 11.524s |      1 |
|      personal-laptop | 17.050s |  17.050s |    0.000s | 17.050s | 17.050s |      1 |
|      personal-vps-02 |  7.777s |   7.777s |    0.000s |  7.777s |  7.777s |      1 |
| personal-workstation | 17.170s |  17.170s |    0.000s | 17.170s | 17.170s |      1 |
|            server-01 |  9.094s |   9.094s |    0.000s |  9.094s |  9.094s |      1 |
|            server-03 |  9.110s |   9.110s |    0.000s |  9.110s |  9.110s |      1 |

### Simultaneous

**Table 4:** Evaluation time per host with all hosts evaluated concurrently.

All hosts are evaluated in parallel to measure the overhead of concurrent Nix evaluation (CPU contention, lock contention, etc.).

|                 Host |    Mean |   Median |   Std Dev |     Min |     Max |   Runs |
|---------------------:|--------:|---------:|----------:|--------:|--------:|-------:|
|                kiosk | 21.887s |  21.887s |    0.000s | 21.887s | 21.887s |      1 |
|      personal-laptop | 28.352s |  28.352s |    0.000s | 28.352s | 28.352s |      1 |
|      personal-vps-02 | 17.149s |  17.149s |    0.000s | 17.149s | 17.149s |      1 |
| personal-workstation | 28.361s |  28.361s |    0.000s | 28.361s | 28.361s |      1 |
|            server-01 | 19.190s |  19.190s |    0.000s | 19.190s | 19.190s |      1 |
|            server-03 | 19.192s |  19.192s |    0.000s | 19.192s | 19.192s |      1 |

## Closure Reuse Matrix

**Table 5:** Binary-level dependency sharing between host configurations.

This matrix quantifies the degree of dependency reuse across different NixOS host
configurations. Each cell shows the percentage of packages (derivations) from the
row host's closure that also appear in the column host's closure. A value of 100%
would indicate complete subsumption. The diagonal shows dashes (-) as self-comparison
is omitted. Higher percentages indicate greater infrastructure consolidation potential
through shared package caches and common dependency management.

|                 Host |   kiosk |   personal-laptop |   personal-vps-02 |   personal-workstation |   server-01 |   server-03 |
|---------------------:|--------:|------------------:|------------------:|-----------------------:|------------:|------------:|
|                kiosk |       - |               94% |               47% |                    94% |         49% |         49% |
|      personal-laptop |     24% |                 - |               12% |                    99% |         12% |         13% |
|      personal-vps-02 |     86% |               86% |                 - |                    86% |         92% |         92% |
| personal-workstation |     24% |               98% |               12% |                      - |         12% |         12% |
|            server-01 |     85% |               86% |               87% |                    86% |           - |         95% |
|            server-03 |     85% |               87% |               87% |                    87% |         95% |           - |<!-- STATS_END -->

## Dependency Graph

<!-- DEPS_START -->
```mermaid
%%{init: {
  'theme': 'base',
  'themeVariables': {
    'fontSize': '14px',
    'fontFamily': 'system-ui',
    'lineColor': '#888'
  },
  'flowchart': {
    'nodeSpacing': 3,
    'rankSpacing': 40,
    'padding': 2,
    'diagramPadding': 3
  }
}}%%

flowchart LR

    %% Styles
    classDef input fill:#e0f7fa,stroke:#00838f,stroke-width:1px,color:#006064
    classDef local fill:#efebe9,stroke:#6d4c41,stroke-width:1px,color:#4e342e
    classDef flake fill:#f3e5f5,stroke:#7b1fa2,stroke-width:1.5px,color:#7b1fa2
    classDef hosts fill:#e8f5e9,stroke:#388e3c,stroke-width:1px,color:#2e7d32
    classDef users fill:#fce4ec,stroke:#c2185b,stroke-width:1px,color:#ad1457
    classDef aspect fill:#e3f2fd,stroke:#1565c0,stroke-width:1px,color:#1565c0
    classDef config fill:#fafafa,stroke:#757575,stroke-width:0.5px,color:#424242

    subgraph Inputs[Inputs]
        input_agenix["agenix"]:::input
        input_agenix_rekey["agenix-rekey"]:::input
        input_den["den"]:::input
        input_disko["disko"]:::input
        input_home_manager["home-manager"]:::input
        input_impermanence["impermanence"]:::input
        input_import_tree["import-tree"]:::input
        input_infrastructure_secrets["infrastructure-secrets"]:::input
        input_lanzaboote["lanzaboote"]:::input
        input_mattpocock_skills["mattpocock-skills"]:::input
        input_nix_index_database["nix-index-database"]:::input
        input_nix_vscode_extensions["nix-vscode-extensions"]:::input
        input_nixpkgs["nixpkgs"]:::input
        input_nur["nur"]:::input
        input_plasma_manager["plasma-manager"]:::input
        input_stylix["stylix"]:::input
        input_tix["tix"]:::input
        local_consul_cni["packages/consul-cni"]:::local
        local_mutable_file["lib/mutable-file"]:::local
        local_virtualhere["packages/virtualhere"]:::local
    end

    subgraph Core[Core]
        flake["flake"]:::flake
        den["den"]:::flake
    end

    subgraph SystemAspects[System Aspects]
        sys_core["core"]:::aspect
        sys_disks["disks"]:::aspect
        sys_impermanence["impermanence"]:::aspect
        sys_locale["locale"]:::aspect
        sys_networking["networking"]:::aspect
        sys_nix["nix"]:::aspect
        sys_secrets["secrets"]:::aspect
        sys_shell["shell"]:::aspect
        sys_shell_fonts["shell/fonts"]:::aspect
        sys_shell_packages["shell/packages"]:::aspect
        sys_shell_starship["shell/starship"]:::aspect
        sys_shell_zsh["shell/zsh"]:::aspect
        sys_style["style"]:::aspect
        opt_containers["containers"]:::aspect
        opt_nvidia["nvidia"]:::aspect
        opt_orchestrator_caddy["orchestrator/caddy"]:::aspect
        opt_orchestrator_consul["orchestrator/consul"]:::aspect
        opt_orchestrator_coredns["orchestrator/coredns"]:::aspect
        opt_orchestrator_nomad["orchestrator/nomad"]:::aspect
        opt_orchestrator["orchestrator"]:::aspect
        opt_peripherals["peripherals"]:::aspect
        opt_plasma["plasma"]:::aspect
        opt_virtualization["virtualization"]:::aspect
        type_client["client"]:::aspect
        type_server["server"]:::aspect
        type_vm_guest["vm-guest"]:::aspect
    end

    subgraph HomeAspects[Home Namespace Aspects]
        home_autostart["autostart"]:::aspect
        home_backup["backup"]:::aspect
        home_clipboard["clipboard"]:::aspect
        home_dead_mens_switch["dead-mens-switch"]:::aspect
        home_common["common"]:::aspect
        home_git["git"]:::aspect
        home_home_apps["home-apps"]:::aspect
        home_ide["ide"]:::aspect
        home_kiosk_brightness["kiosk-brightness"]:::aspect
        home_kiosk_browser["kiosk-browser"]:::aspect
        home_llm["llm"]:::aspect
        home_password_manager["password-manager"]:::aspect
        home_scripts["scripts"]:::aspect
        home_ssh["ssh"]:::aspect
        home_storage["storage"]:::aspect
        home_web_browser_policies["web-browser/policies"]:::aspect
        home_web_browser["web-browser"]:::aspect
    end

    subgraph Hosts[Hosts]
        host_kiosk["kiosk"]:::hosts
        host_kiosk_hardware["hardware"]:::config
        host_personal_laptop["personal-laptop"]:::hosts
        host_personal_laptop_hardware["hardware"]:::config
        host_personal_vps_02["personal-vps-02"]:::hosts
        host_personal_vps_02_hardware["hardware"]:::config
        host_personal_workstation["personal-workstation"]:::hosts
        host_personal_workstation_hardware["hardware"]:::config
        host_server_01["server-01"]:::hosts
        host_server_01_hardware["hardware"]:::config
        host_server_03["server-03"]:::hosts
        host_server_03_hardware["hardware"]:::config
    end

    subgraph Users[Users]
        user_admin["admin"]:::users
        user_kiosk["kiosk"]:::users
        user_krumpy_miha["krumpy-miha"]:::users
    end


    den --> host_kiosk
    den --> host_personal_laptop
    den --> host_personal_vps_02
    den --> host_personal_workstation
    den --> host_server_01
    den --> host_server_03
    den --> sys_core
    den --> sys_disks
    den --> sys_impermanence
    den --> sys_locale
    den --> sys_networking
    den --> sys_nix
    den --> sys_secrets
    den --> sys_shell
    den --> sys_style
    den --> user_admin
    den --> user_kiosk
    den --> user_krumpy_miha
    flake --> den
    home_kiosk_browser --> home_web_browser_policies
    home_web_browser --> home_web_browser_policies
    host_kiosk --> host_kiosk_hardware
    host_kiosk --> type_client
    host_personal_laptop --> host_personal_laptop_hardware
    host_personal_laptop --> opt_containers
    host_personal_laptop --> opt_virtualization
    host_personal_laptop --> type_client
    host_personal_vps_02 --> host_personal_vps_02_hardware
    host_personal_vps_02 --> type_server
    host_personal_vps_02 --> type_vm_guest
    host_personal_workstation --> home_backup
    host_personal_workstation --> home_dead_mens_switch
    host_personal_workstation --> host_personal_workstation_hardware
    host_personal_workstation --> opt_containers
    host_personal_workstation --> opt_virtualization
    host_personal_workstation --> type_client
    host_server_01 --> host_server_01_hardware
    host_server_01 --> opt_orchestrator
    host_server_01 --> type_server
    host_server_03 --> host_server_03_hardware
    host_server_03 --> opt_orchestrator
    host_server_03 --> type_server
    input_agenix --> flake
    input_agenix_rekey --> flake
    input_den --> flake
    input_disko --> flake
    input_home_manager --> flake
    input_impermanence --> flake
    input_import_tree --> flake
    input_infrastructure_secrets --> flake
    input_lanzaboote --> flake
    input_mattpocock_skills --> flake
    input_nix_index_database --> flake
    input_nix_vscode_extensions --> flake
    input_nixpkgs --> flake
    input_nur --> flake
    input_plasma_manager --> flake
    input_stylix --> flake
    input_tix --> flake
    local_consul_cni --> flake
    local_mutable_file --> flake
    local_virtualhere --> flake
    opt_orchestrator --> opt_containers
    opt_orchestrator --> opt_orchestrator_caddy
    opt_orchestrator --> opt_orchestrator_consul
    opt_orchestrator --> opt_orchestrator_coredns
    opt_orchestrator --> opt_orchestrator_nomad
    sys_shell --> sys_shell_fonts
    sys_shell --> sys_shell_packages
    sys_shell --> sys_shell_starship
    sys_shell --> sys_shell_zsh
    type_client --> opt_peripherals
    type_client --> opt_plasma
    type_server --> user_admin
    type_vm_guest --> user_admin
    user_kiosk --> home_common
    user_kiosk --> home_kiosk_brightness
    user_kiosk --> home_kiosk_browser
    user_krumpy_miha --> home_autostart
    user_krumpy_miha --> home_clipboard
    user_krumpy_miha --> home_common
    user_krumpy_miha --> home_git
    user_krumpy_miha --> home_home_apps
    user_krumpy_miha --> home_ide
    user_krumpy_miha --> home_llm
    user_krumpy_miha --> home_password_manager
    user_krumpy_miha --> home_scripts
    user_krumpy_miha --> home_ssh
    user_krumpy_miha --> home_storage
    user_krumpy_miha --> home_web_browser

```
<!-- DEPS_END -->

## TODO

- https://github.com/yorukot/superfile
- https://github.com/amadejkastelic/nixos-config/tree/main/hosts/server
- https://docs.nixbuild.net/remote-builds/

## References

Sources:

- https://nixos-and-flakes.thiscute.world

Configs:

- https://github.com/raexera/yuki
- https://github.com/wiedzmin/nixos-config
- https://github.com/Zaechus/nixos-config
- https://github.com/erictossell/nixflakes
- https://github.com/etu/nixconfig
- https://codeberg.org/highghlow/nixos-config
- https://github.com/leoank/neusis: Nvidia Datacenter GPU
- https://github.com/pranjalv123/nix-config: VMs
- https://github.com/abehidek/nix-config: VMs
