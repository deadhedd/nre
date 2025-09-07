const fs = require('fs');
const path = require('path');
const os = require('os');
const commit = require('./commit');
const fetch = (...args) => import('node-fetch').then(({ default: fetch }) => fetch(...args));

// Coordinates for your location
const LAT = 47.7423;
const LON = -121.9857;

// Define the Open-Meteo API endpoint
const API_URL = `https://api.open-meteo.com/v1/forecast?latitude=${LAT}&longitude=${LON}&hourly=temperature_2m,dew_point_2m&temperature_unit=fahrenheit&timezone=America/Los_Angeles`;

const vaultRoot = path.join(os.homedir(), 'automation/obsidian/vaults/Main');

async function checkYardWorkSuitability() {
  try {
    const response = await fetch(API_URL);
    const data = await response.json();

    const times = data.hourly.time;
    const temperatures = data.hourly.temperature_2m;
    const dewPoints = data.hourly.dew_point_2m;

    const today = new Date().toLocaleDateString('en-CA', { timeZone: 'America/Los_Angeles' });
    let earlyUnsuitable = false;
    let highTemp = -Infinity;

    for (let i = 0; i < times.length; i++) {
      const dateStr = times[i].slice(0, 10);
      if (dateStr === today) {
        const hour = parseInt(times[i].slice(11, 13), 10);
        const temp = temperatures[i];
        const dew = dewPoints[i];
        if (temp > highTemp) {
          highTemp = temp;
        }
        if (hour >= 0 && hour <= 6 && temp < dew) {
          earlyUnsuitable = true;
        }
      }
    }

    const unsuitable = earlyUnsuitable || highTemp >= 70;

    const message = unsuitable
      ? "❌ Not ideal for yard work today."
      : "✅ Good yard work conditions expected today.";

    // Build the full path to the daily note
    const notePath = path.join(
      vaultRoot,
      '000 - General Knowledge, Information Science, and Computing/005 - Computer Programming, Information, and Security/005.7 - Data/Daily Notes',
      `${today}.md`
    );

    // Read the existing daily note
    let noteContent = fs.readFileSync(notePath, 'utf8');

    // Replace the placeholder with the message
    noteContent = noteContent.replace('<!-- yard-work-check -->', message);

    // Write the updated content back to the file
    fs.writeFileSync(notePath, noteContent, 'utf8');

    // --- Commit only (post-commit hook will auto-push) ---
    commit(vaultRoot, notePath, `yard work suitability: ${today}`);

    console.log("Yard work suitability check completed.");
  } catch (error) {
    console.error("Error checking yard work suitability:", error);
  }
}

checkYardWorkSuitability();
