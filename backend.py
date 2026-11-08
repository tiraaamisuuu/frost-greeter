"""greetd socket framing and session discovery."""

import json
import os
from pathlib import Path
import shutil
import socket
import struct
import tempfile

from gi.repository import GLib

SESSIONS = {"mango": "Mango", "plasma": "Plasma"}
LENGTH = struct.Struct("=I")


class LoginError(Exception):
    pass


def load_sessions(directory, search_path):
    sessions = {}
    for session in SESSIONS:
        entry = GLib.KeyFile.new()
        entry.load_from_file(str(directory / f"{session}.desktop"), GLib.KeyFileFlags.NONE)
        group = "Desktop Entry"
        _, argv = GLib.shell_parse_argv(entry.get_string(group, "Exec"))
        executable = shutil.which(argv[0], path=search_path)
        if executable is None or any("%" in arg for arg in argv):
            raise ValueError(f"Unsupported or missing Exec in {session}.desktop")
        argv[0] = executable
        desktops = entry.get_string_list(group, "DesktopNames")
        env = [
            "XDG_SESSION_TYPE=wayland",
            f"XDG_SESSION_DESKTOP={session}",
            "XDG_CURRENT_DESKTOP=" + ":".join(desktops),
        ]
        sessions[session] = argv, env
    return sessions


def read_exact(connection, count):
    data = bytearray()
    while len(data) < count:
        chunk = connection.recv(count - len(data))
        if not chunk:
            raise ConnectionError("greetd closed the connection")
        data.extend(chunk)
    return data


def exchange(connection, request, **fields):
    payload = json.dumps({"type": request, **fields}, separators=(",", ":")).encode()
    connection.sendall(LENGTH.pack(len(payload)) + payload)
    size, = LENGTH.unpack(read_exact(connection, LENGTH.size))
    if size > 65536:
        raise ValueError("Unexpectedly large greetd response")
    reply = json.loads(read_exact(connection, size))
    if reply["type"] == "error":
        if reply.get("error_type") == "auth_error":
            raise LoginError("Sign-in failed. Check the account and password, then try again.")
        raise LoginError("The login service could not complete sign-in. Try again.")
    return reply


def login(address, username, password, session, ask, notify):
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
        connection.settimeout(30)
        connection.connect(address)
        started = False
        try:
            reply = exchange(connection, "create_session", username=username)
            while reply["type"] == "auth_message":
                kind = reply["auth_message_type"]
                message = reply["auth_message"]
                if kind == "secret" and password is not None:
                    answer = password
                    password = None
                elif kind in ("secret", "visible"):
                    answer = ask(kind, message)
                    if answer is None:
                        raise LoginError("Sign-in cancelled.")
                elif kind in ("info", "error"):
                    notify(message, kind == "error")
                    answer = None
                else:
                    raise ValueError("Unrecognized greetd prompt")

                reply = exchange(connection, "post_auth_message_response", response=answer)
                del answer

            if reply["type"] != "success":
                raise ValueError("Unexpected greetd authentication response")
            cmd, env = session
            if exchange(connection, "start_session", cmd=cmd, env=env)["type"] != "success":
                raise ValueError("Unexpected greetd start response")
            started = True
        finally:
            if not started:
                try:
                    connection.settimeout(1)
                    exchange(connection, "cancel_session")
                except (OSError, ValueError, KeyError, LoginError):
                    pass


def read_session(path):
    try:
        with path.open() as stream:
            return stream.read(16).strip()
    except (OSError, UnicodeError):
        return "mango"


def save_session(path, session):
    with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, delete=False) as stream:
        temp = Path(stream.name)
        try:
            stream.write(session + "\n")
            stream.close()
            os.replace(temp, path)
        finally:
            temp.unlink(missing_ok=True)
