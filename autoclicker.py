import tkinter as tk
from tkinter import ttk
import pyautogui
from pynput import keyboard
import random
import time
from threading import Thread, Event
from PIL import Image
import numpy as np

class AutoClicker:
    def __init__(self):
        self.running = False
        self.stop_event = Event()
        self.click_thread = None
        
        # Configure PyAutoGUI safety settings
        pyautogui.FAILSAFE = True  # Move mouse to corner to stop
        pyautogui.PAUSE = 0.1  # Add small delay between actions
        
    def find_white_text_regions(self, screenshot):
        """Find regions with white text (SHAKE) using color detection"""
        # Convert screenshot to numpy array
        img_array = np.array(screenshot)
        
        # Define white color threshold (RGB values close to white)
        # White text typically has high R, G, B values
        lower_white = np.array([200, 200, 200])  # Minimum RGB for "white"
        upper_white = np.array([255, 255, 255])  # Maximum RGB
        
        # Create mask for white pixels
        mask = np.all((img_array >= lower_white) & (img_array <= upper_white), axis=2)
        
        # Find coordinates of white pixels
        white_coords = np.argwhere(mask)
        
        if len(white_coords) == 0:
            return None
        
        # Find clusters of white pixels (potential text)
        # Group nearby white pixels together
        clusters = self.find_clusters(white_coords)
        
        # Return the largest cluster (most likely to be the SHAKE text)
        if clusters:
            largest_cluster = max(clusters, key=lambda c: len(c))
            # Calculate center of the cluster
            center_y = int(np.mean([coord[0] for coord in largest_cluster]))
            center_x = int(np.mean([coord[1] for coord in largest_cluster]))
            return (center_x, center_y)
        
        return None
    
    def find_clusters(self, coords, max_distance=50):
        """Group nearby coordinates into clusters"""
        if len(coords) == 0:
            return []
        
        clusters = []
        used = set()
        
        for i, coord in enumerate(coords):
            if i in used:
                continue
            
            cluster = [coord]
            used.add(i)
            
            # Find all nearby coordinates
            for j, other_coord in enumerate(coords):
                if j in used:
                    continue
                
                # Calculate distance
                distance = np.sqrt((coord[0] - other_coord[0])**2 + 
                                 (coord[1] - other_coord[1])**2)
                
                if distance < max_distance:
                    cluster.append(other_coord)
                    used.add(j)
            
            # Only keep clusters with significant number of pixels (real text)
            if len(cluster) > 100:  # Adjust threshold as needed
                clusters.append(cluster)
        
        return clusters
        
    def start_clicking(self, min_interval, max_interval, search_region=None):
        """Main clicking loop with color-based detection"""
        while not self.stop_event.is_set():
            if self.running:
                try:
                    # Take screenshot of specified region or full screen
                    if search_region:
                        screenshot = pyautogui.screenshot(region=search_region)
                        offset_x, offset_y = search_region[0], search_region[1]
                    else:
                        screenshot = pyautogui.screenshot()
                        offset_x, offset_y = 0, 0
                    
                    # Find white text regions
                    location = self.find_white_text_regions(screenshot)
                    
                    if location:
                        # Adjust coordinates if using region
                        click_x = location[0] + offset_x
                        click_y = location[1] + offset_y
                        
                        print(f"Found white text cluster at ({click_x}, {click_y})")
                        pyautogui.click(click_x, click_y)
                    else:
                        print("No white text found")
                        
                except Exception as e:
                    print(f"Error during detection: {e}")
                
                # Random delay between searches
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
        self.root.title("Color-Based AutoClicker")
        self.root.geometry("350x300")
        
        self.clicker = AutoClicker()
        self.search_region = None
        
        self.setup_gui()
        self.setup_hotkeys()
        
    def setup_gui(self):
        # Interval settings
        ttk.Label(self.root, text="Click Interval (seconds)").pack(pady=5)
        
        interval_frame = ttk.Frame(self.root)
        interval_frame.pack()
        
        ttk.Label(interval_frame, text="Min:").pack(side=tk.LEFT, padx=5)
        self.min_interval = ttk.Entry(interval_frame, width=10)
        self.min_interval.insert(0, "1.0")
        self.min_interval.pack(side=tk.LEFT)
        
        ttk.Label(interval_frame, text="Max:").pack(side=tk.LEFT, padx=5)
        self.max_interval = ttk.Entry(interval_frame, width=10)
        self.max_interval.insert(0, "2.0")
        self.max_interval.pack(side=tk.LEFT)
        
        # White threshold settings
        ttk.Label(self.root, text="White Threshold (200-255)").pack(pady=5)
        self.threshold = ttk.Entry(self.root)
        self.threshold.insert(0, "200")
        self.threshold.pack()
        
        # Search region info
        self.region_label = ttk.Label(self.root, text="Search Region: Full Screen")
        self.region_label.pack(pady=5)
        
        # Status label
        self.status_label = ttk.Label(self.root, text="Status: Stopped")
        self.status_label.pack(pady=5)
        
        # Control buttons
        self.toggle_button = ttk.Button(self.root, text="Start (F6)", command=self.toggle_clicking)
        self.toggle_button.pack(pady=5)
        
        ttk.Button(self.root, text="Set Search Region (F7)", command=self.set_region).pack(pady=2)
        ttk.Button(self.root, text="Reset to Full Screen", command=self.reset_region).pack(pady=2)
        ttk.Button(self.root, text="Exit (ESC)", command=self.stop_application).pack(pady=5)
        
    def setup_hotkeys(self):
        def on_press(key):
            try:
                if key == keyboard.Key.f6:
                    self.toggle_clicking()
                elif key == keyboard.Key.f7:
                    self.set_region()
                elif key == keyboard.Key.esc:
                    self.stop_application()
            except:
                pass
        
        self.listener = keyboard.Listener(on_press=on_press)
        self.listener.start()
    
    def set_region(self):
        """Let user define a search region by clicking two corners"""
        self.status_label.config(text="Click top-left corner in 3 seconds...")
        self.root.update()
        time.sleep(3)
        
        x1, y1 = pyautogui.position()
        
        self.status_label.config(text="Click bottom-right corner in 3 seconds...")
        self.root.update()
        time.sleep(3)
        
        x2, y2 = pyautogui.position()
        
        # Calculate region (x, y, width, height)
        x = min(x1, x2)
        y = min(y1, y2)
        width = abs(x2 - x1)
        height = abs(y2 - y1)
        
        self.search_region = (x, y, width, height)
        self.region_label.config(text=f"Region: ({x},{y}) {width}x{height}")
        self.status_label.config(text="Status: Stopped")
    
    def reset_region(self):
        """Reset to full screen search"""
        self.search_region = None
        self.region_label.config(text="Search Region: Full Screen")
        
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
                    args=(min_interval, max_interval, self.search_region)
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
        self.listener.stop()
        self.root.quit()
        
    def run(self):
        self.root.mainloop()

if __name__ == "__main__":
    app = AutoClickerGUI()
    app.run()