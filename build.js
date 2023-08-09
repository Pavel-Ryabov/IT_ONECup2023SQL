const fs = require('fs');
const constants = require('./constants.json');

const TARGET_NAME = 'target.sql';
const EXCLUDES = ['scheme.sql', TARGET_NAME];

let target = '';
fs.readdirSync(__dirname).forEach(fileName => {
  const file = __dirname + '/' + fileName;
  if (fs.lstatSync(file).isDirectory() || !fileName.endsWith('.sql') || EXCLUDES.includes(fileName)) return;
  target += '-- ' + fileName + '\n';
  target += fs.readFileSync(file);
  target += '\n\n';
});

target = target.replace(/constants\.(.+)!/g, (substring, args) => constants[args]);

const targetDir = __dirname + '/target/';
if (!fs.existsSync(targetDir)){
  fs.mkdirSync(targetDir);
}
fs.writeFileSync(targetDir + TARGET_NAME, target);