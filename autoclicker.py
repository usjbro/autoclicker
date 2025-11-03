import pytesseract
from PIL import ImageDraw

def find_text_location(self, screenshot, target_text="SHAKE"):
    """Use OCR to find the location of target text in screenshot"""
    gray = screenshot.convert("L")  # Convert to grayscale for better OCR
    data = pytesseract.image_to_data(gray, output_type=pytesseract.Output.DICT)

    for i, word in enumerate(data["text"]):
        if word.strip().upper() == target_text.upper():
            x = data["left"][i]
            y = data["top"][i]
            w = data["width"][i]
            h = data["height"][i]
            center_x = x + w // 2
            center_y = y + h // 2
            print(f"OCR found '{target_text}' at ({center_x}, {center_y})")
            return (center_x, center_y)

    print(f"OCR did not find '{target_text}'")
    return None