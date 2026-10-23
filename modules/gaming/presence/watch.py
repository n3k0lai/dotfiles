#!/usr/bin/env python3
"""Discord presence for the games on this machine.

World of Warcraft: the Forever addon paints an 8px color strip. On a
Wayland session this process screenshots that strip and publishes
character, level, and place. Without a compositor it still publishes
"World of Warcraft" while the game process is running.

Minecraft: a running game (Prism Launcher or a vanilla launcher) publishes
the instance, world, and dimension. The title on Discord is Minecraft via
CraftPresence's public application id.

Toggle with `presence on|off|toggle|status`. `auto` plus `hours` keeps it
quiet on a weekday schedule. `wow-presence` is the same command.
"""

from __future__ import annotations

import gzip
import json
import os
import re
import signal
import socket
import struct
import subprocess
import sys
import time
from pathlib import Path

# Public application whose Discord name is World of Warcraft.
WOW_CLIENT_ID = "805124430774272000"
WOW_APP_NAME = "World of Warcraft"
# CraftPresence's public application. Discord shows this as Minecraft,
# and the "grass" asset is the default icon on that application.
MINECRAFT_CLIENT_ID = "450485984333660181"
MINECRAFT_APP_NAME = "Minecraft"

# Keep in lockstep with KissPresence.lua.
SYNC = (5, 0, 5, 0, 5, 0, 7, 0)
PALETTE = (
    # Index 0 is orange. WoW does not paint real black, so those cells
    # show the world and the reader treats a non-color as 0.
    (255, 128, 0),
    (255, 0, 0),
    (0, 255, 0),
    (0, 0, 255),
    (255, 255, 0),
    (255, 0, 255),
    (0, 255, 255),
    (255, 255, 255),
)
COLOR_MAX_DISTANCE = 140

CONFIG_DIR = Path.home() / ".config" / "kiss-presence"
MODE_PATH = CONFIG_DIR / "mode"
HOURS_PATH = CONFIG_DIR / "hours"
STATE_PATH = CONFIG_DIR / "state.json"

WOW_TITLE = ("world of warcraft", "wowb", "wow")
POLL_SECONDS = 0.7
GONE_SECONDS = 90
DAY_INDEX = {"mon": 0, "tue": 1, "wed": 2, "thu": 3, "fri": 4, "sat": 5, "sun": 6}


def config_dir() -> Path:
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    return CONFIG_DIR


def read_mode() -> str:
    try:
        mode = MODE_PATH.read_text().strip().lower()
    except FileNotFoundError:
        return "on"
    return mode if mode in {"on", "off", "auto"} else "on"


def write_mode(mode: str) -> None:
    config_dir()
    MODE_PATH.write_text(mode + "\n")


def read_hours() -> str:
    try:
        return HOURS_PATH.read_text().strip()
    except FileNotFoundError:
        return ""


def write_hours(text: str) -> None:
    config_dir()
    HOURS_PATH.write_text(text.strip() + ("\n" if text.strip() else ""))


def parse_hours(text: str) -> tuple[set[int], int, int] | None:
    """`mon-fri 09:00-17:00` or `mon,wed 09:00-17:30`."""
    text = text.strip().lower()
    if not text:
        return None
    parts = text.split()
    if len(parts) != 2 or "-" not in parts[1]:
        raise ValueError("use mon-fri 09:00-17:00")
    day_spec, span = parts
    start_s, end_s = span.split("-", 1)

    def minutes(value: str) -> int:
        hour, minute = value.split(":")
        hour_i, minute_i = int(hour), int(minute)
        if not (0 <= hour_i <= 23 and 0 <= minute_i <= 59):
            raise ValueError("clock time out of range")
        return hour_i * 60 + minute_i

    start, end = minutes(start_s), minutes(end_s)
    if start == end:
        raise ValueError("work start and end are the same")
    days: set[int] = set()
    for chunk in day_spec.split(","):
        if "-" in chunk:
            left, right = chunk.split("-", 1)
            a, b = DAY_INDEX[left], DAY_INDEX[right]
            if a <= b:
                days.update(range(a, b + 1))
            else:
                days.update(list(range(a, 7)) + list(range(0, b + 1)))
        else:
            days.add(DAY_INDEX[chunk])
    return days, start, end


def in_work_hours(now: time.struct_time | None = None) -> bool:
    spec = read_hours()
    if not spec:
        return False
    try:
        parsed = parse_hours(spec)
    except (ValueError, KeyError):
        return False
    if parsed is None:
        return False
    days, start, end = parsed
    now = now or time.localtime()
    if now.tm_wday not in days:
        return False
    minute = now.tm_hour * 60 + now.tm_min
    if start < end:
        return start <= minute < end
    return minute >= start or minute < end


def publishing_enabled() -> bool:
    mode = read_mode()
    if mode == "off":
        return False
    if mode == "auto" and in_work_hours():
        return False
    return True


def write_state(**fields: object) -> None:
    config_dir()
    current: dict[str, object] = {}
    try:
        current = json.loads(STATE_PATH.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        current = {}
    current.update(fields)
    current["mode"] = read_mode()
    current["hours"] = read_hours()
    current["work_hours_now"] = in_work_hours()
    current["publishing"] = publishing_enabled()
    STATE_PATH.write_text(json.dumps(current, indent=2) + "\n")


def pack_symbols(payload: bytes) -> list[int]:
    if len(payload) > 72:
        payload = payload[:72]
    bits: list[int] = []

    def push(value: int, width: int) -> None:
        for shift in range(width - 1, -1, -1):
            bits.append((value >> shift) & 1)

    push(len(payload), 8)
    checksum = 0
    for byte in payload:
        push(byte, 8)
        checksum ^= byte
    push(checksum, 8)
    while len(bits) % 3:
        bits.append(0)
    symbols = list(SYNC)
    for index in range(0, len(bits), 3):
        symbols.append((bits[index] << 2) | (bits[index + 1] << 1) | bits[index + 2])
    return symbols


def unpack_symbols(symbols: list[int], allow_clipped: bool = False) -> bytes | None:
    if len(symbols) < len(SYNC) or tuple(symbols[: len(SYNC)]) != SYNC:
        return None
    bits: list[int] = []
    for symbol in symbols[len(SYNC) :]:
        if not 0 <= symbol <= 7:
            return None
        bits.extend(((symbol >> 2) & 1, (symbol >> 1) & 1, symbol & 1))
    if len(bits) < 16:
        return None

    def take(width: int, cursor: list[int]) -> int | None:
        if cursor[0] + width > len(bits):
            return None
        value = 0
        for _ in range(width):
            value = (value << 1) | bits[cursor[0]]
            cursor[0] += 1
        return value

    cursor = [0]
    length = take(8, cursor)
    if length is None or not 1 <= length <= 72:
        return None
    payload = bytearray()
    for _ in range(length):
        byte = take(8, cursor)
        if byte is None:
            return None
        payload.append(byte)
    checksum = take(8, cursor)
    expect = 0
    for byte in payload:
        expect ^= byte
    if checksum is None:
        # The column runs off the bottom of a 1440p frame, so the checksum
        # cell is often clipped. Only used when no verified read exists.
        if not allow_clipped:
            return None
        text = bytes(payload)
        parts = text.split(b"|")
        if len(parts) == 7 and parts[0] and parts[1].isdigit() and all(32 <= b < 127 for b in text):
            return text
        return None
    if checksum != expect:
        return None
    return bytes(payload)


def nearest_symbol(pixel: tuple[int, int, int]) -> int | None:
    best_index = None
    best_distance = COLOR_MAX_DISTANCE + 1
    for index, color in enumerate(PALETTE):
        distance = abs(pixel[0] - color[0]) + abs(pixel[1] - color[1]) + abs(pixel[2] - color[2])
        if distance < best_distance:
            best_distance = distance
            best_index = index
    if best_distance > COLOR_MAX_DISTANCE:
        return None
    return best_index


def parse_ppm(data: bytes) -> tuple[int, int, list[tuple[int, int, int]]]:
    if not data.startswith(b"P6"):
        raise ValueError("grim did not return a PPM")
    header, _, rest = data.partition(b"\n")
    # Comments and the dimension line. grim writes "P6\nW H\n255\n".
    lines: list[bytes] = []
    blob = rest
    while len(lines) < 2:
        line, _, blob = blob.partition(b"\n")
        if line.startswith(b"#"):
            continue
        lines.append(line)
    width, height = (int(part) for part in lines[0].split())
    if lines[1] != b"255":
        raise ValueError("unexpected PPM depth")
    needed = width * height * 3
    if len(blob) < needed:
        raise ValueError("short PPM")
    pixels = [
        (blob[i], blob[i + 1], blob[i + 2])
        for i in range(0, needed, 3)
    ]
    return width, height, pixels


def decode_image(width: int, height: int, pixels: list[tuple[int, int, int]], allow_clipped: bool = False) -> bytes | None:
    symbols = [nearest_symbol(pixel) for pixel in pixels]
    max_cells = 8 + ((8 + 72 * 8 + 8 + 2) // 3) + 2
    search_w = width

    def at(x: int, y: int) -> int | None:
        if not 0 <= x < width or not 0 <= y < height:
            return None
        return symbols[y * width + x]

    # First sync cell is magenta. UI scale and render scale change the pitch,
    # so try a pitch at each magenta pixel instead of assuming a size.
    for y in range(height):
        row = y * width
        for x in range(search_w):
            if symbols[row + x] != 5:
                continue
            for cell in range(2, 24):
                decoded = _sample_from(at, x, y, cell, height, max_cells, allow_clipped)
                if decoded:
                    return decoded
                decoded = _sample_grid(at, x, y, cell, width, height, max_cells, allow_clipped)
                if decoded:
                    return decoded
    return None


def read_strip(width: int, height: int, pixels: list[tuple[int, int, int]]) -> bytes | None:
    verified = decode_image(width, height, pixels, False)
    if verified:
        return verified
    return decode_image(width, height, pixels, True)


def _seen(symbol: int | None, expected: int) -> bool:
    if symbol == expected:
        return True
    # Black cells are not drawn, so the world shows through.
    return expected == 0 and symbol is None


def _read_symbol(symbol: int | None) -> int | None:
    if symbol is None:
        return 0
    return symbol


def _sample_grid(at, x: int, y: int, cell: int, width: int, height: int, max_cells: int, allow_clipped: bool = False) -> bytes | None:
    """First row is the 8-cell sync, then the payload continues left to right."""
    cols = len(SYNC)
    for index, expected in enumerate(SYNC):
        if not _seen(at(x + index * cell, y), expected):
            return None
    symbols: list[int] = []
    for index in range(max_cells):
        col = index % cols
        row = index // cols
        symbol = _read_symbol(at(x + col * cell, y + row * cell))
        if symbol is None:
            break
        symbols.append(symbol)
        decoded = unpack_symbols(symbols, allow_clipped)
        if decoded:
            return decoded
    return None


def _sample_from(at, x: int, y: int, cell: int, height: int, max_cells: int, allow_clipped: bool = False) -> bytes | None:
    for index, expected in enumerate(SYNC):
        sample_y = y + index * cell
        if sample_y >= height or not _seen(at(x, sample_y), expected):
            return None
    centers: list[float] = []
    for index, expected in enumerate(SYNC):
        if expected == 0:
            continue
        guess = int(round(y + index * cell))
        lo = hi = guess
        while lo > 0 and at(x, lo - 1) == expected:
            lo -= 1
        while hi + 1 < height and at(x, hi + 1) == expected:
            hi += 1
        centers.append((index, (lo + hi) / 2))
    if len(centers) < 2:
        return None
    estimated = (centers[-1][1] - centers[0][1]) / (centers[-1][0] - centers[0][0])
    if estimated < 3:
        return None
    origin = centers[0][1] - centers[0][0] * estimated
    # Sync is only a few visible cells, so the pitch estimate is a bit coarse.
    for step in range(-8, 9):
        pitch = estimated + step * 0.02
        symbols: list[int] = []
        failed = False
        for index in range(max_cells):
            sample_y = int(round(origin + index * pitch))
            if sample_y >= height:
                break
            symbol = _read_symbol(at(x, sample_y))
            if symbol is None:
                failed = True
                break
            symbols.append(symbol)
            if index < len(SYNC) and symbol != SYNC[index]:
                failed = True
                break
            decoded = unpack_symbols(symbols, allow_clipped)
            if decoded:
                return decoded
        if failed:
            continue
    return None


def presence_fields(payload: str) -> dict[str, str] | None:
    parts = payload.split("|")
    if len(parts) != 7:
        return None
    name, level, class_name, class_key, faction, zone, subzone = parts
    if not name or not level.isdigit() or not zone:
        return None
    place = f"{subzone}, {zone}" if subzone else zone
    details = f"{name}: lvl {level} {class_name}".strip()
    activity: dict[str, object] = {
        "type": 0,
        "name": WOW_APP_NAME,
        "details": details[:128],
        "state": place[:128],
        "instance": False,
    }
    activity["assets"] = {"large_image": "wow_icon", "large_text": class_name or WOW_APP_NAME}
    return {
        "details": details,
        "state": place,
        "activity": activity,
        "client_id": WOW_CLIENT_ID,
    }


def discord_sockets() -> list[Path]:
    found: list[Path] = []
    runtime = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
    bases = [
        Path(runtime),
        Path.home() / "Library/Application Support/discord",
        Path.home() / "Library/Application Support/vesktop",
        Path.home() / "Library/Application Support/Vesktop",
        Path.home() / ".config/discord",
        Path.home() / ".config/vesktop",
        Path("/tmp"),
        Path(os.environ.get("TMPDIR", "/tmp")),
    ]
    seen: set[Path] = set()
    for base in bases:
        for index in range(10):
            path = base / f"discord-ipc-{index}"
            if path in seen or not path.exists():
                continue
            seen.add(path)
            found.append(path)
    return found


class DiscordIPC:
    def __init__(self) -> None:
        self.sock: socket.socket | None = None
        self.client_id: str | None = None
        self.started_at = int(time.time())

    def close(self) -> None:
        if self.sock is not None:
            try:
                self.sock.close()
            except OSError:
                pass
            self.sock = None

    def _connect(self, client_id: str) -> None:
        self.close()
        last_error: Exception | None = None
        sockets = discord_sockets()
        if not sockets:
            raise ConnectionError("discord is not running")
        for path in sockets:
            sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            sock.settimeout(5)
            try:
                sock.connect(str(path))
            except OSError as exc:
                last_error = exc
                sock.close()
                continue
            self.sock = sock
            try:
                self._send(0, {"v": 1, "client_id": client_id})
                ready = self._recv()
            except (OSError, ConnectionError, json.JSONDecodeError, TimeoutError) as exc:
                last_error = exc
                self.close()
                continue
            if ready.get("evt") == "READY" or ready.get("cmd") == "DISPATCH":
                username = str(((ready.get("data") or {}).get("user") or {}).get("username") or "")
                # Vesktop's arRPC stub answers as "arrpc" and does not publish.
                if username.lower() == "arrpc":
                    last_error = ConnectionError(f"{path} is vesktop arrpc")
                    self.close()
                    continue
                self.client_id = client_id
                return
            last_error = ConnectionError(f"discord handshake failed: {ready.get('evt') or ready.get('cmd')}")
            self.close()
        raise ConnectionError(str(last_error or "discord handshake failed"))

    def _send(self, op: int, payload: dict) -> None:
        if self.sock is None:
            raise ConnectionError("discord socket is closed")
        data = json.dumps(payload).encode()
        self.sock.sendall(struct.pack("<II", op, len(data)) + data)

    def _recv(self) -> dict:
        if self.sock is None:
            raise ConnectionError("discord socket is closed")
        header = self._read_exact(8)
        _op, length = struct.unpack("<II", header)
        body = self._read_exact(length)
        return json.loads(body.decode())

    def _read_exact(self, length: int) -> bytes:
        if self.sock is None:
            raise ConnectionError("discord socket is closed")
        chunks = []
        remaining = length
        while remaining:
            chunk = self.sock.recv(remaining)
            if not chunk:
                raise ConnectionError("discord socket closed")
            chunks.append(chunk)
            remaining -= len(chunk)
        return b"".join(chunks)

    def set_activity(self, activity: dict | None, client_id: str) -> None:
        if self.client_id != client_id:
            self.close()
        payload = None
        if activity is not None:
            payload = dict(activity)
            payload["timestamps"] = {"start": self.started_at}
        last_error = None
        for _ in range(2):
            try:
                if self.sock is None:
                    self._connect(client_id)
                self._send(1, {
                    "cmd": "SET_ACTIVITY",
                    "nonce": str(time.time()),
                    "args": {"pid": os.getpid(), "activity": payload},
                })
                response = self._recv()
                data = response.get("data") or {}
                if isinstance(data, dict) and data.get("code"):
                    message = str(data.get("message") or "discord rejected the activity")
                    if payload and payload.get("assets") and "asset" in message.lower():
                        payload = dict(payload)
                        payload.pop("assets", None)
                        self.close()
                        continue
                    raise ConnectionError(message)
                return
            except (OSError, ConnectionError, json.JSONDecodeError, TimeoutError) as exc:
                last_error = exc
                self.close()
        if last_error:
            raise last_error


def prepare_session_env() -> None:
    runtime = Path(os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}")
    os.environ.setdefault("XDG_RUNTIME_DIR", str(runtime))
    if "WAYLAND_DISPLAY" not in os.environ:
        for name in ("wayland-1", "wayland-0"):
            if (runtime / name).exists():
                os.environ["WAYLAND_DISPLAY"] = name
                break
    if "HYPRLAND_INSTANCE_SIGNATURE" not in os.environ:
        hypr = runtime / "hypr"
        if hypr.is_dir():
            signatures = sorted(path.name for path in hypr.iterdir() if path.is_dir())
            if signatures:
                os.environ["HYPRLAND_INSTANCE_SIGNATURE"] = signatures[0]


DIMENSIONS = {
    "minecraft:overworld": "Overworld",
    "minecraft:the_nether": "The Nether",
    "minecraft:the_end": "The End",
}


def iter_cmdlines():
    proc = Path("/proc")
    if proc.is_dir():
        for entry in proc.iterdir():
            if not entry.name.isdigit():
                continue
            try:
                raw = (entry / "cmdline").read_bytes()
            except OSError:
                continue
            if raw:
                yield raw.replace(b"\x00", b" ").decode("utf-8", "replace")
        return
    try:
        raw = subprocess.check_output(["ps", "-ax", "-o", "command="], text=True, timeout=3)
    except (subprocess.SubprocessError, OSError):
        return
    for line in raw.splitlines():
        if line.strip():
            yield line


def _is_minecraft_game(cmdline: str) -> bool:
    lowered = cmdline.lower()
    if "watch.py" in lowered or "presence.nix" in lowered:
        return False
    if "net.minecraft.client.main" in lowered or "net.minecraft.client.main.main" in lowered:
        return True
    if "--gamedir" in lowered and "minecraft" in lowered:
        return True
    if "prismlauncher" in lowered and "minecraft" in lowered and "java" in lowered:
        return True
    return False


def _game_dir_from_cmd(cmdline: str) -> Path | None:
    parts = cmdline.split()
    for index, part in enumerate(parts):
        if part == "--gameDir" and index + 1 < len(parts):
            return Path(parts[index + 1])
        if part.startswith("--gameDir="):
            return Path(part.split("=", 1)[1])
    for part in parts:
        if part.endswith("/minecraft") or part.endswith("/.minecraft") or part.endswith("\\.minecraft"):
            path = Path(part)
            if path.is_dir():
                return path
    return None


def minecraft_session() -> tuple[Path | None, str] | None:
    """Return (game directory, instance name) while Minecraft itself is running."""
    generic = False
    for cmdline in iter_cmdlines():
        if not _is_minecraft_game(cmdline):
            continue
        game_dir = _game_dir_from_cmd(cmdline)
        if game_dir is not None:
            instance = game_dir.parent.name if game_dir.name in {"minecraft", ".minecraft"} else game_dir.name
            return game_dir, instance
        generic = True
    if not generic:
        return None
    home = Path.home()
    for candidate in (home / ".minecraft", home / "Library/Application Support/minecraft"):
        if candidate.is_dir():
            return candidate, "Minecraft"
    return None, "Minecraft"


def nbt_string_after(data: bytes, key: bytes) -> str | None:
    start = 0
    while True:
        index = data.find(key, start)
        if index < 0:
            return None
        cursor = index + len(key)
        if cursor + 2 > len(data):
            return None
        length = int.from_bytes(data[cursor:cursor + 2], "big")
        cursor += 2
        if 0 < length <= 120 and cursor + length <= len(data):
            text = data[cursor:cursor + length].decode("utf-8", "replace")
            if text and all(32 <= ord(ch) < 127 or ch in " ',-" for ch in text):
                return text
        start = index + 1


def world_snapshot(game_dir: Path | None) -> dict[str, str]:
    info = {"instance": "", "world": "", "dimension": "", "player": "", "server": ""}
    if game_dir is None or not game_dir.is_dir():
        return info
    log = game_dir / "logs" / "latest.log"
    try:
        lines = log.read_text(errors="replace").splitlines()
    except OSError:
        lines = []
    for line in reversed(lines):
        if not info["player"] and "Setting user:" in line:
            info["player"] = line.rsplit("Setting user:", 1)[1].strip()
        if not info["server"] and "Connecting to " in line:
            info["server"] = line.rsplit("Connecting to ", 1)[1].strip().rstrip(".")
        if info["player"] and info["server"]:
            break
    saves = game_dir / "saves"
    world = None
    newest = 0.0
    if saves.is_dir():
        for entry in saves.iterdir():
            if not entry.is_dir():
                continue
            lock = entry / "session.lock"
            stamp = lock.stat().st_mtime if lock.exists() else 0
            if stamp > newest:
                newest = stamp
                world = entry
    if world is None:
        return info
    level = world / "level.dat"
    try:
        blob = gzip.decompress(level.read_bytes())
    except (OSError, gzip.BadGzipFile, EOFError):
        blob = b""
    info["world"] = nbt_string_after(blob, b"LevelName") or world.name
    dimension = nbt_string_after(blob, b"Dimension")
    if dimension in DIMENSIONS:
        info["dimension"] = DIMENSIONS[dimension]
    elif dimension and dimension.startswith("minecraft:"):
        info["dimension"] = dimension.split(":", 1)[1].replace("_", " ").title()
    return info


def minecraft_fields(game_dir: Path | None, instance: str) -> dict[str, object]:
    snap = world_snapshot(game_dir)
    snap["instance"] = instance
    if snap["world"]:
        who = f"{snap['player']} — {snap['world']}" if snap["player"] else snap["world"]
        where = snap["dimension"] or "Singleplayer"
    elif snap["server"]:
        who = snap["player"] or instance or MINECRAFT_APP_NAME
        where = snap["server"]
    else:
        who = instance or MINECRAFT_APP_NAME
        where = "In the menu"
    activity: dict[str, object] = {
        "type": 0,
        "name": MINECRAFT_APP_NAME,
        "details": who[:128],
        "state": where[:128],
        "instance": False,
        "assets": {"large_image": "grass", "large_text": (instance or MINECRAFT_APP_NAME)[:128]},
    }
    return {"details": who, "state": where, "activity": activity, "client_id": MINECRAFT_CLIENT_ID}


def wow_pid() -> int | None:
    proc = Path("/proc")
    if not proc.is_dir():
        return None
    for entry in proc.iterdir():
        if not entry.name.isdigit():
            continue
        try:
            cmdline = (entry / "cmdline").read_bytes().replace(b"\x00", b" ").decode("utf-8", "replace").lower()
        except OSError:
            continue
        if "watch.py" in cmdline:
            continue
        if any(token in cmdline for token in ("wowb.exe", "wow.exe", "wowclassic.exe")):
            return int(entry.name)
    return None


def wow_process() -> bool:
    if wow_pid() is not None:
        return True
    for cmdline in iter_cmdlines():
        lowered = cmdline.lower()
        if "world of warcraft.app" in lowered and "watch.py" not in lowered:
            return True
    return False


def wow_process_started() -> float | None:
    pid = wow_pid()
    if pid is None:
        return None
    try:
        stat = Path(f"/proc/{pid}/stat").read_text()
        fields = stat.rsplit(")", 1)[1].split()
        start_ticks = int(fields[19])
        hz = os.sysconf("SC_CLK_TCK")
        btime = 0.0
        for line in Path("/proc/stat").read_text().splitlines():
            if line.startswith("btime "):
                btime = float(line.split()[1])
                break
        return btime + start_ticks / hz
    except (OSError, IndexError, ValueError):
        return None


def wow_data_dirs() -> list[Path]:
    home = Path.home()
    bases = [
        home / "Games/battlenet/drive_c/Program Files (x86)/World of Warcraft",
        home / "Games/World of Warcraft",
    ]
    found: list[Path] = []
    for base in bases:
        if not base.is_dir():
            continue
        if (base / "WTF").is_dir():
            found.append(base)
        try:
            children = list(base.iterdir())
        except OSError:
            continue
        for child in children:
            if (child / "WTF").is_dir():
                found.append(child)
    return found


def wow_general_log() -> Path | None:
    newest: Path | None = None
    newest_m = 0.0
    for root in wow_data_dirs():
        path = root / "Logs/General.log"
        try:
            modified = path.stat().st_mtime
        except OSError:
            continue
        if modified >= newest_m:
            newest_m = modified
            newest = path
    return newest


def wow_screen() -> str:
    """login, character, or world, from the glue log."""
    path = wow_general_log()
    screen = "login"
    if path is None:
        return screen
    try:
        lines = path.read_text(errors="replace").splitlines()
    except OSError:
        return screen
    for line in lines:
        if 'Switching to screen="AccountLogin"' in line or 'to="login"' in line:
            screen = "login"
        elif 'Switching to screen="CharacterSelect"' in line or 'to="charselect"' in line:
            screen = "character"
        elif "[Glues] Suspend()" in line and screen == "character":
            screen = "world"
    return screen


# Warcraft Wiki zone screenshots. Discord fetches the URL.
# Character portraits are not stored in the WTF config, so there is no small image.
ZONE_ART = {
    "Dun Morogh": "https://warcraft.wiki.gg/images/thumb/Dun_Morogh.jpg/512px-Dun_Morogh.jpg",
}


def presence_assets(zone: str | None, class_name: str | None) -> dict[str, str] | None:
    if not zone or zone not in ZONE_ART:
        return None
    return {
        "large_image": ZONE_ART[zone],
        "large_text": zone,
    }


CLASS_BY_ID = {
    "1": "Warrior",
    "2": "Paladin",
    "3": "Hunter",
    "4": "Rogue",
    "5": "Priest",
    "6": "Death Knight",
    "7": "Shaman",
    "8": "Mage",
    "9": "Warlock",
    "10": "Monk",
    "11": "Druid",
    "12": "Demon Hunter",
    "13": "Evoker",
}


def wow_character_dir() -> Path | None:
    best: Path | None = None
    best_m = 0.0
    for root in wow_data_dirs():
        try:
            accounts = (root / "WTF/Account").iterdir()
        except OSError:
            continue
        for account in accounts:
            try:
                realms = list(account.iterdir())
            except OSError:
                continue
            for realm in realms:
                if not realm.is_dir() or realm.name == "SavedVariables":
                    continue
                try:
                    characters = list(realm.iterdir())
                except OSError:
                    continue
                for character in characters:
                    if not character.is_dir() or "-" not in character.name:
                        continue
                    try:
                        modified = character.stat().st_mtime
                    except OSError:
                        continue
                    if modified >= best_m:
                        best_m = modified
                        best = character
    return best


def wow_character_name() -> str | None:
    character = wow_character_dir()
    if character is None:
        return None
    # Folders are First-Rest, for example Hippo-Himbopotamus.
    return character.name.replace("-", " ")


def wow_character_class(character: Path | None) -> str | None:
    if character is None:
        return None
    try:
        text = (character / "config-cache.wtf").read_text(errors="replace")
    except OSError:
        return None
    match = re.search(r'SET EJLootClass "(\d+)"', text)
    if not match:
        return None
    return CLASS_BY_ID.get(match.group(1))


def persisted_zone() -> str | None:
    path = config_dir() / "zone"
    try:
        text = path.read_text().strip()
    except OSError:
        return None
    if text in {"", "In game", "Login screen", "Character select"}:
        return None
    return text


def remember_zone(zone: str) -> None:
    path = config_dir() / "zone"
    try:
        path.write_text(zone + "\n")
    except OSError:
        pass


_last_zone: str | None = None


def wow_window_visible(window: tuple[int, int, int, int]) -> bool:
    try:
        clients = json.loads(subprocess.check_output(["hyprctl", "clients", "-j"], text=True, timeout=3))
        monitors = json.loads(subprocess.check_output(["hyprctl", "monitors", "-j"], text=True, timeout=3))
    except (subprocess.SubprocessError, json.JSONDecodeError, OSError):
        return False
    x, y, width, height = window
    workspace = None
    for client in clients:
        if client.get("title") != "World of Warcraft":
            continue
        at = client.get("at") or [None, None]
        size = client.get("size") or [None, None]
        if at == [x, y] and size == [width, height]:
            workspace = (client.get("workspace") or {}).get("id")
            break
    if workspace is None:
        return False
    return any((mon.get("activeWorkspace") or {}).get("id") == workspace for mon in monitors)


# Subzone label -> the zone we publish. The minimap text is the specific
# place, and a bad read must not replace the zone.
ZONE_OF = {
    "dun morogh": "Dun Morogh",
    "coldridge valley": "Dun Morogh",
    "anvilmar": "Dun Morogh",
    "kharanos": "Dun Morogh",
    "steelgrill's depot": "Dun Morogh",
    "thunderbrew distillery": "Dun Morogh",
    "brewnall village": "Dun Morogh",
    "amberstill ranch": "Dun Morogh",
    "gol'bolar quarry": "Dun Morogh",
    "helm's bed lake": "Dun Morogh",
    "the grizzled den": "Dun Morogh",
    "frostmane hold": "Dun Morogh",
    "shimmer ridge": "Dun Morogh",
    "iceflow lake": "Dun Morogh",
    "gates of ironforge": "Dun Morogh",
    "ironforge": "Ironforge",
    "the great forge": "Ironforge",
    "tinker town": "Ironforge",
    "loch modan": "Loch Modan",
    "thelsamar": "Loch Modan",
    "valley of kings": "Loch Modan",
    "stonesplinter valley": "Loch Modan",
    "stormwind": "Stormwind City",
    "stormwind city": "Stormwind City",
    "elwynn forest": "Elwynn Forest",
    "goldshire": "Elwynn Forest",
    "northshire": "Elwynn Forest",
    "northshire valley": "Elwynn Forest",
    "westfall": "Westfall",
    "sentinel hill": "Westfall",
    "redridge mountains": "Redridge Mountains",
    "lakeshire": "Redridge Mountains",
    "burning steppes": "Burning Steppes",
    "wetlands": "Wetlands",
    "menethil harbor": "Wetlands",
    "gnomeregan": "Gnomeregan",
}


def zone_from_label(text: str) -> str | None:
    key = re.sub(r"[^a-z' ]", "", text.lower()).strip()
    if not key:
        return None
    if key in ZONE_OF:
        return ZONE_OF[key]
    if len(key) < 6:
        return None
    for name, zone in ZONE_OF.items():
        if name.startswith(key) or key.startswith(name):
            return zone
    return None


def read_zone(window: tuple[int, int, int, int]) -> str | None:
    if not wow_window_visible(window):
        return None
    x, y, width, _height = window
    crop_w, crop_h = 820, 72
    left = x + max(0, width - 900)
    geometry = f"{left},{y} {crop_w}x{crop_h}"
    try:
        subprocess.check_call(
            ["grim", "-g", geometry, "/tmp/wow-zone.png"],
            timeout=4,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        subprocess.check_call(
            ["magick", "/tmp/wow-zone.png", "-resize", "400%", "/tmp/wow-zone-big.png"],
            timeout=4,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except (subprocess.SubprocessError, OSError):
        return None
    tesseract = "/nix/store/n60gsy1g79dz4pw2gzcxndcykng55p68-tesseract-5.5.0/bin/tesseract"
    tessdata = "/nix/store/n60gsy1g79dz4pw2gzcxndcykng55p68-tesseract-5.5.0/share/tessdata"
    if not Path(tesseract).exists():
        return None
    env = os.environ.copy()
    env["TESSDATA_PREFIX"] = tessdata
    try:
        raw = subprocess.check_output(
            [tesseract, "/tmp/wow-zone-big.png", "stdout", "--psm", "6",
             "-c", "tessedit_char_whitelist=ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz' "],
            timeout=8,
            env=env,
            stderr=subprocess.DEVNULL,
        )
    except (subprocess.SubprocessError, OSError):
        return None
    phrases = re.findall(
        r"[A-Z][A-Za-z']+(?: [A-Z][A-Za-z']+)*",
        raw.decode("utf-8", "replace"),
    )
    for phrase in phrases:
        zone = zone_from_label(phrase)
        if zone:
            return zone
    return None


GROUP_SPEC = re.compile(r"^(solo|party|raid):(\d+):(\d+)$")


def parse_group_spec(spec: str | None) -> dict[str, object] | None:
    """Solo and a count of 1 publish no party. Party is n of 5, raid n of 40 or 20."""
    if not spec:
        return None
    match = GROUP_SPEC.match(spec.strip())
    if not match:
        return None
    kind, current, maximum = match.group(1), int(match.group(2)), int(match.group(3))
    if kind == "solo" or current <= 1 or maximum < current:
        return None
    return {"id": f"wow-{kind}-{current}", "size": [current, maximum]}


def wow_group_spec() -> str | None:
    spec = None
    for root in wow_data_dirs():
        config = root / "WTF/Config.wtf"
        try:
            text = config.read_text(errors="replace")
        except OSError:
            text = ""
        found = re.search(r'SET KissPresenceGroup "([^"]+)"', text)
        if found:
            spec = found.group(1)
        saved = root / "WTF/Account"
        if not saved.is_dir():
            continue
        try:
            accounts = list(saved.iterdir())
        except OSError:
            continue
        for account in accounts:
            lua = account / "SavedVariables/KissPresence.lua"
            try:
                body = lua.read_text(errors="replace")
            except OSError:
                continue
            found = re.search(r'\["group"\] = "([^"]+)"', body)
            if found:
                spec = found.group(1)
    return spec


def wow_fallback_fields(window: tuple[int, int, int, int] | None = None) -> dict[str, object]:
    global _last_zone
    screen = wow_screen()
    assets = None
    if screen == "world":
        character = wow_character_dir()
        name = character.name.replace("-", " ") if character is not None else WOW_APP_NAME
        class_name = wow_character_class(character)
        # The client does not write level while you are in the world.
        # 6 is the last level this character reported.
        level = "6" if name == "Hippo Himbopotamus" else None
        zone = read_zone(window) if window is not None else None
        if zone:
            _last_zone = zone
            remember_zone(zone)
        elif _last_zone is None:
            _last_zone = persisted_zone()
        state = _last_zone or "In game"
        if level and class_name:
            details = f"{name}: lvl {level} {class_name}"
        elif class_name:
            details = f"{name}: {class_name}"
        else:
            details = name
        assets = presence_assets(state if state != "In game" else None, class_name)
    elif screen == "character":
        _last_zone = None
        details = WOW_APP_NAME
        state = "Character select"
    else:
        _last_zone = None
        details = WOW_APP_NAME
        state = "Login screen"
    activity = {
        "type": 0,
        "name": WOW_APP_NAME,
        "details": details[:128],
        "state": state[:128],
        "instance": False,
    }
    if assets:
        activity["assets"] = assets
    if screen == "world":
        party = parse_group_spec(wow_group_spec())
        if party:
            activity["party"] = party
    return {
        "details": details,
        "state": state,
        "activity": activity,
        "client_id": WOW_CLIENT_ID,
    }


def wow_window() -> tuple[int, int, int, int] | None:
    try:
        raw = subprocess.check_output(["hyprctl", "clients", "-j"], text=True, timeout=3)
        clients = json.loads(raw)
    except (subprocess.SubprocessError, json.JSONDecodeError, OSError):
        return None
    best = None
    best_area = 0
    for client in clients:
        title = (client.get("title") or "").lower()
        if client.get("class") != "steam_app_default":
            continue
        if "warcraft iii" in title or title == "battle.net" or "battle.net" in title:
            continue
        if not any(token in title for token in WOW_TITLE):
            continue
        width, height = client.get("size") or (0, 0)
        area = width * height
        if area > best_area and height >= 400 and width >= 400:
            best = client
            best_area = area
    if not best:
        return None
    x, y = best["at"]
    width, height = best["size"]
    return x, y, width, height


def capture_strip(window: tuple[int, int, int, int]) -> tuple[int, int, list[tuple[int, int, int]]] | None:
    x, y, width, height = window
    # The UI scale pulls UIParent in from the screen edge, so the strip
    # is not at the window origin. Search the left half of the frame.
    grab_w = min(900, width)
    grab_h = min(height, 1440)
    geometry = f"{x},{y} {grab_w}x{grab_h}"
    try:
        raw = subprocess.check_output(
            ["grim", "-t", "ppm", "-g", geometry, "-"],
            timeout=4,
        )
    except (subprocess.SubprocessError, OSError):
        return None
    try:
        return parse_ppm(raw)
    except ValueError:
        return None


def status_text() -> str:
    mode = read_mode()
    hours = read_hours() or "not set"
    try:
        state = json.loads(STATE_PATH.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        state = {}
    publishing = "yes" if publishing_enabled() else "no"
    lines = [
        f"mode: {mode}",
        f"work hours: {hours}",
        f"inside work hours: {'yes' if in_work_hours() else 'no'}",
        f"publishing: {publishing}",
    ]
    if state.get("details"):
        lines.append(f"showing: {state['details']}")
        lines.append(f"         {state.get('state', '')}")
    elif state.get("waiting"):
        lines.append(f"waiting: {state['waiting']}")
    return "\n".join(lines)


def cmd_status() -> int:
    print(status_text())
    return 0


def cmd_hours(argument: str) -> int:
    if argument in {"", "off", "clear"}:
        write_hours("")
        if read_mode() == "auto":
            write_mode("on")
        print("work hours cleared")
        return 0
    try:
        parse_hours(argument)
    except (ValueError, KeyError) as exc:
        print(f"presence: {exc}", file=sys.stderr)
        return 2
    write_hours(argument)
    write_mode("auto")
    print(f"work hours set: {argument}")
    print("presence stays off during those hours; presence on overrides that")
    return 0


def watch() -> int:
    prepare_session_env()
    config_dir()
    ipc = DiscordIPC()
    stop = False

    def handle_signal(_signum, _frame) -> None:
        nonlocal stop
        stop = True

    signal.signal(signal.SIGTERM, handle_signal)
    signal.signal(signal.SIGINT, handle_signal)

    last_key = None
    last_sent = 0.0
    last_rich = None
    missing_since = None
    shown = False

    def clear() -> None:
        nonlocal last_key, last_sent, last_rich, shown
        try:
            ipc.set_activity(None, ipc.client_id or WOW_CLIENT_ID)
        except (OSError, ConnectionError, TimeoutError):
            pass
        last_key = None
        last_sent = 0.0
        last_rich = None
        shown = False

    try:
        while not stop:
            if not publishing_enabled():
                if shown:
                    clear()
                    write_state(details=None, state=None, waiting="paused")
                else:
                    write_state(waiting="paused")
                time.sleep(1)
                continue

            fields = None
            wow_on = os.environ.get("PRESENCE_WOW", "1") != "0"
            minecraft_on = os.environ.get("PRESENCE_MINECRAFT", "1") != "0"
            window = wow_window() if wow_on else None
            if window is not None:
                image = capture_strip(window)
                decoded = read_strip(*image) if image is not None else None
                if decoded:
                    last_rich = presence_fields(decoded.decode("utf-8", "replace"))
                # The strip is only on screen for about a second. Keep the
                # last character read instead of replacing it with "In game".
                if wow_screen() == "world":
                    fields = wow_fallback_fields(window)
                elif last_rich is not None:
                    fields = last_rich
                else:
                    fields = wow_fallback_fields(window)
            else:
                last_rich = None
                minecraft = minecraft_session() if minecraft_on else None
                if minecraft is not None:
                    game_dir, instance = minecraft
                    fields = minecraft_fields(game_dir, instance)
                elif wow_on and wow_process():
                    fields = wow_fallback_fields()

            if fields is None:
                if shown:
                    if missing_since is None:
                        missing_since = time.monotonic()
                    elif time.monotonic() - missing_since > GONE_SECONDS:
                        clear()
                        write_state(details=None, state=None, waiting="game closed")
                else:
                    write_state(waiting="waiting for World of Warcraft or Minecraft")
                time.sleep(1)
                continue
            missing_since = None

            key = (fields["client_id"], fields["details"], fields["state"])
            # Vesktop drops a presence that is not refreshed, and a one-shot
            # update never comes back if the socket dies.
            if key != last_key or time.monotonic() - last_sent > 20:
                if not shown or key[0] != (last_key[0] if last_key else None):
                    ipc.started_at = int(time.time())
                try:
                    ipc.set_activity(fields["activity"], fields["client_id"])
                except (OSError, ConnectionError, TimeoutError) as exc:
                    write_state(waiting=f"discord: {exc}")
                else:
                    last_key = key
                    last_sent = time.monotonic()
                    shown = True
                    write_state(details=fields["details"], state=fields["state"], waiting=None)
            time.sleep(POLL_SECONDS)
    finally:
        clear()
        ipc.close()
    return 0


def box_downscale(width: int, height: int, pixels: list[tuple[int, int, int]], factor: float):
    out_w = max(1, int(width * factor))
    out_h = max(1, int(height * factor))
    out = []
    for y in range(out_h):
        for x in range(out_w):
            x0 = int(x / factor)
            y0 = int(y / factor)
            x1 = min(width, max(x0 + 1, int((x + 1) / factor)))
            y1 = min(height, max(y0 + 1, int((y + 1) / factor)))
            total = [0, 0, 0]
            count = 0
            for sy in range(y0, y1):
                for sx in range(x0, x1):
                    pixel = pixels[sy * width + sx]
                    total[0] += pixel[0]
                    total[1] += pixel[1]
                    total[2] += pixel[2]
                    count += 1
            out.append(tuple(channel // count for channel in total))
    return out_w, out_h, out


def render_column(symbols: list[int], cell: int, pad: int = 6) -> tuple[int, int, list[tuple[int, int, int]]]:
    width = cell + pad * 2
    height = cell * len(symbols) + pad * 2
    pixels = [(8, 12, 16)] * (width * height)
    for index, symbol in enumerate(symbols):
        color = PALETTE[symbol]
        for y in range(pad + index * cell, pad + (index + 1) * cell):
            for x in range(pad, pad + cell):
                pixels[y * width + x] = color
    return width, height, pixels


def selftest() -> int:
    payload = "Hippo|70|Paladin|paladin|Alliance|Dun Morogh|Kharanos".encode()
    symbols = pack_symbols(payload)
    assert unpack_symbols(symbols) == payload

    for cell, factor in ((8, 1.0), (8, 0.83), (8, 0.75), (10, 0.64), (12, 0.75)):
        width, height, pixels = render_column(symbols, cell)
        if factor != 1:
            width, height, pixels = box_downscale(width, height, pixels, factor)
        decoded = decode_image(width, height, pixels)
        if decoded != payload:
            print(f"selftest failed cell={cell} factor={factor} got={decoded!r}", file=sys.stderr)
            return 1
    spec = parse_hours("mon-fri 09:00-17:00")
    assert spec is not None
    # Wednesday 10:00 is inside, Sunday 10:00 is not, Wednesday 18:00 is not.
    wed = time.struct_time((2026, 9, 23, 10, 0, 0, 2, 266, 1))
    sun = time.struct_time((2026, 9, 27, 10, 0, 0, 6, 270, 1))
    evening = time.struct_time((2026, 9, 23, 18, 0, 0, 2, 266, 1))
    days, start, end = spec
    assert wed.tm_wday in days and start <= 10 * 60 < end
    assert sun.tm_wday not in days
    assert not (start <= 18 * 60 < end)

    blob = gzip.compress(b"\x0aLevelName\x00\x09TestWorld\x08Dimension\x00\x14minecraft:the_nether")
    raw = gzip.decompress(blob)
    assert nbt_string_after(raw, b"LevelName") == "TestWorld"
    assert nbt_string_after(raw, b"Dimension") == "minecraft:the_nether"
    fields = minecraft_fields(None, "1.21.11")
    assert fields["details"] == "1.21.11"
    assert parse_group_spec(None) is None
    assert parse_group_spec("solo") is None
    assert parse_group_spec("party:1:5") is None
    assert parse_group_spec("party:3:5") == {"id": "wow-party-3", "size": [3, 5]}
    assert parse_group_spec("raid:12:40") == {"id": "wow-raid-12", "size": [12, 40]}
    assert parse_group_spec("raid:8:20") == {"id": "wow-raid-8", "size": [8, 20]}
    assert fields["state"] == "In the menu"
    assert fields["client_id"] == MINECRAFT_CLIENT_ID
    print("selftest ok")
    return 0


def main(argv: list[str]) -> int:
    command = argv[1] if len(argv) > 1 else "status"
    if command == "watch":
        return watch()
    if command == "selftest":
        return selftest()
    if command == "status":
        return cmd_status()
    if command == "on":
        write_mode("on")
        print("presence on")
        return 0
    if command == "off":
        write_mode("off")
        print("presence off")
        return 0
    if command == "toggle":
        quiet = read_mode() == "off" or (read_mode() == "auto" and in_work_hours())
        write_mode("on" if quiet else "off")
        print("presence on" if quiet else "presence off")
        return 0
    if command == "auto":
        write_mode("auto")
        print(status_text())
        return 0
    if command == "hours":
        return cmd_hours(" ".join(argv[2:]))
    if command in {"-h", "--help", "help"}:
        print("""presence on|off|toggle|status|auto
presence hours mon-fri 09:00-17:00
presence hours off

on      show World of Warcraft or Minecraft on Discord
off     hide it (work)
toggle  flip between on and off
auto    follow the hours schedule
hours   set the quiet window, weekdays by default as mon-fri""")
        return 0
    print(f"presence: unknown command {command}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
