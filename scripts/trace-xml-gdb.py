"""GDB-only observer for a stopped synthetic container; never inspect salt arguments."""

import hashlib
import json
import os
from pathlib import Path

import gdb


control = json.loads(Path(os.environ["MUVV_TRACE_CONTROL"]).read_text())
pid = control["host_pid"]
if type(pid) is not int or pid <= 1:
    raise RuntimeError("Invalid synthetic process")
for module in control["modules"].values():
    path = Path(f"/proc/{pid}/root{module['path']}")
    if hashlib.sha256(path.read_bytes()).hexdigest() != module["sha256"]:
        raise RuntimeError("Module identity mismatch")
maps = Path(f"/proc/{pid}/maps").read_text().splitlines()
provider = control["modules"]["pyexpat"]["path"]
for key in ("salt16", "legacy"):
    address = control[key]
    mapped = False
    for line in maps:
        fields = line.split(maxsplit=5)
        if len(fields) == 6 and fields[5] == provider and "x" in fields[1]:
            low, high = (int(value, 16) for value in fields[0].split("-"))
            mapped |= low <= address < high
    if not mapped:
        raise RuntimeError("Trace address is not in the expected executable module")

gdb.execute("set pagination off")
gdb.execute("set confirm off")
gdb.execute("set print frame-arguments none")
gdb.execute(f"set sysroot /proc/{pid}/root")
gdb.execute(f"attach {pid}", to_string=True)
if gdb.selected_inferior().pid != pid:
    raise RuntimeError("Debugger attached to the wrong process")


class Counter(gdb.Breakpoint):
    def __init__(self, address):
        super().__init__(f"*{address:#x}", type=gdb.BP_HARDWARE_BREAKPOINT, internal=True)
        self.hits = 0

    def stop(self):
        self.hits += 1
        return self.hits > 3


salt16 = Counter(control["salt16"])
legacy = Counter(control["legacy"])
exits = []
gdb.events.exited.connect(lambda event: exits.append(getattr(event, "exit_code", None)))
gdb.execute("handle SIGSTOP nostop noprint nopass")
gdb.execute("continue", to_string=True)
if exits != [0]:
    raise RuntimeError("Synthetic process did not exit normally")
Path(os.environ["MUVV_TRACE_RESULT"]).write_text(json.dumps({
    "hardware_breakpoints": True, "salt16_hits": salt16.hits,
    "legacy_hits": legacy.hits, "exit_code": exits[0],
}), encoding="utf-8")
