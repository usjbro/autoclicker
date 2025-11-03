# OCR AutoClicker

Modular autoclicker using OCR to detect "SHAKE" button.

## Structure
- `main.py`: Entry point
- `gui.py`: GUI logic
- `autoclicker.py`: Clicking logic
- `ocr_detector.py`: OCR detection
- `click_session.py`: Session settings

## Setup
1. Install Python 3.8+
2. `brew install tesseract` (macOS)
3. `pip install -r requirements.txt`

## Usage
Run with:
```bash
python main.py