const STORAGE_KEY = "autoclicker-save";

const state = {
  score: 0,
  autoClickerCount: 0,
};

function loadState() {
  const saved = localStorage.getItem(STORAGE_KEY);
  if (!saved) return;

  try {
    const parsed = JSON.parse(saved);
    if (typeof parsed.score === "number") state.score = parsed.score;
    if (typeof parsed.autoClickerCount === "number") {
      state.autoClickerCount = parsed.autoClickerCount;
    }
  } catch {
    // Corrupt save data — start fresh instead of crashing the page.
  }
}

function saveState() {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
}

function autoClickerCost() {
  return Math.floor(10 * Math.pow(1.15, state.autoClickerCount));
}

const scoreEl = document.getElementById("score");
const rateEl = document.getElementById("rate");
const clickButton = document.getElementById("click-button");
const buyButton = document.getElementById("buy-auto-clicker");
const costEl = document.getElementById("auto-clicker-cost");
const countEl = document.getElementById("auto-clicker-count");
const resetButton = document.getElementById("reset-button");

function render() {
  scoreEl.textContent = Math.floor(state.score);
  rateEl.textContent = state.autoClickerCount;
  countEl.textContent = state.autoClickerCount;

  const cost = autoClickerCost();
  costEl.textContent = cost;
  buyButton.disabled = state.score < cost;
}

clickButton.addEventListener("click", () => {
  state.score += 1;
  render();
  saveState();
});

buyButton.addEventListener("click", () => {
  const cost = autoClickerCost();
  if (state.score < cost) return;

  state.score -= cost;
  state.autoClickerCount += 1;
  render();
  saveState();
});

resetButton.addEventListener("click", () => {
  state.score = 0;
  state.autoClickerCount = 0;
  render();
  saveState();
});

// TODO: play a short sound effect when the click button is pressed
// TODO: add a prestige system that resets progress for a permanent multiplier

setInterval(() => {
  if (state.autoClickerCount > 0) {
    state.score += state.autoClickerCount;
    render();
    saveState();
  }
}, 1000);

loadState();
render();
