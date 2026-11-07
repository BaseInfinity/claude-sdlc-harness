"""Start a NEW Codex thread with a first prompt, no human needed.

Talks JSON-RPC to a private `codex app-server --listen stdio://`. The thread
lands in the shared Codex thread store, so Codex Desktop lists it under CWD.
Read-only sandbox, never asks for approval.

Usage: python3 codex-thread.py CWD PROMPT_FILE
Prints "THREAD <id>" then the final answer. Exit 0 when the turn completes,
1 on bad arguments, 2 when the server fails or the turn is not "completed"
(failed, interrupted, or no turn/completed within 300 s).
Observed on codex-cli 0.167.0.
"""
import json
import os
import queue
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


class Server:
    """JSON-RPC over a child's stdio. A reader thread queues every line, so
    replies that arrive in one write are never stranded in a buffer."""

    def __init__(self, cmd=None):
        self.p = subprocess.Popen(cmd or ["codex", "app-server", "--listen", "stdio://"],
                                  stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                  stderr=subprocess.DEVNULL, text=True, bufsize=1)
        self.q = queue.Queue()
        threading.Thread(target=self._read, daemon=True).start()
        self.n = 0

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
        self.p.stdin.write(json.dumps(m) + "\n")
        self.p.stdin.flush()
        return m.get("id")

    def wait(self, pred, timeout):
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
            if pred(msg):
                return msg

    def close(self):
        self.p.terminate()
        try:
            self.p.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.p.kill()
            self.p.wait(timeout=5)


def main(cwd, prompt_file, cmd=None):
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
                        and m["params"]["turn"].get("id") == uid, 300)
        if not done:
            print("TURN_INCOMPLETE")
            return 2
        t = done["params"]["turn"]
        if t.get("status") != "completed":
            print("TURN_%s" % str(t.get("status")).upper())
            return 2
        texts = [i.get("text", "") for i in t.get("items", []) if i.get("type") == "agentMessage"]
        print(texts[-1] if texts else "")
        return 0
    finally:
        srv.close()


if __name__ == "__main__":
    if len(sys.argv) != 3 or not valid_cwd(sys.argv[1]) or not os.path.isfile(sys.argv[2]):
        print("usage: codex-thread.py ABSOLUTE_CWD PROMPT_FILE", file=sys.stderr)
        sys.exit(1)
    sys.exit(main(sys.argv[1], sys.argv[2]))
