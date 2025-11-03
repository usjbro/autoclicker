import pytesseract
from PIL import Image

class OCRDetector:
    def __init__(self):
        pass

    def find_text_location(self, image, target_text="SHAKE"):
        gray = image.convert("L")
        data = pytesseract.image_to_data(gray, output_type=pytesseract.Output.DICT)
        for i, word in enumerate(data["text"]):
            if word.strip().upper() == target_text.upper():
                x = data["left"][i]
                y = data["top"][i]
                w = data["width"][i]
                h = data["height"][i]
                return (x + w // 2, y + h // 2)
        return None