"""AX half of claude-desktop.sh: press NAMED controls in one Claude window.

Holds native AXUIElementRef handles, which name one element and never
re-resolve, so the window that is verified is the window that is pressed.
decide() is pure so tests can run it without a GUI.

Usage: claude-desktop.py PID FOLDER PROMPT_FILE ALLOW_TRUST LAUNCH_EPOCH
(prints one result word)
"""
import ctypes
import json
import os
import sys
import time


def decide(s, folder, home, expect, allow_trust=True):
    shown = "~" + folder[len(home):] if folder.startswith(home + "/") else folder
    if s.get("trust"):
        if s.get("trustPath") != folder:
            return "WRONG_FOLDER"
        return "TRUST" if allow_trust else "NEEDS_TRUST"
    if s.get("folderLabel") != "Folder: " + shown:
        return "WRONG_FOLDER"
    if s.get("composer") is None:
        return "NO_COMPOSER"
    if s["composer"].rstrip("\n") != expect.rstrip("\n"):
        return "MISMATCH"
    if not s.get("send"):
        return "NO_SEND"
    return "SEND"


class AX:
    def __init__(self):
        self.a = ctypes.cdll.LoadLibrary(
            "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices")
        self.cf = ctypes.cdll.LoadLibrary(
            "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation")
        a, cf, vp = self.a, self.cf, ctypes.c_void_p
        a.AXUIElementCreateApplication.restype = vp
        a.AXUIElementCreateApplication.argtypes = [ctypes.c_int]
        a.AXUIElementCopyAttributeValue.argtypes = [vp, vp, ctypes.POINTER(vp)]
        a.AXUIElementSetAttributeValue.argtypes = [vp, vp, vp]
        a.AXUIElementPerformAction.argtypes = [vp, vp]
        cf.CFStringCreateWithCString.restype = vp
        cf.CFStringCreateWithCString.argtypes = [vp, ctypes.c_char_p, ctypes.c_uint32]
        cf.CFGetTypeID.restype = ctypes.c_ulong
        cf.CFGetTypeID.argtypes = [vp]
        cf.CFStringGetTypeID.restype = ctypes.c_ulong
        cf.CFArrayGetTypeID.restype = ctypes.c_ulong
        cf.CFArrayGetCount.restype = ctypes.c_long
        cf.CFArrayGetCount.argtypes = [vp]
        cf.CFArrayGetValueAtIndex.restype = vp
        cf.CFArrayGetValueAtIndex.argtypes = [vp, ctypes.c_long]
        cf.CFStringGetLength.restype = ctypes.c_long
        cf.CFStringGetLength.argtypes = [vp]
        cf.CFStringGetCString.argtypes = [vp, ctypes.c_char_p, ctypes.c_long, ctypes.c_uint32]
        self.str_t, self.arr_t = cf.CFStringGetTypeID(), cf.CFArrayGetTypeID()

    def cfstr(self, s):
        return self.cf.CFStringCreateWithCString(None, s.encode(), 0x08000100)

    def get(self, el, attr):
        out = ctypes.c_void_p()
        if self.a.AXUIElementCopyAttributeValue(el, self.cfstr(attr), ctypes.byref(out)) != 0:
            return None
        return out.value

    def text(self, el, attr):
        v = self.get(el, attr)
        if not v or self.cf.CFGetTypeID(v) != self.str_t:
            return None
        size = self.cf.CFStringGetLength(v) * 4 + 1
        buf = ctypes.create_string_buffer(size)
        if not self.cf.CFStringGetCString(v, buf, size, 0x08000100):
            return None
        return buf.value.decode()

    def children(self, el):
        v = self.get(el, "AXChildren")
        if not v or self.cf.CFGetTypeID(v) != self.arr_t:
            return []
        return [self.cf.CFArrayGetValueAtIndex(v, i) for i in range(self.cf.CFArrayGetCount(v))]

    def press(self, el):
        return self.a.AXUIElementPerformAction(el, self.cfstr("AXPress")) == 0


def scan(ax, win):
    s = {"trust": None, "trustPath": None, "folderLabel": None, "composer": None, "send": None}
    found = {"composer": False}

    def walk(el, depth, in_trust):
        if depth > 45:
            return
        role = ax.text(el, "AXRole") or ""
        title = ax.text(el, "AXTitle") or ""
        desc = ax.text(el, "AXDescription") or ""
        if role == "AXGroup" and title == "Trust this workspace?":
            in_trust = True
        if role == "AXButton" and title == "Trust workspace" and not s["trust"]:
            s["trust"] = el
        if in_trust and role == "AXStaticText":
            v = ax.text(el, "AXValue")
            if v and v.startswith("/"):
                s["trustPath"] = v
        if role == "AXPopUpButton" and desc.startswith("Folder: "):
            s["folderLabel"] = desc
        if role == "AXTextArea" and desc == "Prompt" and not found["composer"]:
            # An unreadable value stays None: "" must mean verified empty.
            found["composer"] = True
            s["composer"] = ax.text(el, "AXValue")
        if role == "AXButton" and "Send" in (title, desc) and not s["send"]:
            s["send"] = el
        for c in ax.children(el):
            walk(c, depth + 1, in_trust)

    walk(win, 0, False)
    return s


def project_dir(folder, home):
    """Claude Code's transcript dir for FOLDER: "/" and "." become "-"."""
    return os.path.join(home, ".claude", "projects", folder.replace("/", "-").replace(".", "-"))


def _text(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "".join(b.get("text", "") for b in content
                       if isinstance(b, dict) and b.get("type") == "text")
    return ""


def transcript_sent(pdir, since, expect):
    """True when a .jsonl created at or after SINCE (epoch seconds) holds a
    user message that contains the prompt. That is the proof of a send."""
    want = expect.rstrip("\n")
    try:
        names = os.listdir(pdir)
    except OSError:
        return False
    for name in names:
        if not name.endswith(".jsonl"):
            continue
        path = os.path.join(pdir, name)
        try:
            st = os.stat(path)
            if getattr(st, "st_birthtime", st.st_mtime) < since:
                continue
            with open(path, encoding="utf-8") as f:
                for line in f:
                    try:
                        d = json.loads(line)
                    except ValueError:
                        continue
                    msg = d.get("message") if isinstance(d, dict) else None
                    if d.get("type") == "user" and isinstance(msg, dict) \
                            and want in _text(msg.get("content")):
                        return True
        except OSError:
            continue
    return False


def main(pid, folder, prompt_file, allow_trust, launch):
    with open(prompt_file, encoding="utf-8") as f:
        expect = f.read()
    home = os.path.expanduser("~")
    ax = AX()
    app = ax.a.AXUIElementCreateApplication(pid)
    # Electron exposes page controls only after this is set on the app element.
    true = ctypes.c_void_p.in_dll(ax.cf, "kCFBooleanTrue")
    if ax.a.AXUIElementSetAttributeValue(app, ax.cfstr("AXManualAccessibility"), true) != 0:
        return "NO_AX"
    time.sleep(1)
    win = ax.get(app, "AXFocusedWindow") or ax.get(app, "AXMainWindow")
    if not win:
        return "NO_WINDOW"
    pdir = project_dir(folder, home)
    return drive(lambda: scan(ax, win), ax.press,
                 lambda: transcript_sent(pdir, launch, expect),
                 folder, home, expect, allow_trust)


def drive(scan_fn, press, confirm, folder, home, expect, allow_trust, wait=time.sleep):
    """Press Trust (if allowed) then Send, each only after decide() agrees."""
    s = scan_fn()
    d = decide(s, folder, home, expect, allow_trust)
    trusted = d == "TRUST"
    if trusted:
        if not press(s["trust"]):
            return "PRESS_FAILED"
        wait(3)
        s = scan_fn()
        d = decide(s, folder, home, expect)
        if d == "TRUST":
            return "TRUST_STUCK"
    if d != "SEND":
        return d
    if not press(s["send"]):
        return "PRESS_FAILED"
    # An accepted press is not a submitted prompt. The proof is the new
    # session's transcript holding the prompt, polled for up to 30 s. The
    # composer is no proof: it kept the prompt after a real send (live 13:39).
    for _ in range(30):
        wait(1)
        if confirm():
            return "TRUSTED_SENT" if trusted else "SENT"
    return "SEND_UNCONFIRMED"


EXIT = {"SENT": 0, "TRUSTED_SENT": 0, "MISMATCH": 3, "WRONG_FOLDER": 3, "NEEDS_TRUST": 4,
        "SEND_UNCONFIRMED": 5}


if __name__ == "__main__":
    result = main(int(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4] == "1",
                  float(sys.argv[5]))
    print(result)
    sys.exit(EXIT.get(result, 2))
