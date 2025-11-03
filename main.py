from logger import setup_logger
from gui import AutoClickerGUI

logger = setup_logger()

if __name__ == "__main__":
    logger.info("Launching OCR AutoClicker GUI")
    try:
        app = AutoClickerGUI(logger)
        app.run()
    except KeyboardInterrupt:
        logger.info("Application interrupted by user")
    logger.info("Application exited")