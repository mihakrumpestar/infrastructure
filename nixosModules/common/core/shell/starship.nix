{lib, ...}: {
  programs.starship = {
    enable = true;
    settings = {
      # from https://github.com/ChrisTitusTech/mybash/blob/main/starship.toml with some modifications

      format = lib.concatStrings [
        "[](#3B4252)"
        "$username"
        "$hostname"
        "$battery"
        "[](bg:#434C5E fg:#3B4252)"
        "$directory"
        "[](fg:#434C5E bg:#4C566A)"
        "$git_branch"
        "$git_status"
        "[](fg:#4C566A bg:#86BBD8)"
        "$golang"
        "$java"
        "$nodejs"
        "$rust"
        "[](fg:#86BBD8 bg:#06969A)"
        "$nix_shell"
        "$docker_context"
        "[](fg:#06969A bg:#33658A)"
        "$time"
        "[ ](fg:#33658A)"
        "\n"
        "$cmd_duration"
        "$character"
      ];

      command_timeout = 500;
      add_newline = true;

      username = {
        show_always = true;
        style_user = "bg:#3B4252";
        style_root = "fg:red bg:#3B4252";
        format = "[$user ]($style)";
      };

      hostname = {
        style = "bg:#3B4252";
        ssh_symbol = "🌐";
        format = "[$ssh_symbol](bold fg:#33ccff $style)[$hostname ]($style)";
        trim_at = "";
      };

      directory = {
        style = "bg:#434C5E";
        format = "[ $path ]($style)";
        truncation_length = 8;
        truncation_symbol = "…/";
        substitutions = {
          "Documents" = " ";
          "Downloads" = " ";
          "Music" = " ";
          "Pictures" = " ";
        };
      };

      # Git

      git_branch = {
        symbol = "";
        style = "bg:#4C566A";
        format = "[ $symbol $branch ]($style)";
      };

      git_status = {
        style = "bold bg:#4C566A";
        format = "[$all_status$ahead_behind ]($style)";
      };

      # Language

      golang = {
        symbol = "";
        style = "bg:#86BBD8 fg:black";
        format = "[ $symbol ($version) ]($style)";
      };

      java = {
        symbol = "";
        style = "bg:#86BBD8 fg:black";
        format = "[ $symbol ($version) ]($style)";
      };

      nodejs = {
        symbol = "";
        style = "bg:#86BBD8 fg:black";
        format = "[ $symbol ($version) ]($style)";
      };

      rust = {
        symbol = "";
        style = "bg:#86BBD8 fg:black";
        format = "[ $symbol ($version) ]($style)";
      };

      # Shells

      docker_context = {
        symbol = "";
        style = "bg:#06969A";
        format = "[ $symbol $context $path]($style)";
      };

      nix_shell = {
        impure_msg = "";
        pure_msg = "";
        style = "bg:#06969A";
        format = "[ $symbol$state(\($name\)) ]($style)";
      };

      # Miscelnous

      time = {
        disabled = false;
        time_format = "%R";
        style = "bg:#33658A";
        format = "[ $time ]($style)";
      };

      cmd_duration = {
        min_time = 500;
        format = "[$duration]($style) ";
      };
    };
  };
}
