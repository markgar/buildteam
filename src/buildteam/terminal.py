"""Terminal spawning helper for launching agent commands in new windows."""

import os
import shutil
import subprocess
import sys
import tempfile

from buildteam.utils import check_command, console, is_container, is_macos, is_windows, resolve_logs_dir


def _is_headless() -> bool:
    """Detect if we're in a headless environment (no desktop, container, etc.).

    Returns True when there's no graphical terminal available — either because
    we're inside a container or because there's no DISPLAY/TERM_PROGRAM set.
    """
    if is_container():
        return True
    if os.environ.get("BUILDTEAM_HEADLESS", "").lower() in ("1", "true", "yes"):
        return True
    # On macOS/Windows, the desktop is always available if we got this far.
    if is_macos() or is_windows():
        return False
    # On Linux, check for DISPLAY (X11) or WAYLAND_DISPLAY
    return not os.environ.get("DISPLAY") and not os.environ.get("WAYLAND_DISPLAY")


def build_agent_script(working_dir: str, command: str, platform: str, model: str = "") -> str:
    """Generate the shell script content for launching an agent.

    Pure function: returns the script text for the given platform.
    platform should be 'macos', 'windows', or 'linux'.
    When *model* is provided it is used; otherwise COPILOT_MODEL from the
    current environment is propagated to the child terminal.
    """
    lines = ["#!/bin/bash"]
    copilot_model = model or os.environ.get("COPILOT_MODEL", "")
    if copilot_model:
        lines.append(f"export COPILOT_MODEL='{copilot_model}'")
    lines.append(f"cd '{working_dir}'")
    lines.append(f"buildteam {command}")
    if platform == "linux":
        lines.append("exec bash")
    return "\n".join(lines) + "\n"


def _spawn_macos(working_dir: str, command: str, model: str = "") -> None:
    """Spawn agent in a new macOS Terminal window."""
    script_content = build_agent_script(working_dir, command, "macos", model=model)
    fd, temp_script = tempfile.mkstemp(suffix=".sh")
    with os.fdopen(fd, "w") as f:
        f.write(script_content)
    os.chmod(temp_script, 0o755)
    subprocess.run(
        ["osascript", "-e", f'tell application "Terminal" to do script "{temp_script}"'],
        stdout=subprocess.DEVNULL,
    )


def _resolve_windows_command(command: str) -> list[str]:
    """Build the command list for launching an agent on Windows.

    Splits the command string so flags like '--loop --builder-id 1' become
    separate arguments in the subprocess call.
    """
    parts = command.split()
    venv_exe = os.path.join(os.path.dirname(sys.executable), "buildteam.exe")
    if os.path.isfile(venv_exe):
        return [venv_exe] + parts
    path_exe = shutil.which("buildteam")
    if path_exe:
        return [path_exe] + parts
    return [sys.executable, "-m", "buildteam"] + parts


def _spawn_windows(working_dir: str, command: str, model: str = "") -> None:
    """Spawn agent in a new Windows console.

    When *model* is provided it overrides the inherited COPILOT_MODEL.
    Otherwise the parent environment value is propagated.
    """
    cmd = _resolve_windows_command(command)
    env = os.environ.copy()
    copilot_model = model or os.environ.get("COPILOT_MODEL", "")
    if copilot_model:
        env["COPILOT_MODEL"] = copilot_model
    subprocess.Popen(
        cmd,
        cwd=working_dir,
        env=env,
        creationflags=subprocess.CREATE_NEW_CONSOLE,
    )


def _spawn_linux(working_dir: str, command: str, model: str = "") -> None:
    """Spawn agent in a new Linux terminal emulator."""
    script_content = build_agent_script(working_dir, command, "linux", model=model)
    fd, temp_script = tempfile.mkstemp(suffix=".sh")
    with os.fdopen(fd, "w") as f:
        f.write(script_content)
    os.chmod(temp_script, 0o755)

    if check_command("gnome-terminal"):
        subprocess.Popen(["gnome-terminal", "--", "bash", temp_script])
    elif check_command("xterm"):
        subprocess.Popen(["xterm", "-e", f"bash {temp_script}"])
    else:
        console.print(
            f"WARNING: Could not find a terminal emulator. "
            f"Please run manually in a new terminal:\n"
            f"  cd {working_dir} && buildteam {command}",
            style="yellow",
        )


def _spawn_headless(working_dir: str, command: str, model: str = "") -> None:
    """Spawn agent as a background subprocess (no terminal window).

    Used in containers and other headless environments where there's no
    desktop to open a terminal window in. Output goes to logs/*.log only.
    """
    script_content = build_agent_script(working_dir, command, "linux", model=model)
    fd, temp_script = tempfile.mkstemp(suffix=".sh")
    with os.fdopen(fd, "w") as f:
        f.write(script_content)
    os.chmod(temp_script, 0o755)

    # Open log file for stdout/stderr so output isn't lost
    logs_dir = resolve_logs_dir()
    os.makedirs(logs_dir, exist_ok=True)
    agent_name = os.path.basename(working_dir)
    log_path = os.path.join(logs_dir, f"{agent_name}-spawn.log")
    log_fh = open(log_path, "a", encoding="utf-8")

    subprocess.Popen(
        ["bash", temp_script],
        stdout=log_fh,
        stderr=log_fh,
        start_new_session=True,  # detach from parent
    )


def spawn_agent_in_terminal(working_dir: str, command: str, model: str = "") -> None:
    """Launch an agent command in a new terminal window (or background process if headless).

    When *model* is provided the child terminal's COPILOT_MODEL is set to
    that value, overriding the parent environment.  When omitted the parent
    environment value is inherited as before.

    In headless mode (container, no DISPLAY, or BUILDTEAM_HEADLESS=1), spawns
    a background subprocess instead of opening a terminal window.
    """
    try:
        if _is_headless():
            _spawn_headless(working_dir, command, model=model)
        elif is_macos():
            _spawn_macos(working_dir, command, model=model)
        elif is_windows():
            _spawn_windows(working_dir, command, model=model)
        else:
            _spawn_linux(working_dir, command, model=model)
    except Exception as exc:
        console.print(
            f"WARNING: Failed to spawn terminal for '{command}': {exc}\n"
            f"  Run manually: cd {working_dir} && buildteam {command}",
            style="yellow",
        )
