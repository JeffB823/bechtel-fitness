#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
global.window = {};
require(path.join(root, 'data.js'));

const source = global.window.WORKOUT_DATA;
const snapshotPath = path.join(root, 'ios', 'BechtelFitness', 'BechtelFitness', 'ProgramData.json');
const snapshot = JSON.parse(fs.readFileSync(snapshotPath, 'utf8'));

function fail(message) {
  console.error(message);
  process.exit(1);
}

if (!source || !Array.isArray(source.phases)) {
  fail('data.js did not expose window.WORKOUT_DATA.phases');
}

if (JSON.stringify(source.phases) !== JSON.stringify(snapshot.phases)) {
  fail('ProgramData.json phases differ from data.js. Regenerate the snapshot before building native.');
}

const phaseCount = source.phases.length;
const dayCount = source.phases.reduce((count, phase) => count + phase.days.length, 0);
const exerciseCount = source.phases.reduce((count, phase) => {
  return count + phase.days.reduce((dayTotal, day) => dayTotal + day.exercises.length, 0);
}, 0);

console.log(`Program snapshot matches data.js (${phaseCount} phases, ${dayCount} days, ${exerciseCount} exercises).`);
