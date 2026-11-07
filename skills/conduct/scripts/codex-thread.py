"""Start a NEW Codex thread with a first prompt, no human needed.

Talks JSON-RPC to a private `codex app-server --listen stdio://`. The thread
lands in the shared Codex thread store, so Codex Desktop lists it under CWD.
Read-only sandbox, never asks for approval.

Server requests (approvals, user input) are declined: no human answers them.
Answer text comes from turn/completed items, or from item/completed
notifications when the server leaves those items empty.

Usage: python3 codex-thread.py CWD PROMPT_FILE
Prints "THREAD <id>" then the final answer. Exit 0 when the turn completes,
1 on bad arguments, 2 when the server fails to start, its pipes break, or
the turn is not "completed"
(failed, interrupted, or no turn/completed within 300 s).
Observed on codex-cli 0.167.0.
"""
import json
import os
import queue
import shutil
import subprocess
import sys
import threading
import time


def valid_cwd(path, isabs=os.path.isabs):
    """True for an absolute path on this platform (POSIX, C:\\ or UNC)."""
    return isabs(path)


def handshake(cwd):
    return [
        ("initialize", {"clientInfo": {"name": "conduct", "version": "1"}}),
        ("initialized", None),
        ("thread/start", {"cwd": cwd, "sandbox": "read-only", "approvalPolicy": "never"}),
    ]


def turn(thread_id, prompt):
    return {"threadId": thread_id, "input": [{"type": "text", "text": prompt}]}


SERVER_ARGS = ["app-server", "--listen", "stdio://"]


def server_argv(osname=os.name, which=shutil.which):
    """Windows npm installs codex as a .cmd shim, which CreateProcess cannot
    run directly; launch it through cmd.exe with fixed arguments. `/s` strips
    the outer quote pair, so the path keeps its own quotes. The result is a
    command-line string, because list2cmdline would escape those quotes with
    backslashes that cmd.exe does not read. The prompt never reaches a shell:
    it travels as JSON on stdin."""
    if osname != "nt":
        return ["codex"] + SERVER_ARGS
    path = which("codex")
    if not path:
        return ["codex"] + SERVER_ARGS
    if path.lower().endswith((".cmd", ".bat")):
        return 'cmd.exe /d /s /c ""%s" %s"' % (path, " ".join(SERVER_ARGS))
    return [path] + SERVER_ARGS


class Server:
    """JSON-RPC over a child's stdio. A reader thread queues every line, so
    replies that arrive in one write are never stranded in a buffer. Messages
that no wait() has claimed yet stay in a backlog, so a notification that
lands before the reply it follows is not lost."""

    def __init__(self, cmd=None):
        self.p = subprocess.Popen(cmd or server_argv(),
                                  stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                  stderr=subprocess.DEVNULL, text=True, bufsize=1,
                                  encoding="utf-8")
        self.q = queue.Queue()
        threading.Thread(target=self._read, daemon=True).start()
        self.n = 0
        self.backlog = []
        self.seen = []

    def _read(self):
        for line in self.p.stdout:
            self.q.put(line)
        self.q.put(None)

    def send(self, method, params):
        m = {"method": method}
        if params is not None:
            m["params"] = params
        if method != "initialized":
            self.n += 1
            m["id"] = self.n
        self._write(m)
        return m.get("id")

    def _write(self, m):
        self.p.stdin.write(json.dumps(m) + "\n")
        self.p.stdin.flush()

    def wait(self, pred, timeout):
        for i, msg in enumerate(self.backlog):
            if pred(msg):
                return self.backlog.pop(i)
        end = time.time() + timeout
        while True:
            left = end - time.time()
            if left <= 0:
                return None
            try:
                line = self.q.get(timeout=left)
            except queue.Empty:
                return None
            if line is None:
                return None
            msg = json.loads(line)
            if "method" in msg and "id" in msg:
                self._write({"id": msg["id"],
                             "error": {"code": -32601, "message": "noninteractive client"}})
                continue
            self.seen.append(msg)
            if pred(msg):
                return msg
            self.backlog.append(msg)

    def close(self):
        try:
            self.p.stdin.close()
        except OSError:
            pass
        self.p.terminate()
        try:
            self.p.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.p.kill()
            self.p.wait(timeout=5)


def cli_stdout(stream):
    """Callers parse CLI output byte for byte: UTF-8 whatever the locale says,
    and no newline translation, so Windows never turns \n into \r\n."""
    stream.reconfigure(encoding="utf-8", newline="\n")


def main(cwd, prompt_file, cmd=None, turn_timeout=300):
    with open(prompt_file, encoding="utf-8") as f:
        prompt = f.read().rstrip("\n")
    try:
        srv = Server(cmd)
    except OSError as e:
        print("SERVER_START_FAILED %s" % e.strerror)
        return 2
    try:
        reply = None
        for method, params in handshake(cwd):
            rid = srv.send(method, params)
            if rid is not None:
                reply = srv.wait(lambda m, rid=rid: m.get("id") == rid, 60)
                if not reply or "result" not in reply:
                    print("FAILED %s" % method)
                    return 2
        tid = reply["result"]["thread"]["id"]
        print("THREAD %s" % tid, flush=True)
        rid = srv.send("turn/start", turn(tid, prompt))
        started = srv.wait(lambda m: m.get("id") == rid, 60)
        if not started or "result" not in started:
            print("FAILED turn/start")
            return 2
        uid = started["result"]["turn"]["id"]
        done = srv.wait(lambda m: m.get("method") == "turn/completed"
                        and m["params"].get("threadId") == tid
                        and m["params"]["turn"].get("id") == uid, turn_timeout)
        if not done:
            print("TURN_INCOMPLETE")
            return 2
        t = done["params"]["turn"]
        if t.get("status") != "completed":
            print("TURN_%s" % str(t.get("status")).upper())
            return 2
        items = t.get("items") or [
            m["params"].get("item", {}) for m in srv.seen
            if m.get("method") == "item/completed"
            and m["params"].get("threadId") == tid and m["params"].get("turnId") == uid]
        texts = [i.get("text", "") for i in items if i.get("type") == "agentMessage"]
        answer = texts[-1] if texts else ""
        sys.stdout.write(answer if answer.endswith("\n") else answer + "\n")
        return 0
    except OSError as e:
        print("SERVER_IO_FAILED %s" % (e.strerror or e))
        return 2
    finally:
        srv.close()


if __name__ == "__main__":
    if len(sys.argv) != 3 or not valid_cwd(sys.argv[1]) or not os.path.isfile(sys.argv[2]):
        print("usage: codex-thread.py ABSOLUTE_CWD PROMPT_FILE", file=sys.stderr)
        sys.exit(1)
    cli_stdout(sys.stdout)
    sys.exit(main(sys.argv[1], sys.argv[2]))
