class ClickSession:
    def __init__(self, min_interval=1.0, max_interval=2.0, target_text="SHAKE", region=None):
        self.min_interval = min_interval
        self.max_interval = max_interval
        self.target_text = target_text
        self.region = region
        self.running = False