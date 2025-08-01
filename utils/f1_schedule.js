const https = require('https');

// Use dynamic ESM-style import for node-fetch v3+
const fetch = (...args) =>
  import('node-fetch').then(({ default: fetch }) =>
    fetch(...args, {
      agent: new https.Agent({ family: 4 }) // force IPv4
    })
  );

function getDiffDays(a, b) {
  const msPerDay = 1000 * 60 * 60 * 24;
  return Math.floor((a - b) / msPerDay);
}

function getFlag(country) {
  const map = {
    Australia: "🇦🇺", China: "🇨🇳", Japan: "🇯🇵", Bahrain: "🇧🇭", "Saudi Arabia": "🇸🇦", USA: "🇺🇸",
    Italy: "🇮🇹", Monaco: "🇲🇨", Spain: "🇪🇸", Canada: "🇨🇦", Austria: "🇦🇹", UK: "🇬🇧",
    Belgium: "🇧🇪", Hungary: "🇭🇺", Netherlands: "🇳🇱", Azerbaijan: "🇦🇿", Singapore: "🇸🇬",
    Mexico: "🇲🇽", Brazil: "🇧🇷", Qatar: "🇶🇦", UAE: "🇦🇪",
    "United States": "🇺🇸", "United Arab Emirates": "🇦🇪"
  };
  return map[country] || "🏳️";
}

function parseLocalDateOnly(str) {
  const [y, m, d] = str.split("-").map(Number);
  return new Date(y, m - 1, d);
}

async function getF1Schedule() {
  const today = new Date();
  today.setHours(0, 0, 0, 0);

  let output = `# 🏎️ Formula 1\n\n`;

  // === Fetch schedule
  let raceData;
  try {
    const scheduleRes = await fetch('https://api.jolpi.ca/ergast/f1/current.json');
    const scheduleJson = await scheduleRes.json();
    raceData = scheduleJson.MRData.RaceTable.Races.map(race => ({
      name: race.raceName,
      date: parseLocalDateOnly(race.date),
      country: race.Circuit.Location.country
    }));
  } catch (err) {
    return output + `⚠️ Could not load race schedule.\n`;
  }

  const eventsToday = [];
  let nextRace = null;

  for (const event of raceData) {
    const raceDate = event.date;
    const practiceDate = new Date(raceDate);
    const qualiDate = new Date(raceDate);
    practiceDate.setDate(raceDate.getDate() - 2);
    qualiDate.setDate(raceDate.getDate() - 1);

    const isPractice = getDiffDays(today, practiceDate) === 0;
    const isQuali = getDiffDays(today, qualiDate) === 0;
    const isRace = getDiffDays(today, raceDate) === 0;

    if (isPractice || isQuali || isRace) {
      const emoji = isRace ? "🏁" : isQuali ? "⏱️" : "🛠️";
      const desc = isRace ? "Race Day" : isQuali ? "Qualifying / Sprint" : "Practice";
      eventsToday.push({ ...event, desc, emoji });
    } else if (!nextRace && getDiffDays(raceDate, today) > 0) {
      nextRace = event;
    }
  }

  if (eventsToday.length > 0) {
    output += `### 📆 This Weekend:\n`;
    for (const event of eventsToday) {
      output += `- ${event.emoji} **${event.desc}** — ${event.name} ${getFlag(event.country)}\n`;
    }
  } else if (nextRace) {
    const practiceDate = new Date(nextRace.date);
    practiceDate.setDate(practiceDate.getDate() - 2);
    const daysUntilPractice = getDiffDays(practiceDate, today);

    output += `**⏳ Next Grand Prix:**\n`;
    output += `- ${nextRace.name} ${getFlag(nextRace.country)} — ${nextRace.date.toISOString().split("T")[0]}\n`;
    output += `- ⌛ Practice starts in ${daysUntilPractice} day${daysUntilPractice !== 1 ? "s" : ""} (on ${practiceDate.toISOString().split("T")[0]})\n`;
  } else {
    output += `🚫 No upcoming Formula 1 races found.\n`;
  }

  // === Fetch standings
  try {
    const driverRes = await fetch('https://api.jolpi.ca/ergast/f1/current/driverStandings.json');
    const driverData = await driverRes.json();
    const drivers = driverData.MRData.StandingsTable.StandingsLists[0].DriverStandings;

    output += `\n### 📊 Driver Standings\n`;
    for (let i = 0; i < Math.min(5, drivers.length); i++) {
      const d = drivers[i];
      const name = `${d.Driver.givenName} ${d.Driver.familyName}`;
      const team = d.Constructors[0].name;
      const points = d.points;

      const styledName = d.Driver.familyName === "Norris"
        ? `<div style="color: yellow; text-shadow: 0 0 5px gold; font-weight: bold;">${name}</div>`
        : name;


      output += `- ${d.position}. ${styledName} (${team}) – ${points} pts\n`;
    }

    const constructorRes = await fetch('https://api.jolpi.ca/ergast/f1/current/constructorStandings.json');
    const constructorData = await constructorRes.json();
    const constructors = constructorData.MRData.StandingsTable.StandingsLists[0].ConstructorStandings;

    output += `\n### 🏎️ Constructor Standings\n`;
    for (let i = 0; i < Math.min(5, constructors.length); i++) {
      const c = constructors[i];
      const styledName = c.Constructor.name === "McLaren"
        ? `<div style="color: yellow; text-shadow: 0 0 5px gold; font-weight: bold;">${c.name}</div>`
        : c.Constructor.name;

      output += `- ${c.position}. ${styledName} – ${c.points} pts\n`;
    }

  } catch (err) {
    output += `\n⚠️ Could not load standings.\n`;
  }

  return output;
}

module.exports = getF1Schedule;