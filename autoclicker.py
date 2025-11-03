import tkinter as tk
from tkinter import ttk
import pyautogui
import keyboard
import random
import time
from threading import Thread, Event

class AutoClicker:
    def __init__(self):
        self.running = False
        self.stop_event = Event()
        self.click_thread = None
        
        # Configure PyAutoGUI safety settings
        pyautogui.FAILSAFE = True  # Move mouse to corner to stop
        pyautogui.PAUSE = 0.1  # Add small delay between actions
        
    def start_clicking(self, min_interval, max_interval):
        while not self.stop_event.is_set():
            if self.running:
                pyautogui.click()
                # Random delay between clicks for natural behavior
                delay = random.uniform(min_interval, max_interval)
                time.sleep(delay)
                
    def toggle(self):
        self.running = not self.running
        
    def stop(self):
        self.stop_event.set()
        if self.click_thread:
            self.click_thread.join()

class AutoClickerGUI:
    def __init__(self):
        self.root = tk.Tk()
        self.root.title("Legitimate AutoClicker")
        self.root.geometry("300x200")
        
        self.clicker = AutoClicker()
        
        self.setup_gui()
        self.setup_hotkeys()
        
    def setup_gui(self):
        # Interval settings
        ttk.Label(self.root, text="Click Interval (seconds)").pack(pady=5)
        
        self.min_interval = ttk.Entry(self.root)
        self.min_interval.insert(0, "1.0")
        self.min_interval.pack()
        
        self.max_interval = ttk.Entry(self.root)
        self.max_interval.insert(0, "2.0")
        self.max_interval.pack()
        
        # Status label
        self.status_label = ttk.Label(self.root, text="Status: Stopped")
        self.status_label.pack(pady=10)
        
        # Control buttons
        self.toggle_button = ttk.Button(self.root, text="Start (F6)", command=self.toggle_clicking)
        self.toggle_button.pack(pady=5)
        
        ttk.Button(self.root, text="Exit (ESC)", command=self.stop_application).pack(pady=5)
        
    def setup_hotkeys(self):
        keyboard.on_press_key("F6", lambda _: self.toggle_clicking())
        keyboard.on_press_key("esc", lambda _: self.stop_application())
        
    def toggle_clicking(self):
        if not self.clicker.running:
            try:
                min_interval = float(self.min_interval.get())
                max_interval = float(self.max_interval.get())
                
                if min_interval <= 0 or max_interval <= 0:
                    raise ValueError("Intervals must be positive")
                
                self.clicker.stop_event.clear()
                self.clicker.click_thread = Thread(
                    target=self.clicker.start_clicking,
                    args=(min_interval, max_interval)
                )
                self.clicker.click_thread.start()
                self.clicker.toggle()
                self.status_label.config(text="Status: Running")
                self.toggle_button.config(text="Stop (F6)")
            except ValueError as e:
                self.status_label.config(text=f"Error: Invalid interval values")
        else:
            self.clicker.toggle()
            self.status_label.config(text="Status: Stopped")
            self.toggle_button.config(text="Start (F6)")
            
    def stop_application(self):
        self.clicker.stop()
        self.root.quit()
        
    def run(self):
        self.root.mainloop()

if __name__ == "__main__":
    app = AutoClickerGUI()
    app.run()