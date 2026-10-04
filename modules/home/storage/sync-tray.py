"""System tray indicator for the rclone-bisync-* user services.

Reads the KEY=VALUE state files the bisync services write under
~/.local/state/rclone-bisync/<name>.state (see modules/home/storage/default.nix)
and exposes sync health in the system tray:

  green:  all pairs synced successfully and recently
  orange: all pairs healthy but the newest success is stale (>= 24 h),
          or a pair's service is unexpectedly not running
  red:    at least one pair failed its last run, its service failed, or
          its last success is very stale (>= 72 h)
  grey:   no state recorded yet, or a pair is deliberately paused
          (Pause writes <name>.paused; the watchdog skips paused pairs)

  Pairs listed in the SYNC_PAIRS env (comma-separated, set by the unit)
  appear even before their first sync, so a silent pair is never hidden.

Menu actions per pair: sync now (restart unit; disabled while paused),
pause (stop unit and write the pause marker), resume (start unit and clear
the marker), open log. The menu is host-rendered by the desktop from the
exported StatusNotifierItem (ItemIsMenu), so left and right click both
open it; secondary activation refreshes. Control commands run off the GUI
thread and their failures surface as desktop notifications.

Run with --status for a headless summary (exit 0 when any state file
exists, 1 otherwise).
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

import dbus
import dbus.service
from dbus.mainloop.pyqt6 import DBusQtMainLoop
from PyQt6.QtCore import QObject, QProcess, Qt, QTimer
from PyQt6.QtDBus import QDBus, QDBusConnection, QDBusMessage, QDBusServiceWatcher
from PyQt6.QtGui import QColor, QImage, QPainter, QPixmap
from PyQt6.QtWidgets import QApplication, QMenu

# Must match the wrapper and watchdog in modules/home/storage/default.nix,
# which hardcode this path; honoring XDG_STATE_HOME here alone would make
# the tray silently watch a different directory than they write to.
STATE_DIR = Path.home() / ".local" / "state" / "rclone-bisync"
# Configured pair names (comma-separated), set by the unit from the Nix
# module's bisyncServices list: the single source of truth for which
# pairs must appear even before their first run wrote a state file.
CONFIGURED_PAIRS = tuple(
    name for name in os.environ.get("SYNC_PAIRS", "").split(",") if name
)
REFRESH_SECONDS = 30
# Threshold ladder, derived from the watchdog alert option (env
# SYNC_ALERT_HOURS, set by the unit): warn = alert/2 < watchdog alert
# < crit = alert*1.5, so the tray escalates before and after the watchdog.
try:
    _alert_hours = int(os.environ.get("SYNC_ALERT_HOURS", "48"))
except ValueError:
    _alert_hours = 48
ALERT_HOURS = max(1, _alert_hours)
STALE_WARN_HOURS = max(1, ALERT_HOURS // 2)
STALE_CRIT_HOURS = ALERT_HOURS + ALERT_HOURS // 2

SEV_ORDER = {"idle": 0, "ok": 1, "warn": 2, "crit": 3}
SEV_COLOR = {
    "idle": "#95a5a6",
    "ok": "#2ecc71",
    "warn": "#f39c12",
    "crit": "#e74c3c",
}

# D-Bus names, in one place: the export and the client side must agree.
SNI_INTERFACE = "org.kde.StatusNotifierItem"
MENU_INTERFACE = "com.canonical.dbusmenu"
NOTIFY_NAME = "org.freedesktop.Notifications"
NOTIFY_PATH = "/org/freedesktop/Notifications"
WATCHER_NAME = "org.kde.StatusNotifierWatcher"
WATCHER_PATH = "/StatusNotifierWatcher"
SNI_PATH = "/StatusNotifierItem"
MENU_PATH = "/MenuBar"


def parse_state(path: Path) -> dict[str, str] | None:
    """Parse a KEY=VALUE state file; None when missing or unreadable."""
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return None
    data: dict[str, str] = {}
    for line in text.splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            data[key.strip()] = value.strip()
    return data


def iso_to_epoch(value: str) -> float:
    try:
        return datetime.fromisoformat(value).timestamp()
    except (TypeError, ValueError):
        return 0.0


def systemctl(args: list[str]) -> subprocess.CompletedProcess[bytes]:
    # Read path only (unit_state); it must stay bounded because a wedged
    # user bus must not freeze the Qt event loop it runs on.
    return subprocess.run(
        ["systemctl", "--user", *args],
        check=False,
        capture_output=True,
        timeout=5,
    )


def unit_state(pair: str) -> str:
    """Return the systemd active state string for a pair's unit."""
    # An unhandled exception in a Qt slot aborts the whole tray, so a
    # missing/broken systemctl or a wedged user bus (timeout) must
    # degrade to "unknown" instead.
    try:
        result = systemctl(["is-active", f"rclone-bisync-{pair}"])
    except (OSError, subprocess.SubprocessError):
        return "unknown"
    return result.stdout.decode(errors="replace").strip() or "unknown"


def is_paused(pair: str) -> bool:
    """True when the user deliberately paused this pair via the tray."""
    return (STATE_DIR / f"{pair}.paused").exists()


def pair_status(pair: str, state: dict[str, str] | None) -> tuple[str, str]:
    """Return (severity, detail) for one pair."""
    unit = unit_state(pair)
    if unit == "failed":
        # A crashed service must never be mistaken for a deliberate pause.
        return "crit", "service failed"
    if is_paused(pair):
        # A deliberate pause wins over any non-failed unit state,
        # including the window while a stop job is still finishing or
        # after a failed stop (before the marker rollback lands): the
        # user's intent is what the icon must show.
        return "idle", "paused"
    if unit != "active":
        return "warn", f"service not running ({unit})"
    if state is None:
        return "idle", "no sync recorded yet"
    try:
        exit_code = int(state.get("last_exit", "0"))
    except ValueError:
        exit_code = 1
    if exit_code != 0:
        return "crit", f"failed (exit {exit_code}) at {state.get('last_attempt', '?')}"
    epoch = iso_to_epoch(state.get("last_success", ""))
    if epoch <= 0:
        return "warn", "no successful sync recorded yet"
    age_hours = (time.time() - epoch) / 3600
    stamp = state.get("last_success", "?")
    if age_hours >= STALE_CRIT_HOURS:
        return "crit", f"stale: last success {age_hours:.0f} h ago ({stamp})"
    if age_hours >= STALE_WARN_HOURS:
        return "warn", f"last success {age_hours:.0f} h ago ({stamp})"
    return "ok", f"last success {age_hours:.0f} h ago ({stamp})"


def snapshot() -> dict[str, tuple[str, str]]:
    """Collect (severity, detail) per pair: configured pairs (SYNC_PAIRS)
    plus every state file, so unconfigured leftovers still show up."""
    names: set[str] = set(CONFIGURED_PAIRS)
    names.update(path.stem for path in STATE_DIR.glob("*.state"))
    return {
        name: pair_status(name, parse_state(STATE_DIR / f"{name}.state"))
        for name in sorted(names)
    }


def icon_color(pairs: dict[str, tuple[str, str]]) -> str:
    if not pairs:
        return SEV_COLOR["idle"]
    worst = max(pairs.values(), key=lambda item: SEV_ORDER[item[0]])[0]
    return SEV_COLOR[worst]


def sni_icon_payload(color_hex: str) -> dbus.Array:
    """a(iiay) icon payload for IconPixmap and ToolTip (one marshaling).

    QImage stores ARGB32 pixels in native byte order (little-endian on
    x86) while org.kde.StatusNotifierItem wants big-endian, so every
    4-byte pixel is swapped.
    """
    pixmap = QPixmap(24, 24)
    pixmap.fill(Qt.GlobalColor.transparent)
    painter = QPainter(pixmap)
    painter.setRenderHint(QPainter.RenderHint.Antialiasing)
    painter.setBrush(QColor(color_hex))
    painter.setPen(QColor(color_hex))
    painter.drawEllipse(3, 3, 18, 18)
    painter.end()
    image = pixmap.toImage().convertToFormat(QImage.Format.Format_ARGB32)
    width, height = image.width(), image.height()
    stride = image.bytesPerLine()
    raw = bytes(image.bits().asstring(stride * height))
    rows = []
    for y in range(height):
        row = raw[y * stride:y * stride + width * 4]
        rows.append(b"".join(row[i:i + 4][::-1] for i in range(0, len(row), 4)))
    return dbus.Array(
        [
            dbus.Struct(
                (dbus.Int32(width), dbus.Int32(height), dbus.ByteArray(b"".join(rows))),
                signature="iiay",
            )
        ],
        signature="(iiay)",
    )


def _props_map(props: dict) -> dbus.Dictionary:
    """a{sv} map: the one marshaling spelling of this signature."""
    return dbus.Dictionary(props, signature="sv")


def _layout_node(node_id: int, props: dict, children: list) -> dbus.Struct:
    """(ia{sv}av) dbusmenu layout node; children are nested nodes."""
    return dbus.Struct(
        (
            dbus.Int32(node_id),
            _props_map(props),
            dbus.Array(children, signature="v"),
        ),
        signature="ia{sv}av",
    )


def notify(summary: str, body: str) -> None:
    """Send a desktop notification; any DBus failure degrades to stderr.

    Goes through dbus-python, not QDBusMessage: PyQt6 marshals Python
    values with the wrong types for Notify (int as i where the service
    wants u, empty list as av where it wants as), which strict
    notification servers reject. The call is asynchronous so a wedged
    bus cannot freeze the Qt event loop.
    """
    try:
        obj = dbus.SessionBus().get_object(NOTIFY_NAME, NOTIFY_PATH)
        dbus.Interface(obj, NOTIFY_NAME).Notify(
            "rclone bisync",
            dbus.UInt32(0),
            "",
            summary,
            body,
            dbus.Array([], signature="s"),
            _props_map({}),
            dbus.Int32(10000),
            reply_handler=lambda _id: None,
            error_handler=lambda exc: print(f"notification failed: {exc}", file=sys.stderr),
        )
    except dbus.DBusException as exc:
        print(f"notification failed: {exc.get_dbus_message()}", file=sys.stderr)


def _register_status_notifier_item() -> None:
    """Register the tray with StatusNotifierWatcher.

    The name registered is the serving connection's unique name: the
    exports live on the dbus-python bus, so Qt's own baseService() would
    point at a connection that serves nothing. A missing watcher (no
    Plasma session) just logs; registration is retried when it appears.
    """
    msg = QDBusMessage.createMethodCall(
        WATCHER_NAME, WATCHER_PATH, WATCHER_NAME, "RegisterStatusNotifierItem"
    )
    msg.setArguments([dbus.SessionBus().get_unique_name()])
    # Bounded like systemctl(): a wedged user bus must not freeze the
    # Qt event loop this runs on.
    reply = QDBusConnection.sessionBus().call(msg, QDBus.CallMode.Block, 5000)
    if reply.type() == QDBusMessage.MessageType.ErrorMessage:
        print(f"status notifier registration failed: {reply.errorMessage()}", file=sys.stderr)


def print_status() -> int:
    pairs = snapshot()
    if not pairs:
        print(f"no state files in {STATE_DIR}")
        return 1
    for pair, (severity, detail) in pairs.items():
        print(f"{pair}: {severity}: {detail}")
    return 0


class _BusObject(dbus.service.Object):
    """Exported object with hand-rolled org.freedesktop.DBus.Properties.

    dbus-python has no property decorator, and Plasma reads both the SNI
    and the dbusmenu properties through Get/GetAll only.
    """

    #: main D-Bus interface this object serves
    interface = ""

    def _properties(self) -> dict:
        """name -> already typed value; the registry is the single source."""
        raise NotImplementedError

    @dbus.service.method(
        dbus_interface="org.freedesktop.DBus.Properties",
        in_signature="ss",
        out_signature="v",
    )
    def Get(self, interface, name):
        props = self._properties()
        if interface != self.interface or name not in props:
            raise dbus.DBusException(
                f"unknown property {interface}.{name}",
                name="org.freedesktop.DBus.Error.UnknownProperty",
            )
        return props[name]

    @dbus.service.method(
        dbus_interface="org.freedesktop.DBus.Properties",
        in_signature="s",
        out_signature="a{sv}",
    )
    def GetAll(self, interface):
        if interface != self.interface:
            raise dbus.DBusException(
                f"unknown interface {interface}",
                name="org.freedesktop.DBus.Error.UnknownInterface",
            )
        return _props_map(self._properties())


class StatusNotifierItem(_BusObject):
    """Hand-rolled org.kde.StatusNotifierItem export (ItemIsMenu = True).

    QSystemTrayIcon is not used: it hardcodes ItemIsMenu to false and
    cannot host-render the menu on left click, while a local QMenu popup
    cannot map on a window-less Wayland app. With ItemIsMenu the desktop
    renders the exported menu for both mouse buttons.
    """

    interface = SNI_INTERFACE

    def __init__(self, bus, tray) -> None:
        super().__init__(bus, SNI_PATH)
        self._tray = tray

    def _properties(self) -> dict:
        pixmap = self._tray.icon_payload
        return {
            "Category": dbus.String("ApplicationStatus"),
            "Id": dbus.String("rclone-sync-tray"),
            "Title": dbus.String("rclone bisync"),
            "Status": dbus.String("Active"),
            "WindowId": dbus.UInt32(0),
            "IconThemePath": dbus.String(""),
            "IconName": dbus.String(""),
            "Menu": dbus.ObjectPath(MENU_PATH),
            "ItemIsMenu": dbus.Boolean(True),
            "IconPixmap": pixmap,
            "ToolTip": dbus.Struct(
                (
                    dbus.String(""),
                    pixmap,
                    dbus.String("rclone bisync"),
                    dbus.String(self._tray.tooltip_text),
                ),
                signature="sa(iiay)ss",
            ),
        }

    @dbus.service.method(dbus_interface=SNI_INTERFACE, in_signature="ii")
    def Activate(self, x, y):
        """Left click: the host opens the menu itself (ItemIsMenu)."""

    @dbus.service.method(dbus_interface=SNI_INTERFACE, in_signature="ii")
    def ContextMenu(self, x, y):
        """Right click: the host opens the same menu; nothing to do."""

    @dbus.service.method(dbus_interface=SNI_INTERFACE, in_signature="is")
    def Scroll(self, delta, orientation):
        """No scroll semantics for a status dot."""

    @dbus.service.method(dbus_interface=SNI_INTERFACE, in_signature="")
    def SecondaryActivate(self):
        self._tray.refresh(force=True)

    @dbus.service.signal(dbus_interface=SNI_INTERFACE, signature="")
    def NewIcon(self):
        """Emitted when the cached icon payload changed."""

    @dbus.service.signal(dbus_interface=SNI_INTERFACE, signature="")
    def NewToolTip(self):
        """Emitted when the cached tooltip text changed."""


class MenuExporter(_BusObject):
    """Hand-rolled com.canonical.dbusmenu export over the tray's QMenu.

    PyQt6 wraps no QDBusMenuExporter and its QtDBus cannot express these
    signatures, so the layout is built from the QMenu and marshaled with
    the dbus-python types in _layout_node.
    """

    interface = MENU_INTERFACE

    def __init__(self, bus, menu) -> None:
        super().__init__(bus, MENU_PATH)
        self._menu = menu
        self._by_id: dict = {}
        self._by_action: dict = {}
        self._revision = 0
        self.rebuild()

    def _properties(self) -> dict:
        return {
            "Version": dbus.UInt32(2),
            "Status": dbus.String("normal"),
            "TextDirection": dbus.String("ltr"),
            "IconThemePath": dbus.Array([], signature="s"),
            "Capabilities": dbus.Array([dbus.String("*")], signature="s"),
        }

    def rebuild(self) -> None:
        """Reassign item ids after a model rebuild and push LayoutUpdated.

        Ids are model-local on purpose: a click racing a rebuild must hit
        an unknown id (ignored in Event) instead of the wrong action.
        """
        self._by_id = {}
        self._by_action = {}
        next_id = 1
        for action in self._menu.actions():
            self._by_id[next_id] = action
            self._by_action[action] = next_id
            next_id += 1
        self._revision += 1
        self.LayoutUpdated(dbus.UInt32(self._revision), dbus.Int32(0))

    def _action_props(self, action) -> dict:
        return {
            "type": "separator" if action.isSeparator() else "standard",
            "label": action.text(),
            "enabled": action.isEnabled(),
            "visible": action.isVisible(),
        }

    def _action_node(self, action) -> dbus.Struct:
        # flat by construction (see _fill_menu); the client refetches per
        # submenu if one ever appears
        return _layout_node(self._by_action[action], self._action_props(action), [])

    def _node_for(self, node_id: int) -> dbus.Struct:
        if node_id == 0:
            children = [self._action_node(action) for action in self._menu.actions()]
            return _layout_node(
                0,
                {"children-display": "submenu", "label": "", "enabled": True, "visible": True},
                children,
            )
        action = self._by_id.get(node_id)
        if action is None:
            raise dbus.DBusException(
                f"unknown menu item {node_id}",
                name="org.freedesktop.DBus.Error.InvalidArgs",
            )
        return self._action_node(action)

    @dbus.service.method(
        dbus_interface=MENU_INTERFACE,
        in_signature="iias",
        out_signature="u(ia{sv}av)",
    )
    def GetLayout(self, parent_id, recursion_depth, property_names):
        # property_names is ignored on purpose: clients tolerate full
        # property sets and filtering them would only fork the builder.
        return (dbus.UInt32(self._revision), self._node_for(parent_id))

    @dbus.service.method(
        dbus_interface=MENU_INTERFACE,
        in_signature="aias",
        out_signature="a(ia{sv})",
    )
    def GetGroupProperties(self, ids, property_names):
        items = []
        for item_id in ids:
            action = self._by_id.get(int(item_id))
            if action is not None:
                items.append(
                    dbus.Struct(
                        (
                            dbus.Int32(item_id),
                            _props_map(self._action_props(action)),
                        ),
                        signature="ia{sv}",
                    )
                )
        return items

    @dbus.service.method(dbus_interface=MENU_INTERFACE, in_signature="isvu")
    def Event(self, item_id, event_id, data, timestamp):
        # Handlers run on the GUI thread (the export is served from the
        # Qt loop). Unknown ids are ignored: clicks race rebuilds and
        # must never trigger the wrong action.
        action = self._by_id.get(item_id)
        if event_id == "clicked" and action is not None:
            action.trigger()

    @dbus.service.method(dbus_interface=MENU_INTERFACE, in_signature="i", out_signature="b")
    def AboutToShow(self, item_id):
        # Always False: LayoutUpdated already pushes every rebuild, so a
        # client never has to ask whether it must refetch.
        return False

    @dbus.service.signal(dbus_interface=MENU_INTERFACE, signature="ui")
    def LayoutUpdated(self, revision, parent):
        """Pushed after every rebuild (the only update path we need)."""


class SyncTray(QObject):
    """Aggregate tray icon over all bisync pairs."""

    def __init__(self) -> None:
        super().__init__()
        # One persistent QMenu for the icon's whole lifetime, repopulated
        # in place: the exporters read it live, and its actions must be
        # parented to it (a parentless QAction is garbage-collected and
        # the menu export would silently go empty).
        self._menu = QMenu()
        self._busy: set[str] = set()
        # Icon payload is a pure function of the color, so the cache key
        # is the color; "" forces the first refresh to fill the payload.
        self._icon_color = ""
        self.icon_payload = dbus.Array([], signature="(iiay)")
        self.tooltip_text = ""
        self._last_pairs: dict[str, tuple[str, str]] | None = None
        # Both interfaces must be served by one connection (the Menu
        # property is an object path on this same service), so the
        # session bus is dbus-python's, driven by the Qt event loop.
        bus = dbus.SessionBus()
        self._menu_exporter = MenuExporter(bus, self._menu)
        self._sni = StatusNotifierItem(bus, self)
        self.refresh()
        # Export first (done above), then register: the watcher may call
        # back into the export the moment registration succeeds.
        _register_status_notifier_item()
        self._watcher = QDBusServiceWatcher(self)
        # PyQt6 has no WatchForOwnerChange flag; the registration and
        # unregistration events together cover a kded6 restart, which is
        # exactly when the watcher loses and regains its owner.
        self._watcher.setWatchMode(
            QDBusServiceWatcher.WatchModeFlag.WatchForRegistration
            | QDBusServiceWatcher.WatchModeFlag.WatchForUnregistration
        )
        self._watcher.addWatchedService(WATCHER_NAME)
        self._watcher.serviceOwnerChanged.connect(self._on_watcher_owner)
        timer = QTimer(self)
        timer.setInterval(REFRESH_SECONDS * 1000)
        timer.timeout.connect(self.refresh)
        timer.start()

    def refresh(self, force: bool = False) -> None:
        pairs = snapshot()
        color = icon_color(pairs)
        if color != self._icon_color:
            self._icon_color = color
            self.icon_payload = sni_icon_payload(color)
            self._sni.NewIcon()
        tooltip = "\n".join(f"{pair}: {detail}" for pair, (_, detail) in pairs.items())
        if tooltip != self.tooltip_text:
            self.tooltip_text = tooltip
            self._sni.NewToolTip()
        if force or pairs != self._last_pairs:
            self._last_pairs = pairs
            self._fill_menu(pairs)

    def _fill_menu(self, pairs: dict[str, tuple[str, str]]) -> None:
        menu = self._menu
        menu.clear()
        if not pairs:
            # Also covers pairs configured but not yet synced once: no
            # .state file exists during the startDelay window.
            empty = menu.addAction("no sync state yet")
            empty.setEnabled(False)
        else:
            for pair, (severity, detail) in pairs.items():
                busy = pair in self._busy
                header = menu.addAction(f"{pair} [{severity}]: {detail}")
                header.setEnabled(False)
                sync_now = menu.addAction("Sync now")
                sync_now.triggered.connect(lambda _=False, p=pair: self._control(p, "restart"))
                # A paused pair's wrapper exits 0 on sight (pause marker), so a
                # restart there would silently do nothing; Resume is the path.
                sync_now.setEnabled(not busy and not is_paused(pair))
                if is_paused(pair):
                    toggle = menu.addAction("Resume")
                    toggle.triggered.connect(lambda _=False, p=pair: self._control(p, "start"))
                else:
                    toggle = menu.addAction("Pause")
                    toggle.triggered.connect(lambda _=False, p=pair: self._control(p, "stop"))
                toggle.setEnabled(not busy)
                open_log = menu.addAction("Open log")
                open_log.triggered.connect(lambda _=False, p=pair: self._open_log(p))
                menu.addSeparator()
            refresh_action = menu.addAction("Refresh now")
            # Force: with no state change the data gate would skip the rebuild
            # the user just explicitly asked for.
            refresh_action.triggered.connect(lambda: self.refresh(force=True))
        self._menu_exporter.rebuild()

    def _on_watcher_owner(self, _name: str, _old: str, new: str) -> None:
        # kded6 (re)start: the watcher went away and came back, and it
        # forgot every registered item in between.
        if new:
            _register_status_notifier_item()

    def _control(self, pair: str, action: str) -> None:
        if pair in self._busy:
            # One control job per pair: concurrent clicks would race the
            # marker ordering and the rollback in _control_done.
            return
        marker = STATE_DIR / f"{pair}.paused"
        args: list[str]
        if action == "restart":
            args = ["restart", f"rclone-bisync-{pair}"]
        elif action == "stop":
            # Durable pause: write the marker (honored by the wrapper at
            # boot) and stop both timer and service so nothing respawns
            # the pair until Resume.
            marker.touch()
            args = ["stop", f"rclone-bisync-{pair}.timer", f"rclone-bisync-{pair}"]
        elif action == "start":
            marker.unlink(missing_ok=True)
            args = ["start", f"rclone-bisync-{pair}.timer", f"rclone-bisync-{pair}"]
        else:
            return
        # systemctl waits for the job to finish, and a SIGINT shutdown of a
        # mid-transfer rclone can take a while; blocking the Qt event loop
        # would freeze icon and menu. Run it async and report the outcome;
        # if the job fails, the marker rollback is done in _control_done.
        self._busy.add(pair)
        proc = QProcess(self)
        proc.finished.connect(
            lambda code, _status: self._control_done(pair, action, code, proc)
        )
        # FailedToStart never emits finished; route it through the same
        # completion path so the rollback and refresh still run. Crashes
        # do emit finished, so only the spawn failure is handled here.
        proc.errorOccurred.connect(
            lambda err: self._control_done(pair, action, 1, proc)
            if err == QProcess.ProcessError.FailedToStart
            else None
        )
        proc.start("systemctl", ["--user", *args])

    def _control_done(self, pair: str, action: str, code: int, proc: QProcess) -> None:
        stderr = bytes(proc.readAllStandardError()).decode(errors="replace").strip()
        proc.deleteLater()
        self._busy.discard(pair)
        if code != 0:
            notify(
                "rclone bisync",
                f"{action} {pair} failed: {stderr or 'unknown systemctl error'}",
            )
            # Roll the marker back so it always equals "actually paused":
            # a failed stop must not leave a durable pause (the wrapper
            # honors it at boot), and a failed start must not destroy one.
            marker = STATE_DIR / f"{pair}.paused"
            if action == "stop":
                marker.unlink(missing_ok=True)
            elif action == "start":
                marker.touch()
        self.refresh(force=True)

    def _open_log(self, pair: str) -> None:
        log = STATE_DIR / "logs" / f"{pair}.log"
        if not log.exists():
            # rclone creates the file on first write; before that (or for a
            # pair paused since before its first run) the journal is all
            # there is.
            notify(
                "rclone bisync",
                f"no log for {pair} yet; see journalctl --user -u rclone-bisync-{pair}",
            )
            return
        # startDetached lets the system reap the child; an unwaited Popen
        # would linger as a zombie for the tray's lifetime.
        ok, _pid = QProcess.startDetached("xdg-open", [str(log)])
        if not ok:
            notify("rclone bisync", "could not launch a log viewer (xdg-open missing?)")


def main() -> int:
    parser = argparse.ArgumentParser(description="rclone bisync tray indicator")
    parser.add_argument("--status", action="store_true", help="print status and exit")
    args = parser.parse_args()
    if args.status:
        return print_status()
    app = QApplication(sys.argv)
    app.setQuitOnLastWindowClosed(False)
    # One event loop for Qt and D-Bus: the exports are served from the Qt
    # loop, so menu Event clicks run the QAction handlers on the GUI thread.
    DBusQtMainLoop(set_as_default=True)
    # Keep the tray alive on the app: a collected tray would take the
    # menu and the D-Bus exports down with it.
    app._tray = SyncTray()
    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())
