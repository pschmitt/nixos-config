const WIDTH = 10;
const HEIGHT = 7;

const same = (a, b) => a[0] === b[0] && a[1] === b[1];
const distance = (a, b) => Math.abs(a[0] - b[0]) + Math.abs(a[1] - b[1]);

/**
 * A self-playing snake game: the snake greedily chases the food and renders
 * as an emoji grid, so every frame can be shown by editing a single message.
 */
export class SnakeGame {
  constructor(seed = Date.now()) {
    this.seed = seed & 0x7fffffff;
    this.snake = [[2, 3], [1, 3], [0, 3]];
    this.score = 0;
    this.dead = false;
    this.food = this.randomFood();
  }

  random(max) {
    this.seed = (this.seed * 1103515245 + 12345) & 0x7fffffff;
    return this.seed % max;
  }

  randomFood() {
    let food;
    do {
      food = [this.random(WIDTH), this.random(HEIGHT)];
    } while (this.snake.some((s) => same(s, food)));
    return food;
  }

  isFree(p) {
    return p[0] >= 0 && p[0] < WIDTH && p[1] >= 0 && p[1] < HEIGHT && !this.snake.slice(0, -1).some((s) => same(s, p));
  }

  step() {
    const [hx, hy] = this.snake[0];
    const moves = [[1, 0], [-1, 0], [0, 1], [0, -1]]
      .map(([dx, dy]) => [hx + dx, hy + dy])
      .filter((p) => this.isFree(p))
      .sort((a, b) => distance(a, this.food) - distance(b, this.food));
    if (moves.length === 0) {
      this.dead = true;
      return;
    }
    this.snake.unshift(moves[0]);
    if (same(moves[0], this.food)) {
      this.score++;
      this.food = this.randomFood();
    } else {
      this.snake.pop();
    }
  }

  render(label = '') {
    const rows = [];
    for (let y = 0; y < HEIGHT; y++) {
      let row = '';
      for (let x = 0; x < WIDTH; x++) {
        const p = [x, y];
        if (same(this.snake[0], p)) row += '🟢';
        else if (this.snake.some((s) => same(s, p))) row += '🟩';
        else if (same(this.food, p)) row += '🍎';
        else row += '⬛';
      }
      rows.push(row);
    }
    return `🐍 **snake** — score ${this.score}${label ? ` — ${label}` : ''}\n\n${rows.join('\n')}`;
  }
}
