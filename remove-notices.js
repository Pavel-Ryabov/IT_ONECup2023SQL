const fs = require('fs');
const filePath = process.argv[2];

fs.writeFileSync(filePath, fs.readFileSync(filePath).toString().replace(/raise notice[\s\S]+?;/gm, ''));