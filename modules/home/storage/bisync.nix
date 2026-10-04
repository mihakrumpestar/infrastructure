{
  ...
}:
{
  home.storage-bisync = {
    homeManager =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      let
        rcloneConfigPath = config.age.secrets."rclone_config".path;

        # Sync engine: rclone bisync. This module wraps it with the
        # failure handling and observability that production use requires.
        #
        # The hardening below makes that failure mode loud and mostly self-healing:
        #
        #   Self-healing runs    --resilient --recover --max-lock 2m retry
        #                        less-serious errors, recover interrupted
        #                        runs, and expire stale lock files.
        #   Conflict safety      The default conflict handling keeps both
        #                        versions of a conflicting file as
        #                        *.conflict1/*.conflict2 copies; nothing is
        #                        ever silently discarded.
        #   Durable state        Listings, state files, rotated logs and
        #                        alerts live under ~/.local/state, never
        #                        ~/.cache, which cleaners routinely empty.
        #   Bootstrap guard      An empty local dir only triggers --resync
        #                        before the first successful sync; later
        #                        emptying fails loudly instead of
        #                        resurrecting files.
        #   Guarded auto-resync  If listings are lost anyway, a single
        #                        --resync rebuilds them. The bootstrap
        #                        trusts the remote, while remediation uses
        #                        --resync-mode newer, so unsynced local
        #                        edits are never silently reverted. The
        #                        user is notified either way.
        #   Compare mode         See the bisync.compareMode option description.
        #   Watchdog and tray    Per-pair health in the system tray, with
        #                        sync-now, pause and resume controls; alert
        #                        thresholds derive from alertStaleAfterHours.
        #
        # Multi-host caveat: bisync has no cross-machine lock. Within one
        # sync interval, another host's upload can be overwritten; the
        # losing version is archived. Keep vault edits on one machine at a
        # time. New pairs need the remote base directory to exist, as
        # --resync will not create it.
        #
        # Backups: every file replaced or deleted by a run is archived under
        # a per-run subdir named <timestamp>-<hostname> on both sides:
        #   remote: <remotePath>-backup/<run-id>/
        #   local:  ~/.local/share/rclone-bisync-backup/<name>/<run-id>/
        # The watchdog prunes run dirs older than backupRetentionDays
        # (default 60 days; 0 keeps everything). Remote pruning activates
        # after the pair's next sync, and legacy pre-run-id backups are
        # never pruned automatically.
        #
        # Recovery procedure: before adding a pair, or after an outage that
        # left the two sides diverged, converge them deliberately first
        # (a KeePassXC merge works well), place the result on both sides,
        # and only then let bisync rebuild its state.
        mkBisyncService =
          {
            name,
            remotePath,
            localPath,
            syncDelay ? 30, # 30 sec
            syncInterval ? 900, # 15 min
            startDelay ? "2min",
          }:
          # The name becomes a systemd unit name, state/log file names and
          # shell text; anything outside [A-Za-z0-9_.-] breaks one of those
          # consumers (unit addressing, KEY=VALUE parsing, globbing).
          assert lib.assertMsg (
            builtins.match "[A-Za-z0-9][A-Za-z0-9_.-]*" name != null
          ) "bisync pair name '${name}' may only contain [A-Za-z0-9_.-]";
          {
            service = {
              Unit = {
                Description = "rclone bisync: ${name} sync (inotify + periodic)";
                Documentation = "man:rclone(1) man:inotifywait(1)";
                # network-online.target does not exist in the user manager, so
                # the real protections are the staggered start delay plus the
                # 15 min heartbeat retry. agenix.service ordering matters:
                # ExecStart consumes the decrypted rclone.conf.
                After = [ "agenix.service" ];
              };
              Service = {
                Type = "simple";
                ExecStart =
                  let
                    autoResync = if config.my.home.storage.bisync.autoResync then "1" else "0";
                    compareMode = config.my.home.storage.bisync.compareMode;
                    script = pkgs.writeShellScript "rclone-bisync-${name}" ''
                      SYNC_PATH="$HOME/${localPath}"
                      SYNC_DELAY=${toString syncDelay}
                      SYNC_INTERVAL=${toString syncInterval}
                      AUTO_RESYNC=${autoResync}
                      COMPARE_MODE="${compareMode}"
                      STATE_DIR="$HOME/.local/state/rclone-bisync"
                      LOG_DIR="$STATE_DIR/logs"
                      WORK_DIR="$STATE_DIR/work/${name}"
                      STATE_FILE="$STATE_DIR/${name}.state"
                      BOOTSTRAP="$STATE_DIR/.bootstrapped-${name}"
                      LOG_FILE="$LOG_DIR/${name}.log"
                      NOTIFY="${pkgs.libnotify}/bin/notify-send"

                      ${pkgs.coreutils}/bin/mkdir -p -- "$SYNC_PATH"
                      # Private: state and logs contain file names, and
                      # backup runs archive every prior kdbx version.
                      ${pkgs.coreutils}/bin/install -d -m 700 -- \
                        "$STATE_DIR" "$LOG_DIR" "$WORK_DIR" \
                        "$HOME/.local/share/rclone-bisync-backup/${name}"
                      # rclone-created run dirs and files must stay private too.
                      umask 077

                      # A deliberate pause must survive reboots: if the pause
                      # marker exists, exit cleanly. The login timer fires
                      # once regardless, and Restart=on-failure never
                      # restarts a clean exit, so the pair stays down.
                      if [ -f "$STATE_DIR/${name}.paused" ]; then
                        exit 0
                      fi

                      notify_user() {
                        # Desktop notification when a graphical session exists.
                        DISPLAY="''${DISPLAY:-:0}" "$NOTIFY" -u critical -t 60000 \
                          "rclone bisync ${name}" "$1" >/dev/null 2>&1 || true
                      }

                      write_state() {
                        # Record the run result atomically and echo the
                        # previous exit code, so callers can notify only when
                        # a pair transitions from healthy to failing. A
                        # failure keeps the last known last_success.
                        local exit_code="$1" now prev_success="never" prev_exit=0
                        now="$(${pkgs.coreutils}/bin/date -Iseconds)"
                        if [ "$exit_code" -eq 0 ]; then
                          prev_success="$now"
                        elif [ -f "$STATE_FILE" ]; then
                          # shellcheck disable=SC1090
                          . "$STATE_FILE" 2>/dev/null
                          prev_success="''${last_success:-never}"
                          prev_exit="''${last_exit:-0}"
                        fi
                        ${pkgs.coreutils}/bin/printf 'pair=${name}\nlast_attempt=%s\nlast_success=%s\nlast_exit=%s\nbackup1_root=${remotePath}-backup\n' \
                          "$now" "$prev_success" "$exit_code" > "''${STATE_FILE}.tmp" \
                          && ${pkgs.coreutils}/bin/mv "''${STATE_FILE}.tmp" "$STATE_FILE"
                        printf '%s' "$prev_exit"
                      }

                      run_bisync() {
                        # Shared flags for every bisync invocation so normal
                        # runs, the bootstrap resync and the remediation resync
                        # can never diverge (compare mode, backup dirs, lock
                        # timeout).
                        local run_id="$1"; shift
                        ${pkgs.rclone}/bin/rclone bisync "${remotePath}" "$SYNC_PATH" \
                          --config=${rcloneConfigPath} \
                          --workdir "$WORK_DIR" \
                          --log-file "$LOG_FILE" \
                          --log-level INFO \
                          --backup-dir1 "${remotePath}-backup/''${run_id}" \
                          --backup-dir2 "$HOME/.local/share/rclone-bisync-backup/${name}/''${run_id}" \
                          --create-empty-src-dirs \
                          --compare "$COMPARE_MODE" \
                          --max-lock 2m "$@"
                      }

                      do_sync() {
                        local rc prev_exit safety_flags run_id
                        # Stamp this run with a timestamp and hostname id:
                        # every file replaced or deleted by this run, up to
                        # and including the remediation resync when it fires,
                        # is archived under a matching per-run subdir on
                        # each side.
                        run_id="$(${pkgs.coreutils}/bin/date +%Y%m%dT%H%M%S)-$(${pkgs.coreutils}/bin/uname -n)"
                        safety_flags="--resilient --recover"
                        RESYNC_FLAG=""
                        # Bootstrap: an empty local dir before the first
                        # successful sync pulls everything from the remote.
                        # Once bootstrapped, deletions propagate normally and
                        # an emptied dir fails loudly. Note that --recover
                        # only applies to normal runs, never to --resync.
                        if [ ! -f "$BOOTSTRAP" ] \
                          && [ -z "$(${pkgs.coreutils}/bin/ls -A "$SYNC_PATH" 2>/dev/null)" ]; then
                          RESYNC_FLAG="--resync"
                          safety_flags="--resilient"
                        fi

                        # Rotate the log at 10 MiB, keeping one generation.
                        if [ -f "$LOG_FILE" ] \
                          && [ "$(${pkgs.coreutils}/bin/stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)" -gt 10485760 ]; then
                          ${pkgs.coreutils}/bin/mv "$LOG_FILE" "$LOG_FILE.1"
                        fi

                        run_bisync "$run_id" $RESYNC_FLAG $safety_flags
                        rc=$?
                        prev_exit="$(write_state "$rc")"
                        if [ "$rc" -eq 0 ]; then
                          ${pkgs.coreutils}/bin/touch "$BOOTSTRAP"
                          if [ -n "$RESYNC_FLAG" ]; then
                            notify_user "Initial sync from remote completed"
                          fi
                        fi
                        if [ "$rc" -ne 0 ]; then
                          # Notify only on transition from healthy to failing.
                          if [ "$prev_exit" -eq 0 ]; then
                            notify_user "Sync failed (exit $rc), details in $LOG_FILE"
                          fi
                          # Last-resort remediation: if the listings are gone,
                          # rebuild them with a single --resync. It runs with
                          # --resync-mode newer instead of the path1 default,
                          # so unsynced local edits can never be silently
                          # reverted to older remote versions; superseded
                          # files land in the backup dirs. The error message
                          # is matched case-insensitively and was verified
                          # against rclone 1.75.1.
                          if [ "$AUTO_RESYNC" = "1" ] \
                            && ${pkgs.coreutils}/bin/tail -n 50 "$LOG_FILE" 2>/dev/null \
                              | ${pkgs.gnugrep}/bin/grep -qiE "cannot find prior.*listings"; then
                            notify_user "Bisync state lost, rebuilding with --resync"
                            run_bisync "$run_id" --resync --resync-mode newer --resilient
                            rc=$?
                            prev_exit="$(write_state "$rc")"
                            if [ "$rc" -eq 0 ]; then
                              ${pkgs.coreutils}/bin/touch "$BOOTSTRAP"
                              notify_user "Bisync state rebuilt; superseded files archived to ~/.local/share/rclone-bisync-backup/${name}/''${run_id}"
                            fi
                          fi
                        fi

                        # Drop the local run dir when nothing was archived:
                        # rclone creates it lazily, so a run without changes
                        # should not leave an empty folder behind.
                        ${pkgs.coreutils}/bin/rmdir \
                          "$HOME/.local/share/rclone-bisync-backup/${name}/''${run_id}" 2>/dev/null || true
                      }

                      do_sync

                      while true; do
                        ${pkgs.inotify-tools}/bin/inotifywait --recursive \
                          --timeout "$SYNC_INTERVAL" \
                          -e modify,delete,create,move "$SYNC_PATH"
                        EXIT_CODE=$?
                        if [ "$EXIT_CODE" -eq 0 ]; then
                          ${pkgs.coreutils}/bin/sleep "$SYNC_DELAY"
                          do_sync
                        elif [ "$EXIT_CODE" -eq 2 ]; then
                          do_sync
                        else
                          # An inotifywait error (missing directory, exhausted
                          # watch limit, ...) is no reason to stop syncing:
                          # back off briefly, then run a delta sync anyway so
                          # the failure shows up loudly in the state file.
                          ${pkgs.coreutils}/bin/sleep 60
                          do_sync
                        fi
                      done
                    '';
                  in
                  "${script}";
                Restart = "on-failure";
                RestartSec = "10s";
                # bisync shuts down gracefully on SIGINT. The systemd default
                # SIGTERM kills mid-run instead, leaving recovery to
                # --recover with a wider conflict window.
                KillSignal = "SIGINT";
              };
            };

            timer = {
              # OnStartupSec is user-manager-start relative (boot with linger).
              Unit.Description = "Timer: rclone bisync ${name} sync (${startDelay} after user-manager start)";
              Timer.OnStartupSec = startDelay;
              Install.WantedBy = [ "timers.target" ];
            };
          };

        bisyncServices = [
          {
            name = "Documents";
            remotePath = "nextcloud-personal:private/Documents";
            localPath = "Documents";
          }
          {
            name = "Sidebery";
            remotePath = "nextcloud-personal:private/Downloads/Sidebery";
            localPath = "Downloads/Sidebery";
            startDelay = "3min";
          }
        ];

        syncTray = pkgs.writers.writePython3Bin "rclone-sync-tray" {
          libraries = [ pkgs.python3Packages.pyqt6 ];
          # writers' --ignore replaces flake8's default ignore list, so W503
          # and W504 must be re-ignored explicitly.
          flakeIgnore = [
            "E501"
            "E402"
            "W503"
            "W504"
          ];
        } (builtins.readFile ./sync-tray.py);

        watchdog = pkgs.writeShellApplication {
          name = "rclone-bisync-watchdog";
          runtimeInputs = with pkgs; [
            coreutils
            gnugrep
            libnotify
            rclone
          ];
          text = ''
            STATE_DIR="$HOME/.local/state/rclone-bisync"
            THRESHOLD_HOURS=${toString config.my.home.storage.bisync.alertStaleAfterHours}
            RETENTION_DAYS=${toString config.my.home.storage.bisync.backupRetentionDays}
            DEDUPE_SECONDS=$(( 12 * 3600 ))

            maybe_alert() {
              # maybe_alert <pair> <body>: notify at most once per dedupe
              # window per pair, and append every alert to alerts.log so the
              # trail outlives the desktop session.
              local pair="$1" body="$2" marker="$STATE_DIR/$1.alerted" last=0 now
              now="$(date +%s)"
              read -r last 2>/dev/null < "$marker" || last=0
              if [ $(( now - last )) -ge "$DEDUPE_SECONDS" ]; then
                DISPLAY="''${DISPLAY:-:0}" notify-send -u critical -t 9999999 \
                  "rclone bisync: $pair" "$body" || true
                printf '%s %s: %s\n' "$(date -Iseconds)" "$pair" "$body" \
                  >> "$STATE_DIR/alerts.log"
                printf '%s' "$now" > "$marker.tmp" \
                  && mv "$marker.tmp" "$marker"
              fi
            }

            run_dir_epoch() {
              # Single source for the run-id timestamp grammar: validate the
              # <yyyymmddThhmmss>-<host> shape and parse its embedded time.
              local ts="$1" iso
              case "$ts" in
                [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]T[0-9][0-9][0-9][0-9][0-9][0-9]-*) ;;
                *) echo 0; return 0 ;;
              esac
              iso="''${ts:0:4}-''${ts:4:2}-''${ts:6:2}T''${ts:9:2}:''${ts:11:2}:''${ts:13:2}"
              date -d "$iso" +%s 2>/dev/null || echo 0
            }

            prune_pair() {
              # prune_pair <pair> <backup1_root>: remove backup run dirs older
              # than RETENTION_DAYS on both sides. Age is taken from the run
              # id timestamp, because archived files keep their original
              # mtimes; judging by file age would prune fresh backups of old
              # files.
              local pair="$1" backup1_root="$2" cutoff dir ts age_dir dirs
              [ "$RETENTION_DAYS" -gt 0 ] || return 0
              cutoff=$(( $(date +%s) - RETENTION_DAYS * 86400 ))

              # Local side: run dirs under ~/.local/share/rclone-bisync-backup.
              for dir in "$HOME/.local/share/rclone-bisync-backup/$pair"/*/; do
                [ -d "$dir" ] || continue
                ts="$(basename "$dir")"
                age_dir="$(run_dir_epoch "$ts")"
                if [ "$age_dir" -ne 0 ] && [ "$age_dir" -lt "$cutoff" ]; then
                  rm -rf -- "$dir"
                fi
              done

              # Remote side: run dirs under <remotePath>-backup.
              [ -n "$backup1_root" ] || return 0
              dirs="$(rclone lsf --dirs-only "$backup1_root/" 2>/dev/null)" || return 0
              printf '%s\n' "$dirs" | while read -r ts; do
                ts="''${ts%/}"
                age_dir="$(run_dir_epoch "$ts")"
                if [ "$age_dir" -ne 0 ] && [ "$age_dir" -lt "$cutoff" ]; then
                  rclone purge "$backup1_root/$ts" 2>/dev/null || true
                fi
              done
            }

            shopt -s nullglob
            for state_file in "$STATE_DIR"/*.state; do
              unset pair last_exit last_attempt last_success backup1_root
              # shellcheck disable=SC1090
              . "$state_file"
              pair="''${pair:-$(basename "$state_file" .state)}"
              # Housekeeping is independent of pause state.
              prune_pair "$pair" "''${backup1_root:-}"
              # Deliberately paused pairs (tray "Pause") must not alert.
              if [ -f "$STATE_DIR/$pair.paused" ]; then
                continue
              fi
              # Sanitize: a corrupted last_exit must not abort the loop
              # (writeShellApplication runs with errexit). A corrupt value
              # must also alert like the tray does, so treat it as failure
              # and never as healthy. last_exit is never empty here
              # (''${last_exit:-0} substitutes the default).
              case "''${last_exit:-0}" in
                *[!0-9]*) last_exit=1 ;;
              esac
              if [ "$last_exit" -ne 0 ]; then
                maybe_alert "$pair" "Last run failed (exit ''${last_exit:-0}) at ''${last_attempt:-?}. Log: $STATE_DIR/logs/$pair.log"
                continue
              fi
              success_epoch="$(date -d "''${last_success:-}" +%s 2>/dev/null || echo 0)"
              if [ "$success_epoch" -eq 0 ]; then
                maybe_alert "$pair" "No successful sync recorded yet."
                continue
              fi
              age_hours=$(( ( $(date +%s) - success_epoch ) / 3600 ))
              if [ "$age_hours" -ge "$THRESHOLD_HOURS" ]; then
                maybe_alert "$pair" "Last successful sync was $age_hours hours ago."
              fi
            done
          '';
        };
      in
      {
        options.my.home.storage = {
          syncTray.enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = ''
              Run the rclone-sync-tray indicator in the desktop session
              (per-pair health icon plus sync now / pause / resume actions).
            '';
          };
          bisync = {
            alertStaleAfterHours = lib.mkOption {
              type = lib.types.ints.positive;
              default = 48;
              description = ''
                Watchdog alert threshold: how long a pair may go without a
                successful sync before the watchdog notifies the user.
              '';
            };
            autoResync = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = ''
                Allow the bisync wrapper to run one guarded --resync
                automatically when the workdir listings are lost, instead of
                failing forever until manual intervention.
              '';
            };
            backupRetentionDays = lib.mkOption {
              type = lib.types.ints.unsigned;
              default = 60;
              description = ''
                Auto-delete backup run dirs older than this many days on both
                sides (0 disables pruning).
              '';
            };
            compareMode = lib.mkOption {
              type = lib.types.strMatching "(size|modtime|checksum)(,(size|modtime|checksum))*";
              default = "size,modtime";
              description = ''
                Value for rclone bisync --compare. Checksum is omitted from
                the default because the Nextcloud WebDAV remote advertises
                sha1 support but returns blank hashes for non-empty files, so
                bisync warned per file per run and gained no detection (it
                falls back to size+modtime anyway). Append ",checksum" if the
                remote ever starts returning real hashes.
              '';
            };
          };
        };

        config = {
          systemd.user.services = lib.mkMerge (
            # Bisync services
            (map (svc: {
              "rclone-bisync-${svc.name}" = (mkBisyncService svc).service;
            }) bisyncServices)
            # Tray indicator (live per-pair status and controls)
            ++ (lib.optionals config.my.home.storage.syncTray.enable [
              {
                "rclone-sync-tray" = {
                  Unit = {
                    Description = "rclone bisync tray indicator";
                    After = [ "graphical-session.target" ];
                    PartOf = [ "graphical-session.target" ];
                    # Never rate-limit a monitoring surface into silence: a
                    # deterministic crash would otherwise exhaust the burst
                    # and leave the session without any tray. RestartSec
                    # alone throttles the restart rate.
                    StartLimitIntervalSec = 0;
                  };
                  Service = {
                    Type = "simple";
                    ExecStart = "${syncTray}/bin/rclone-sync-tray";
                    Restart = "on-failure";
                    RestartSec = "5s";
                    # Tray thresholds derive from the watchdog alert option
                    # so the escalation ladder can never invert.
                    Environment = [
                      "SYNC_ALERT_HOURS=${toString config.my.home.storage.bisync.alertStaleAfterHours}"
                      # Pairs the tray must show even before their first
                      # sync wrote a state file (single source: the
                      # bisyncServices list in this file).
                      "SYNC_PAIRS=${lib.concatStringsSep "," (map (svc: svc.name) bisyncServices)}"
                      # The tray shells out to systemctl (in /run/wrappers/bin)
                      # and xdg-open (in /run/current-system/sw/bin); the user
                      # manager's default PATH is not guaranteed to find them.
                      "PATH=/run/wrappers/bin:/run/current-system/sw/bin"
                    ];
                  };
                  Install.WantedBy = [ "graphical-session.target" ];
                };
              }
            ])
            # Sync health watchdog (fired by rclone-bisync-watchdog.timer)
            ++ [
              {
                "rclone-bisync-watchdog" = {
                  Unit.Description = "rclone bisync health watchdog";
                  Service = {
                    Type = "oneshot";
                    ExecStart = "${watchdog}/bin/rclone-bisync-watchdog";
                  };
                };
              }
            ]
          );

          # Bisync timers
          systemd.user.timers = builtins.listToAttrs (
            (map (svc: {
              name = "rclone-bisync-${svc.name}";
              value = (mkBisyncService svc).timer;
            }) bisyncServices)
            # Watchdog timer: periodic health alerts independent of the tray.
            ++ [
              {
                name = "rclone-bisync-watchdog";
                value = {
                  Unit.Description = "Timer: rclone bisync health watchdog (every 30 min)";
                  Timer = {
                    OnCalendar = "*:0/30";
                    Persistent = true;
                  };
                  Install.WantedBy = [ "timers.target" ];
                };
              }
            ]
          );
        };
      };
  };
}
