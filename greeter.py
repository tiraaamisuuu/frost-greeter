"""GTK login screen and desktop-safe preview."""

import argparse
import os
from pathlib import Path
from queue import Queue
import resource
from threading import Thread

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Gdk", "4.0")
from gi.repository import Gdk, Gio, GLib, Gtk, Pango

from backend import LoginError, SESSIONS, load_sessions, login, read_session, save_session

STYLE = b"""
window { background: #202429; color: #f2f2f2; }
.shade { background: rgba(11, 17, 24, 0.23); }
.panel {
  background: rgba(26, 30, 35, 0.97);
  border: 1px solid rgba(173, 201, 227, 0.38);
  border-radius: 16px;
  padding: 26px 30px;
  box-shadow: 0 14px 48px rgba(9, 14, 21, 0.46);
  font-family: "Mononoki Nerd Font Mono", monospace;
}
.kicker { color: #adc9e3; font-size: 12px; letter-spacing: 2px; }
.heading { font-size: 28px; font-weight: bold; }
.field-label, .hint { color: #bac7d2; font-size: 12px; }
entry, passwordentry, dropdown button, button.submit {
  background: #222932;
  color: #f2f2f2;
  border: 1px solid #465360;
  border-radius: 7px;
  min-height: 34px;
}
entry, passwordentry { padding: 0 10px; caret-color: #adc9e3; }
entry:focus-within, passwordentry:focus-within, dropdown button:focus-visible, button.submit:focus-visible {
  outline: 2px solid #adc9e3;
  outline-offset: 2px;
}
button.submit { background: #adc9e3; color: #15212d; font-weight: bold; padding: 0 16px; }
.message { color: #adc9e3; font-size: 13px; }
.error { color: #ffc3ba; }
"""


def label(text, css):
    widget = Gtk.Label(label=text, xalign=0)
    widget.add_css_class(css)
    return widget


class Greeter:
    def __init__(self, app, options, sessions):
        self.app = app
        self.options = options
        self.sessions = sessions
        self.pending = None
        self.busy = False
        self.window = Gtk.ApplicationWindow(application=app, title="Frost Greeter")
        self.window.set_default_size(1120, 650)

        css = Gtk.CssProvider()
        css.load_from_data(STYLE)
        Gtk.StyleContext.add_provider_for_display(
            self.window.get_display(), css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )

        layers = Gtk.Overlay()
        picture = Gtk.Picture.new_for_file(Gio.File.new_for_path(str(options.wallpaper)))
        picture.set_content_fit(Gtk.ContentFit.COVER)
        layers.set_child(picture)
        shade = Gtk.Box()
        shade.add_css_class("shade")
        layers.add_overlay(shade)

        panel = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=11)
        panel.add_css_class("panel")
        panel.set_size_request(370, -1)
        panel.set_halign(Gtk.Align.CENTER)
        panel.set_valign(Gtk.Align.CENTER)
        layers.add_overlay(panel)
        self.window.set_child(layers)

        panel.append(label("FROST  /  PREVIEW" if options.preview else "FROST", "kicker"))
        panel.append(label("Sign in", "heading"))

        self.user = Gtk.Entry(text=options.username)
        self.password = Gtk.PasswordEntry(show_peek_icon=False)
        self.field(panel, "Account", self.user)
        self.visible_prompt = Gtk.Entry()
        self.prompt = Gtk.Stack()
        self.prompt.add_child(self.password)
        self.prompt.add_child(self.visible_prompt)
        self.password_label = self.field(panel, "Password", self.prompt)
        self.password.update_property([Gtk.AccessibleProperty.LABEL], ["Password"])

        row = Gtk.Box(spacing=10)
        self.session = Gtk.DropDown.new_from_strings(list(SESSIONS.values()))
        self.session.update_property([Gtk.AccessibleProperty.LABEL], ["Session"])
        self.session.set_hexpand(True)
        if not options.preview and read_session(options.state) == "plasma":
            self.session.set_selected(1)
        self.submit = Gtk.Button(label="Sign in  ↵")
        self.submit.add_css_class("submit")
        row.append(self.session)
        row.append(self.submit)
        panel.append(label("Session", "field-label"))
        panel.append(row)

        self.message = label("", "message")
        self.message.set_wrap(True)
        self.message.set_max_width_chars(36)
        self.message.set_lines(3)
        self.message.set_ellipsize(Pango.EllipsizeMode.END)
        panel.append(self.message)
        if options.preview:
            panel.append(label("Demo password: frost   ·   Esc closes", "hint"))
        keys = Gtk.EventControllerKey.new()
        keys.connect("key-pressed", self.escape_key)
        self.window.add_controller(keys)
        self.window.connect("close-request", lambda *_: self.busy)

        self.user.connect("activate", lambda *_: self.password.grab_focus())
        self.password.connect("activate", self.sign_in)
        self.visible_prompt.connect("activate", self.sign_in)
        self.submit.connect("clicked", self.sign_in)
        if options.fullscreen or not options.preview:
            self.window.fullscreen()
        self.window.set_focus(self.password)
        self.window.present()

    def field(self, panel, text, widget):
        title = label(text, "field-label")
        panel.append(title)
        panel.append(widget)
        widget.update_property([Gtk.AccessibleProperty.LABEL], [text])
        return title

    def escape_key(self, _controller, key, _keycode, _state):
        if key != Gdk.KEY_Escape:
            return False
        if self.options.preview:
            self.window.close()
            return True
        if self.pending is not None:
            self.answer(None)
            return True
        return False

    def status(self, text, error=False):
        self.message.set_text(text)
        if error:
            self.message.add_css_class("error")
        else:
            self.message.remove_css_class("error")

    def sign_in(self, *_):
        if self.pending is not None:
            entry = self.prompt.get_visible_child()
            answer = entry.get_text()
            entry.set_text("")
            self.answer(answer)
            return
        if self.busy:
            return
        username = self.user.get_text().strip()
        if not username:
            self.status("Enter an account name.", error=True)
            self.user.grab_focus()
            return
        secret = self.password.get_text()
        self.password.set_text("")
        session = tuple(SESSIONS)[self.session.get_selected()]
        if self.options.preview:
            self.password.grab_focus()
            if secret == "frost":
                self.status(f"Preview accepted · {SESSIONS[session]}")
            else:
                self.status("Password incorrect. Try again.", error=True)
            return

        self.busy = True
        for control in (self.user, self.session, self.prompt, self.submit):
            control.set_sensitive(False)
        self.status("Signing in…")
        Thread(target=self.authenticate, args=(username, secret, session), daemon=True).start()

    def authenticate(self, username, secret, session):
        try:
            login(
                os.environ["GREETD_SOCK"], username, secret, self.sessions[session],
                self.ask, lambda message, error: GLib.idle_add(self.status, message, error),
            )
        except LoginError as error:
            GLib.idle_add(self.retry, str(error))
            return
        except (OSError, ValueError, KeyError):
            GLib.idle_add(self.retry, "Unable to reach the login service. Try again.")
            return

        try:
            save_session(self.options.state, session)
        except OSError:
            # A failed preference write must never prevent session handoff.
            pass
        GLib.idle_add(self.app.quit)

    def ask(self, kind, message):
        response = Queue(maxsize=1)
        GLib.idle_add(self.show_prompt, kind, message, response)
        return response.get()

    def show_prompt(self, kind, message, response):
        self.pending = response
        entry = self.password if kind == "secret" else self.visible_prompt
        self.prompt.set_visible_child(entry)
        title = "Authentication" if kind == "visible" else "Password / code"
        self.password_label.set_text(title)
        entry.update_property([Gtk.AccessibleProperty.LABEL], [title])
        self.status(message)
        self.submit.set_sensitive(True)
        self.prompt.set_sensitive(True)
        entry.grab_focus()

    def answer(self, answer):
        response, self.pending = self.pending, None
        self.prompt.get_visible_child().set_text("")
        self.submit.set_sensitive(False)
        self.prompt.set_sensitive(False)
        response.put(answer)

    def retry(self, message):
        self.busy = False
        self.prompt.set_visible_child(self.password)
        self.password_label.set_text("Password")
        self.password.update_property([Gtk.AccessibleProperty.LABEL], ["Password"])
        for control in (self.user, self.session, self.prompt, self.submit):
            control.set_sensitive(True)
        self.status(message, error=True)
        self.password.grab_focus()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group(required=True)
    modes.add_argument("--preview", action="store_true")
    modes.add_argument("--live", action="store_true")
    modes.add_argument("--check-sessions", action="store_true")
    parser.add_argument("--sessions-dir", type=Path)
    parser.add_argument("--session-path", default="/run/current-system/sw/bin")
    parser.add_argument("--state", type=Path, default=Path("/var/lib/frost-greeter/session"))
    parser.add_argument("--fullscreen", action="store_true")
    parser.add_argument("--username", default="tiramisu")
    parser.add_argument("--wallpaper", type=Path, default=Path.home() / "Pictures/mango-wall.jpg")
    options = parser.parse_args()
    sessions = {}
    if not options.preview:
        if options.sessions_dir is None:
            parser.error("--sessions-dir is required")
        sessions = load_sessions(options.sessions_dir, options.session_path)
    if options.check_sessions:
        for session, (cmd, env) in sessions.items():
            print(f"{SESSIONS[session]}: {GLib.shell_quote(cmd[0])}", *map(GLib.shell_quote, cmd[1:]))
        return 0
    if options.live:
        if not os.environ.get("GREETD_SOCK"):
            parser.error("--live requires greetd")
        resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    app = Gtk.Application(flags=Gio.ApplicationFlags.NON_UNIQUE)
    app.connect("activate", lambda app: Greeter(app, options, sessions))
    return app.run([])


if __name__ == "__main__":
    raise SystemExit(main())
