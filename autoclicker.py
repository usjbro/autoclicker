import pyautogui
import random
import time
from threading import Thread, Event
from ocr_detector import OCRDetector

class AutoClicker:
    def __init__(self, session):
        self.session = session
        self.detector = OCRDetector()
        self.stop_event = Event()
        self.thread = None
        pyautogui.FAILSAFE = True
        pyautogui.PAUSE = 0.1

    def start(self):
        self.stop_event.clear()
        self.session.running = True
        self.thread = Thread(target=self.run)
        self.thread.start()

    def stop(self):
        self.session.running = False
        self.stop_event.set()
        if self.thread:
            self.thread.join()

    def run(self):
        while not self.stop_event.is_set():
            if self.session.running:
                screenshot = pyautogui.screenshot(region=self.session.region) if self.session.region else pyautogui.screenshot()
                offset_x, offset_y = self.session.region[:2] if self.session.region else (0, 0)
                location = self.detector.find_text_location(screenshot, self.session.target_text)
                if location:
                    pyautogui.moveTo(location[0] + offset_x, location[1] + offset_y, duration=0.2)
                    pyautogui.click()
                time.sleep(random.uniform(self.session.min_interval, self.session.max_interval))