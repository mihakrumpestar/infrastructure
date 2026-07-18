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

## Hosts

| **Host** | **Type** | **Boot** | **Disk enc.** | **Local login** | **Secrets enc.** | **Impermanence** | **Home Manager** |
|---|---|---|---|---|---|---|---|
| personal-workstation | Client | Lanzaboote | FIDO2 | FIDO2 | TPM | Default | Full |
| personal-laptop | Client | Lanzaboote | FIDO2 | FIDO2 | TPM | Default | Full |
| server-01 | Server | Lanzaboote | TPM2 | Password | TPM | Default | None |
| server-03 | Server | systemd-boot | TPM2 | Password | TPM | Default | None |
| personal-vps-02 | Server+VM guest | GRUB | None | Password | SSH key | Default | None |
| kiosk | Client (kiosk) | Lanzaboote | TPM2 | Auto | TPM | Maximum | Kiosk-only |

## Build Statistics

<!-- STATS_START -->

commit hash: 47fde4a3c3973d0428debe4294be01e5e1de2564

nix (Nix) 2.34.7

Kernel: 7.1.2

CPU: AMD Ryzen 9 5900HX with Radeon Graphics

Disk: Micron Technology Inc 3400 NVMe SSD [Hendrix] (SN: MTFDKBA512TFH-1BC1AABHA)

Memory: 29 GiB


## Lines of Code

**Table 1:** Non-blank lines across the flake's source tree.

LOC excludes blank lines but includes comments. All file types are counted (`.nix`, `.json`, `.jsonc`, `.sh`, `.ini`, etc.) except Markdown (`.md`).

| Component        |   Lines |
|:-----------------|--------:|
| flake.nix        |      89 |
| modules/den.nix  |      94 |
| modules/hosts    |     462 |
| modules/system   |    1942 |
| modules/home     |    2831 |
| modules/users    |     184 |
| modules (total)  |    5513 |
| packages (total) |     279 |
| lib (total)      |      97 |
| **Total**        |    5978 |

## NixOS Configuration Sizes

**Table 2:** NixOS system configuration sizes for each host.

This table presents the closure size (total disk space required for all dependencies) for each configured host in the infrastructure. Closure size is measured in GiB (gibibytes, 2³⁰ bytes) and represents the complete set of packages, libraries, and system components required for each configuration. System/Home Pkgs shows the count of packages in each profile (excluding -doc, -man, -info, -dev, -bin outputs). System/Home Refs shows the total recursive dependencies for each profile.

|                 Host |   Closure Size |   System Pkgs |   Home Pkgs |   System Refs |   Home Refs |
|---------------------:|---------------:|--------------:|------------:|--------------:|------------:|
|                kiosk |      10.39 GiB |          1434 |         521 |          2179 |         576 |
|      personal-laptop |      36.60 GiB |          6241 |        5527 |          8299 |        6869 |
|      personal-vps-02 |       3.60 GiB |           675 |           - |          1182 |           - |
| personal-workstation |      37.62 GiB |          6293 |        5530 |          8379 |        6875 |
|            server-01 |       6.12 GiB |           705 |           - |          1244 |           - |
|            server-03 |       4.38 GiB |           683 |           - |          1197 |           - |

## Eval Performance

**Statistics computed over 5 run(s)**

### Sequential

**Table 3:** Evaluation time per host with no concurrent evaluation. Each host is evaluated in isolation using `nix eval --option eval-cache false` to ensure deterministic, cache-free measurements.

|                 Host |    Mean |   Median |   Std Dev |     Min |     Max |   Runs |
|---------------------:|--------:|---------:|----------:|--------:|--------:|-------:|
|                kiosk | 12.705s |  12.685s |    0.069s | 12.621s | 12.811s |      5 |
|      personal-laptop | 17.332s |  17.370s |    0.140s | 17.187s | 17.518s |      5 |
|      personal-vps-02 |  8.604s |   8.618s |    0.042s |  8.551s |  8.651s |      5 |
| personal-workstation | 17.573s |  17.518s |    0.166s | 17.423s | 17.776s |      5 |
|            server-01 |  9.713s |   9.707s |    0.110s |  9.545s |  9.837s |      5 |
|            server-03 |  8.603s |   8.626s |    0.098s |  8.482s |  8.717s |      5 |

### Simultaneous

**Table 4:** Evaluation time per host with all hosts evaluated concurrently. All hosts are evaluated in parallel to measure the overhead of concurrent Nix evaluation (CPU contention, lock contention, etc.).

|                 Host |    Mean |   Median |   Std Dev |     Min |     Max |   Runs |
|---------------------:|--------:|---------:|----------:|--------:|--------:|-------:|
|                kiosk | 25.402s |  25.402s |    0.062s | 25.316s | 25.468s |      5 |
|      personal-laptop | 30.461s |  30.467s |    0.169s | 30.259s | 30.661s |      5 |
|      personal-vps-02 | 20.726s |  20.738s |    0.099s | 20.607s | 20.861s |      5 |
| personal-workstation | 30.552s |  30.562s |    0.077s | 30.435s | 30.628s |      5 |
|            server-01 | 22.033s |  22.020s |    0.078s | 21.961s | 22.161s |      5 |
|            server-03 | 20.676s |  20.668s |    0.080s | 20.557s | 20.755s |      5 |

## Closure Reuse Matrix

**Table 5:** Binary-level dependency sharing between host configurations.

This matrix quantifies the degree of dependency reuse across different NixOS host configurations. Each cell shows the percentage of packages (derivations) from the row host's closure that also appear in the column host's closure. A value of 100% would indicate complete subsumption. The diagonal shows dashes (-) as self-comparison is omitted. Higher percentages indicate greater infrastructure consolidation potential through shared package caches and common dependency management.

|                 Host |   kiosk |   personal-laptop |   personal-vps-02 |   personal-workstation |   server-01 |   server-03 |
|---------------------:|--------:|------------------:|------------------:|-----------------------:|------------:|------------:|
|                kiosk |       - |               94% |               47% |                    93% |         49% |         48% |
|      personal-laptop |     24% |                 - |               12% |                    99% |         12% |         12% |
|      personal-vps-02 |     87% |               87% |                 - |                    87% |         93% |         94% |
| personal-workstation |     24% |               98% |               12% |                      - |         12% |         12% |
|            server-01 |     86% |               85% |               88% |                    85% |           - |         91% |
|            server-03 |     88% |               88% |               93% |                    88% |         95% |           - |<!-- STATS_END -->

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
        home_llm_agent["llm/agent"]:::aspect
        home_llm["llm"]:::aspect
        home_llm_gateway["llm/gateway"]:::aspect
        home_llm_mcp["llm/mcp"]:::aspect
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
    home_llm --> home_llm_agent
    home_llm --> home_llm_gateway
    home_llm --> home_llm_mcp
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
    host_server_01 --> orchestrator
    host_server_01 --> type_server
    host_server_03 --> host_server_03_hardware
    host_server_03 --> orchestrator
    host_server_03 --> type_server
    input_agenix --> flake
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
    orchestrator --> opt_containers
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

- https://saylesss88.github.io/nix/hardening_NixOS.html
- https://github.com/yorukot/superfile
- https://github.com/amadejkastelic/nixos-config/tree/main/hosts/server
- https://docs.nixbuild.net/remote-builds/

## References

Sources:

- https://nixos-and-flakes.thiscute.world

Configs:

- https://github.com/mightyiam/infra: dendritic pattern
- https://github.com/vic/vix: dendritic pattern
- https://github.com/GaetanLepage/nix-config
- https://github.com/raexera/yuki
- https://github.com/wiedzmin/nixos-config
- https://github.com/Zaechus/nixos-config
- https://github.com/erictossell/nixflakes
- https://github.com/etu/nixconfig
- https://codeberg.org/highghlow/nixos-config
- https://github.com/leoank/neusis: Nvidia Datacenter GPU
- https://github.com/pranjalv123/nix-config: VMs
- https://github.com/abehidek/nix-config: VMs
