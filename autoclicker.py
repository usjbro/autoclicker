import pyautogui
import random
import time
from threading import Thread, Event
from ocr_detector import OCRDetector

class AutoClicker:
    def __init__(self, session, logger):
        self.session = session
        self.logger = logger
        self.detector = OCRDetector(logger)
        self.stop_event = Event()
        self.thread = None
        pyautogui.FAILSAFE = True
        pyautogui.PAUSE = 0.1

    def start(self):
        self.logger.info("Starting autoclicker thread")
        self.stop_event.clear()
        self.session.running = True
        self.thread = Thread(target=self.run)
        self.thread.start()

    def stop(self):
        self.logger.info("Stopping autoclicker thread")
        self.session.running = False
        self.stop_event.set()
        if self.thread:
            self.thread.join()

    def run(self):
        while not self.stop_event.is_set():
            if self.session.running:
                try:
                    screenshot = pyautogui.screenshot(region=self.session.region) if self.session.region else pyautogui.screenshot()
                    self.logger.debug(f"Screenshot captured (region: {self.session.region})")
                    offset_x, offset_y = self.session.region[:2] if self.session.region else (0, 0)
                    location = self.detector.find_text_location(screenshot, self.session.target_text)
                    if location:
                        click_x = location[0] + offset_x
                        click_y = location[1] + offset_y
                        pyautogui.moveTo(click_x, click_y, duration=0.2)
                        pyautogui.click()
                        self.logger.info(f"Clicked at ({click_x}, {click_y})")
                    else:
                        self.logger.debug("No target text found")
                except Exception as e:
                    self.logger.error(f"Clicking error: {e}")
                delay = random.uniform(self.session.min_interval, self.session.max_interval)
                self.logger.debug(f"Sleeping for {delay:.2f} seconds")
                time.sleep(delay)
            else:
                time.sleep(0.1)