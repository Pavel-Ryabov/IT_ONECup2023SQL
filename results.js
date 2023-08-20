const fs = require('fs');

const OUTPUT_FILE = 'results.log';

const number = process.argv[2];

const scores = {};
const stats = {};
for (let i = 0; i < number; i++) {
  fs.readFileSync(`${__dirname}/log${i}.log`).toString().split('\n').forEach(line => {
    const playerIdx = line.indexOf('Player #');
    if (playerIdx !== -1) {
      const playerKey = line.substring(playerIdx, playerIdx + 9);
      if (!scores[playerKey]) {
        scores[playerKey] = [];
        stats[playerKey] = { wins: 0, sum: 0, min: Number.MAX_VALUE, avg: 0, max: 0 };
      }
      const scoreIdx = line.indexOf(' = ') + 3;
      const score = parseFloat(line.substring(scoreIdx));
      scores[playerKey].push(score);
    }
  });
}
for (let i = 0; i < number; i++) {
  let win;
  let winScore;
  for (let [player, playerScores] of Object.entries(scores)) {
    const score = playerScores[i];
    const playerStats = stats[player];
    playerStats.sum += score;
    if (score < playerStats.min) playerStats.min = score;
    if (score > playerStats.max) playerStats.max = score;
    if (!winScore || score > winScore) {
      winScore = score;
      win = player;
    }
  }
  stats[win].wins++;
}

let results = '';
for (let [player, playerStats] of Object.entries(stats)) {
  playerStats.avg = playerStats.sum / number;
  results += player + ' stats:\n';
  results += 'wins: ' + playerStats.wins + '\n';
  results += 'sum: ' + playerStats.sum + '\n';
  results += 'min: ' + playerStats.min + '\n';
  results += 'avg: ' + playerStats.avg + '\n';
  results += 'max: ' + playerStats.max + '\n';
  results += '\n';
}

for (let i = 0; i < number; i++) {
  for (let [player, playerScores] of Object.entries(scores)) {
    results += player + ': ' + playerScores[i] + '\n';
  }
  results += '\n';
}
fs.writeFileSync(__dirname + '/' + OUTPUT_FILE, results);