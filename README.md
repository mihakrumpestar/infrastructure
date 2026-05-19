# Infrastructure

NixOS configuration repository for managing multiple hosts using flakes.

## Repository Structure

```sh
├── hosts/                  # Per-host configurations
├── nixosModules/           # NixOS modules (common/optional)
├── homeManagerModules/     # Home Manager modules and user configs
├── packages/               # Custom packages (flakes)
├── home-modules/           # Custom home-manager modules (flakes)
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

## NixOS Configuration Sizes

Generated: 2026-05-19 18:48
**Statistics computed over 2 build run(s)**

**Table 1:** NixOS system configuration sizes and evaluation times for each host.

This table presents the closure size (total disk space required for all dependencies)
and evaluation time (time to compute the Nix derivation) for each configured host
in the infrastructure. Closure size is measured in GiB (gibibytes, 2³⁰ bytes)
and represents the complete set of packages, libraries, and system components
required for each configuration. System/Home Pkgs shows the count of packages
in each profile (excluding -doc, -man, -info, -dev, -bin outputs).
System/Home Refs shows the total recursive dependencies for each profile.
Evaluation time measures the computational overhead of the Nix
expression evaluator and is performed on cached derivations, representing the
minimal overhead when no packages need rebuilding.

|                 Host |   Closure Size |   System Pkgs |   Home Pkgs |   System Refs |   Home Refs |       Eval Time |
|---------------------:|---------------:|--------------:|------------:|--------------:|------------:|----------------:|
|                kiosk |       9.78 GiB |          1422 |         461 |          2135 |         510 |  12.60s ± 0.05s |
|      personal-laptop |      35.96 GiB |          6251 |        5541 |          8293 |        6886 |  19.41s ± 0.60s |
|      personal-vps-02 |       3.25 GiB |           663 |           - |          1168 |           - |   5.58s ± 4.09s |
| personal-workstation |      36.92 GiB |          6301 |        5541 |          8366 |        6887 | 12.14s ± 12.01s |
|            server-01 |       5.02 GiB |           697 |           - |          1236 |           - |   6.67s ± 5.55s |
|            server-03 |       5.03 GiB |           697 |           - |          1231 |           - |   6.58s ± 5.55s |

## Timing Statistics

**Table 3:** Detailed timing statistics across multiple runs.

|                 Host |    Mean |   Median |   Std Dev |     Min |     Max |   Runs |
|---------------------:|--------:|---------:|----------:|--------:|--------:|-------:|
|                kiosk | 12.603s |  12.603s |    0.050s | 12.568s | 12.639s |      2 |
|      personal-laptop | 19.405s |  19.405s |    0.596s | 18.984s | 19.826s |      2 |
|      personal-vps-02 |  5.575s |   5.575s |    4.089s |  2.684s |  8.466s |      2 |
| personal-workstation | 12.140s |  12.140s |   12.007s |  3.650s | 20.631s |      2 |
|            server-01 |  6.673s |   6.673s |    5.551s |  2.748s | 10.598s |      2 |
|            server-03 |  6.583s |   6.583s |    5.548s |  2.660s | 10.506s |      2 |

### Visualizations

- ![Bar Chart](generated/stats_20260519_184819/infrastructure-configurations_timing_barchart.png)
- ![Box Plot](generated/stats_20260519_184819/infrastructure-configurations_timing_boxplot.png)

## Closure Reuse Matrix

**Table 2:** Binary-level dependency sharing between host configurations.

This matrix quantifies the degree of dependency reuse across different NixOS host
configurations. Each cell shows the percentage of packages (derivations) from the
row host's closure that also appear in the column host's closure. A value of 100%
would indicate complete subsumption (all packages from row host are present in column
host). The diagonal shows dashes (-) as self-comparison is omitted. Higher percentages
indicate greater infrastructure consolidation potential through shared package caches
and common dependency management. This metric is particularly relevant for optimizing
distributed builds, reducing network transfer overhead, and minimizing storage
requirements in multi-host deployments.

|                 Host |   kiosk |   personal-laptop |   personal-vps-02 |   personal-workstation |   server-01 |   server-03 |
|---------------------:|--------:|------------------:|------------------:|-----------------------:|------------:|------------:|
|                kiosk |       - |               94% |               47% |                    94% |         49% |         49% |
|      personal-laptop |     24% |                 - |               12% |                    99% |         12% |         13% |
|      personal-vps-02 |     86% |               86% |                 - |                    86% |         92% |         92% |
| personal-workstation |     24% |               98% |               12% |                      - |         12% |         12% |
|            server-01 |     85% |               86% |               87% |                    86% |           - |         95% |
|            server-03 |     85% |               87% |               87% |                    87% |         95% |           - |
<!-- STATS_END -->

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
        local_mutable_file["home-modules/mutable-file"]:::local
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
- https://nixos-and-flakes.thiscute.world/nixos-with-flakes/modularize-the-configuration
- https://docs.nixbuild.net/remote-builds/

## References

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
