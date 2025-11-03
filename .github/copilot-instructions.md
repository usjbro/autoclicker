# AI Agent Instructions for Legitimate AutoClicker

## Project Overview
This is a GUI-based auto-clicking utility built with Python's tkinter and pyautogui libraries. The application enables legitimate automation through configurable, randomized mouse clicks with built-in safety features.

## Architecture
The project follows a simple two-class architecture:
- `AutoClicker`: Core clicking logic and thread management (`autoclicker.py`)
- `AutoClickerGUI`: GUI interface and user input handling (`autoclicker.py`)

### Key Components
- Thread-based clicking implementation for non-blocking UI
- PyAutoGUI failsafe mechanisms
- Tkinter-based GUI with real-time status updates
- Keyboard hotkey integration

## Development Workflow
1. Environment Setup:
   ```bash
   # Python 3.8+ required
   pip install -r requirements.txt
   ```

2. Running the Application:
   ```bash
   python autoclicker.py
   ```

## Critical Patterns and Conventions

### Threading Pattern
The clicking operation runs in a separate thread to prevent UI blocking:
```python
self.click_thread = Thread(
    target=self.clicker.start_clicking,
    args=(min_interval, max_interval)
)
```

### Safety Features Implementation
1. PyAutoGUI Failsafe:
   ```python
   pyautogui.FAILSAFE = True  # Move mouse to corner to stop
   pyautogui.PAUSE = 0.1      # Required delay between actions
   ```

2. Multiple Stop Mechanisms:
   - ESC key
   - F6 toggle
   - Mouse to corner
   - GUI button

### Input Validation
All interval inputs must be validated:
```python
if min_interval <= 0 or max_interval <= 0:
    raise ValueError("Intervals must be positive")
```

## Testing and Debugging
- Test hotkeys (F6, ESC) functionality
- Verify failsafe by moving mouse to screen corners
- Monitor status label for real-time feedback
- Check thread cleanup on application exit

## External Dependencies
- `pyautogui`: Mouse control and failsafe mechanisms
- `keyboard`: Global hotkey handling
- `tkinter`: GUI framework (Python standard library)

## Integration Points
1. PyAutoGUI Safety Settings
2. System-wide Keyboard Hooks
3. Threading Events for State Management