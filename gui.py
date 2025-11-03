import tkinter as tk
from tkinter import ttk
from click_session import ClickSession
from autoclicker import AutoClicker

class AutoClickerGUI:
    def __init__(self):
        self.root = tk.Tk()
        self.root.title("OCR AutoClicker")
        self.session = ClickSession()
        self.clicker = AutoClicker(self.session)
        self.setup_gui()

    def setup_gui(self):
        ttk.Label(self.root, text="Min Interval").pack()
        self.min_entry = ttk.Entry(self.root)
        self.min_entry.insert(0, "1.0")
        self.min_entry.pack()

        ttk.Label(self.root, text="Max Interval").pack()
        self.max_entry = ttk.Entry(self.root)
        self.max_entry.insert(0, "2.0")
        self.max_entry.pack()

        self.status = ttk.Label(self.root, text="Stopped")
        self.status.pack()

        self.toggle_btn = ttk.Button(self.root, text="Start", command=self.toggle)
        self.toggle_btn.pack()

    def toggle(self):
        if not self.session.running:
            self.session.min_interval = float(self.min_entry.get())
            self.session.max_interval = float(self.max_entry.get())
            self.clicker.start()
            self.status.config(text="Running")
            self.toggle_btn.config(text="Stop")
        else:
            self.clicker.stop()
            self.status.config(text="Stopped")
            self.toggle_btn.config(text="Start")

    def run(self):
        self.root.mainloop()