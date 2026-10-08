#!/usr/bin/env python3
"""End-to-end UI test for TimeZoneBar.app, driven through the Accessibility API.

Needs: build/TimeZoneBar.app (scripts/build-app.sh) and Accessibility + Screen Recording
permission for the terminal running it. Expected times are computed independently with
Python's zoneinfo, not with the app's code.

WARNING: resets the app's saved preferences (defaults domain com.timezonebar.TimeZoneBar) and briefly
switches the system appearance to light and dark (restored afterwards). It also moves the mouse.

Usage: scripts/ui-test.py [screenshot-dir]   (default: build/screenshots)
"""
import os
import re
import subprocess
import sys
import time
from datetime import datetime, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / "build/TimeZoneBar.app"
AXCTL = ROOT / "build/axctl"
BUNDLE = "com.timezonebar.TimeZoneBar"
SHOTS = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "build/screenshots"
LOCAL = re.sub(r"^.*/zoneinfo[^/]*/", "", os.path.realpath("/etc/localtime"))

failures = []


def log(msg):
    print(msg, flush=True)


def check(cond, msg):
    log(("  PASS " if cond else "  FAIL ") + msg)
    if not cond:
        failures.append(msg)


def ax(*args, ok=True):
    r = subprocess.run([str(AXCTL), *map(str, args)], capture_output=True, text=True)
    if "panel is not open" in r.stderr:
        # The panel closes whenever another app takes focus (e.g. a notification); reopen and retry.
        log("  (panel was closed by a focus change; reopening)")
        subprocess.run([str(AXCTL), "open-panel"])
        time.sleep(0.8)
        r = subprocess.run([str(AXCTL), *map(str, args)], capture_output=True, text=True)
    if "panel is not open" in r.stderr:
        subprocess.run([str(AXCTL), "open-panel"])
        time.sleep(0.8)
        r = subprocess.run([str(AXCTL), *map(str, args)], capture_output=True, text=True)
    if ok and r.returncode != 0:
        raise RuntimeError(f"axctl {' '.join(map(str, args))}: {r.stderr.strip()}")
    return r.stdout.strip()


def get(identifier):
    return ax("get", identifier)


def frame(identifier):
    return [int(v) for v in ax("frame", identifier).split()]


def wait_for(pred, timeout=5.0, step=0.2):
    end = time.time() + timeout
    while time.time() < end:
        try:
            if pred():
                return True
        except RuntimeError:
            pass
        time.sleep(step)
    return False


def running():
    return subprocess.run(["pgrep", "-f", "TimeZoneBar.app/Contents/MacOS/TimeZoneBar"],
                          capture_output=True).returncode == 0


def quit_app():
    subprocess.run(["pkill", "-f", "TimeZoneBar.app/Contents/MacOS/TimeZoneBar"])
    wait_for(lambda: not running(), 5)


def launch():
    for attempt in range(3):  # LaunchServices can briefly refuse right after the app quit (-600)
        if subprocess.run(["open", str(APP)]).returncode == 0:
            break
        time.sleep(1)
    check(wait_for(lambda: running() and ax("menubar", ok=False) != "", 10), "app launched and menu bar item exists")


def open_panel():
    for attempt in range(3):
        if ax("window") != "none":
            break
        if attempt:
            log(f"  (status item click #{attempt + 1}: panel did not appear yet)")
        ax("open-panel")
        wait_for(lambda: ax("window") != "none", 2)
    check(ax("window") != "none", "panel opened")
    time.sleep(0.6)


def shot(name):
    SHOTS.mkdir(parents=True, exist_ok=True)
    x, y, w, h = [int(v) for v in ax("window").split()]
    path = SHOTS / f"{name}.png"
    subprocess.run(["screencapture", "-x", "-R", f"{x - 10},{y - 32},{w + 20},{h + 42}", str(path)], check=True)
    log(f"  shot {path}")


def first_result():
    m = re.search(r"result-(\S+)", ax("dump"))
    return m.group(1) if m else None


def row_ids():
    return re.findall(r"slider-(\S+)", ax("dump"))


def expected(dt, zone):
    """(HH:MM, day difference vs local) for aware datetime dt in zone."""
    z = dt.astimezone(ZoneInfo(zone))
    l = dt.astimezone(ZoneInfo(LOCAL))
    return z.strftime("%H:%M"), (z.date() - l.date()).days


def check_rows(instant, zones, label):
    for zone in zones:
        hhmm, days = expected(instant, zone)
        shown = get(f"time-{zone}")
        date = get(f"date-{zone}")
        tag = "+1 day" if days == 1 else "−1 day" if days == -1 else None
        ok_day = (tag in date) if tag else ("day" not in date)
        check(shown == hhmm and ok_day,
              f"{label}: {zone} shows {shown} [{date}], expected {hhmm} {tag or 'same day'}")


def main():
    if not AXCTL.exists():
        subprocess.run(["swiftc", "-O", "-o", str(AXCTL), str(ROOT / "scripts/uitest/axctl.swift")], check=True)
    log(f"Local zone: {LOCAL}")

    log("1. Fresh launch as a menu-bar-only app")
    quit_app()
    subprocess.run(["defaults", "delete", BUNDLE], capture_output=True)
    launch()
    info = subprocess.run(["lsappinfo", "info", "-only", "ApplicationType", BUNDLE],
                          capture_output=True, text=True).stdout
    check("UIElement" in info, f"ApplicationType is UIElement (no Dock icon): {info.strip()}")
    mx, my, mw, mh = [int(v) for v in ax("menubar").split()]
    SHOTS.mkdir(parents=True, exist_ok=True)
    subprocess.run(["screencapture", "-x", "-R", f"{mx - 200},0,{mw + 400},{mh + 6}", str(SHOTS / "01-menubar.png")])
    open_panel()
    check(row_ids() == [LOCAL], f"default list is just the local zone: {row_ids()}")
    check(get(f"local-{LOCAL}") == "Local", "local zone is marked Local")
    shot("02-panel-initial")

    log("2. Add zones through the search picker")
    panel_top = int(ax("window").split()[1])
    for query, zone in [("Tokyo", "Asia/Tokyo"), ("london", "Europe/London"), ("New York", "America/New_York"),
                        ("Kathmandu", "Asia/Kathmandu"), ("PST", "America/Los_Angeles"), ("Chatham", "Pacific/Chatham")]:
        ax("press", "add")
        wait_for(lambda: "search" in ax("dump"), 3)
        ax("type", "search", query)
        found = wait_for(lambda: first_result() == zone, 3)
        check(found, f"search '{query}' lists {zone} first")
        top = int(ax("window").split()[1])
        field_y = frame("search")[1]
        check(top == panel_top and field_y - top < 90,
              f"search view sits at the top of the attached panel (top {top}, field +{field_y - top}pt)")
        if query in ("Tokyo", "PST"):
            shot(f"03-search-{query}")
        ax("press", f"result-{zone}")
        wait_for(lambda: zone in row_ids(), 3)
    zones = [LOCAL, "Asia/Tokyo", "Europe/London", "America/New_York", "Asia/Kathmandu",
             "America/Los_Angeles", "Pacific/Chatham"]
    check(row_ids() == zones, f"rows after adding: {row_ids()}")
    top = int(ax("window").split()[1])
    check(top == panel_top, f"panel stays attached to the menu bar after adding zones (top {top} vs {panel_top})")
    check(get("offset-Asia/Tokyo") == "UTC+9 · JST", f"Tokyo offset label: {get('offset-Asia/Tokyo')}")
    check(get("offset-Asia/Kathmandu") == "UTC+5:45", f"Kathmandu offset label: {get('offset-Asia/Kathmandu')}")
    shot("04-zones-added")

    log("3. Set Tokyo's slider to 09:00 (Accessibility value)")
    tokyo_now = datetime.now(ZoneInfo("Asia/Tokyo"))
    ax("set", "slider-Asia/Tokyo", 540)
    time.sleep(0.5)
    instant = tokyo_now.replace(hour=9, minute=0, second=0, microsecond=0)
    check(get("time-Asia/Tokyo") == "09:00", f"Tokyo shows {get('time-Asia/Tokyo')}")
    check_rows(instant, zones, "Tokyo 09:00")
    check("from now" in get("status"), f"status shows offset: {get('status')}")
    shot("05-tokyo-0900")

    log("3b. Crossing midnight: Tokyo slider to its right end (24:00)")
    ax("set", "slider-Asia/Tokyo", 1440)
    time.sleep(0.5)
    instant = (instant.replace(hour=0) + timedelta(days=1))  # 24:00 = 00:00 of the next Tokyo day
    check(get("time-Asia/Tokyo") == "00:00", f"Tokyo shows {get('time-Asia/Tokyo')} at the slider's end")
    check(instant.strftime("%-d") in get("date-Asia/Tokyo"), f"Tokyo date moved to {get('date-Asia/Tokyo')}")
    check_rows(instant, zones, "Tokyo 24:00")
    ax("set", "slider-Asia/Tokyo", 540)  # 09:00 on the (new) Tokyo day now shown
    time.sleep(0.3)
    instant = instant.replace(hour=9)
    check_rows(instant, zones, "Tokyo 09:00 next day")

    log("4. Drag London's slider with the real mouse to 12:00")
    x, y, w, h = frame("slider-Europe/London")
    thumb = 14
    london_day = instant.astimezone(ZoneInfo("Europe/London"))
    cur = int(get("slider-Europe/London"))
    from_x = x + thumb / 2 + (w - thumb) * min(max(cur, 0), 1440) / 1440
    to_x = x + thumb / 2 + (w - thumb) * 0.5
    ax("drag", from_x, y + thumb / 2, to_x, y + thumb / 2)
    time.sleep(0.5)
    instant = london_day.replace(hour=12, minute=0, second=0, microsecond=0)
    check(get("time-Europe/London") == "12:00", f"London shows {get('time-Europe/London')}")
    check_rows(instant, zones, "London 12:00")
    shot("06-london-1200-drag")

    log("5. 'Now' resets to live time and ticking resumes")
    ax("press", "now")
    time.sleep(0.5)
    check(get("status") == "Live", f"status after Now: {get('status')}")
    now = datetime.now(ZoneInfo(LOCAL))
    for zone in zones:
        shown = get(f"time-{zone}")
        ok = shown in {expected(now + timedelta(minutes=d), zone)[0] for d in (-1, 0, 1)}
        check(ok, f"live: {zone} shows {shown}, now is {expected(now, zone)[0]}")
    before = get(f"time-{LOCAL}")
    ticked = wait_for(lambda: get(f"time-{LOCAL}") != before, 65, 1)
    check(ticked, f"live clock ticked from {before} to {get(f'time-{LOCAL}')}")
    shot("07-live")

    log("6. Reorder by dragging a row")
    sx, sy, sw, sh = frame("time-Asia/Kathmandu")
    tx, ty, tw, th = frame("time-Asia/Tokyo")
    # Grab the row by its time label and drop it above Tokyo's row.
    ax("drag", sx + sw / 2, sy + sh / 2, tx + tw / 2, ty - 20)
    time.sleep(0.8)
    order = row_ids()
    check(order.index("Asia/Kathmandu") < order.index("Asia/Tokyo"), f"Kathmandu dragged above Tokyo: {order}")

    log("7. Remove a zone")
    ax("press", "remove-Pacific/Chatham")
    time.sleep(0.4)
    check("Pacific/Chatham" not in row_ids(), f"Chatham removed: {row_ids()}")

    log("8. 12h format")
    ax("press", "clockFormat#2")
    time.sleep(0.4)
    check(re.search(r"(AM|PM)$", get("time-Asia/Tokyo")) is not None, f"12h time: {get('time-Asia/Tokyo')}")
    saved_order = row_ids()
    shot("08-12h-reordered")

    log("9. Quit via the Quit button and relaunch")
    ax("press", "quit", ok=False)  # the app exits before answering, so AX reports an error
    check(wait_for(lambda: not running(), 5), "Quit button terminated the app")
    launch()
    open_panel()
    check(row_ids() == saved_order, f"order persisted: {row_ids()}")
    check(re.search(r"(AM|PM)$", get("time-Asia/Tokyo")) is not None, "12h setting persisted")
    shot("09-after-relaunch")

    log("10. Light and dark appearance (system setting toggled, then restored)")
    original_dark = system_dark_mode()
    try:
        for mode in ["light", "dark"]:
            quit_app()
            set_system_dark_mode(mode == "dark")
            time.sleep(3)
            launch()
            open_panel()
            appearance_shots(mode)
    finally:
        set_system_dark_mode(original_dark)
    quit_app()
    launch()

    log("")
    if failures:
        log(f"{len(failures)} FAILURE(S):")
        for f in failures:
            log(f"  - {f}")
        sys.exit(1)
    log("ALL UI CHECKS PASSED")


def system_dark_mode():
    r = subprocess.run(["osascript", "-e", 'tell application "System Events" to tell appearance preferences '
                        'to get dark mode'], capture_output=True, text=True, check=True)
    return r.stdout.strip() == "true"


def set_system_dark_mode(dark):
    subprocess.run(["osascript", "-e", 'tell application "System Events" to tell appearance preferences '
                    f'to set dark mode to {"true" if dark else "false"}'], check=True)


def appearance_shots(mode):
    ax("set", "slider-Asia/Tokyo", 1380)  # 23:00 Tokyo: puts some rows on other days
    time.sleep(0.5)
    top = int(ax("window").split()[1])
    shot(f"10-{mode}")
    ax("press", "add")
    time.sleep(0.3)
    ax("type", "search", "CET")
    time.sleep(0.5)
    wx, wy, ww, wh = [int(v) for v in ax("window").split()]
    field_y = frame("search")[1]
    check(wy == top and field_y - wy < 90,
          f"{mode}: search view is at the top of a panel attached to the menu bar "
          f"(panel top {wy} vs {top}, field {field_y - wy}pt below it, panel height {wh})")
    shot(f"11-{mode}-search")


if __name__ == "__main__":
    main()
