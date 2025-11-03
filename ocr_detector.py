import pytesseract
from PIL import Image

class OCRDetector:
    def __init__(self, logger):
        self.logger = logger
        pytesseract.pytesseract.tesseract_cmd = "/opt/homebrew/bin/tesseract"

    def find_text_location(self, image, target_text="SHAKE"):
        self.logger.debug("Starting OCR scan...")
        gray = image.convert("L").point(lambda x: 0 if x < 200 else 255, '1')
        try:
            data = pytesseract.image_to_data(gray, output_type=pytesseract.Output.DICT)
            for i, word in enumerate(data["text"]):
                if word.strip().upper() == target_text.upper():
                    x = data["left"][i]
                    y = data["top"][i]
                    w = data["width"][i]
                    h = data["height"][i]
                    center = (x + w // 2, y + h // 2)
                    self.logger.info(f"OCR found '{target_text}' at {center}")
                    return center
            self.logger.warning(f"OCR did not find '{target_text}'")
        except Exception as e:
            self.logger.error(f"OCR error: {e}")
        return None