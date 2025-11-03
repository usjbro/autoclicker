import tkinter as tk
from tkinter import ttk
from click_session import ClickSession
from autoclicker import AutoClicker
import subprocess
import re
import pyautogui
import time

class AutoClickerGUI:
    def __init__(self, logger):
        self.logger = logger
        self.root = tk.Tk()
        self.root.title("OCR AutoClicker")
        self.session = ClickSession()
        self.clicker = AutoClicker(self.session, logger)
        self.setup_gui()

    def setup_gui(self):
        ttk.Label(self.root, text="Target Application (optional)").pack(pady=5)
        app_frame = ttk.Frame(self.root)
        app_frame.pack()
        self.app_entry = ttk.Entry(app_frame, width=25)
        self.app_entry.pack(side=tk.LEFT, padx=5)
        ttk.Button(app_frame, text="Find Window", command=self.find_app_window).pack(side=tk.LEFT)

        ttk.Label(self.root, text="Click Interval (seconds)").pack(pady=5)
        interval_frame = ttk.Frame(self.root)
        interval_frame.pack()
        ttk.Label(interval_frame, text="Min:").pack(side=tk.LEFT, padx=5)
        self.min_entry = ttk.Entry(interval_frame, width=10)
        self.min_entry.insert(0, "1.0")
        self.min_entry.pack(side=tk.LEFT)
        ttk.Label(interval_frame, text="Max:").pack(side=tk.LEFT, padx=5)
        self.max_entry = ttk.Entry(interval_frame, width=10)
        self.max_entry.insert(0, "2.0")
        self.max_entry.pack(side=tk.LEFT)

        self.region_label = ttk.Label(self.root, text="Search Region: Full Screen", wraplength=350)
        self.region_label.pack(pady=5)
        self.status = ttk.Label(self.root, text="Status: Stopped")
        self.status.pack(pady=5)
        self.toggle_btn = ttk.Button(self.root, text="Start", command=self.toggle)
        self.toggle_btn.pack(pady=5)
        ttk.Button(self.root, text="Set Manual Region (F7)", command=self.set_region).pack(pady=2)
        ttk.Button(self.root, text="Reset to Full Screen", command=self.reset_region).pack(pady=2)
        ttk.Button(self.root, text="Exit (ESC)", command=self.stop_application).pack(pady=5)

        self.root.bind("<F7>", lambda e: self.set_region())
        self.root.bind("<Escape>", lambda e: self.stop_application())

    def find_app_window(self):
        app_aliases = {
            "roblox": ["Roblox", "RobloxPlayer"],
            "chrome": ["Google Chrome", "chrome"],
            "safari": ["Safari"]
        }

        app_name = self.app_entry.get().strip()
        if not app_name:
            self.status.config(text="Please enter an app name")
            self.logger.warning("No app name entered for window detection")
            return

        self.logger.info(f"Attempting to locate window for '{app_name}'")
        app_names_to_try = app_aliases.get(app_name.lower(), [app_name])

        for try_name in app_names_to_try:
            script = f'''
            tell application "System Events"
                tell process "{try_name}"
                    set winPos to position of window 1
                    set winSize to size of window 1
                    return {{item 1 of winPos, item 2 of winPos, item 1 of winSize, item 2 of winSize}}
                end tell
            end tell
            '''
            try:
                result = subprocess.run(['osascript', '-e', script], capture_output=True, text=True, timeout=5)
                self.logger.debug(f"AppleScript output: {result.stdout.strip()}")
                if result.returncode == 0:
                    output = result.stdout.strip()
                    cleaned = re.sub(r'[^\d,\s]', '', output)
                    numbers = [int(x.strip()) for x in cleaned.split(',') if x.strip()]
                    if len(numbers) >= 4:
                        x, y, width, height = numbers[:4]
                        if width > 0 and height > 0:
                            self.session.region = (x, y, width, height)
                            self.region_label.config