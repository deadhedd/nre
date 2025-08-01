function getCurrentYear() {
  return new Date().getFullYear();
}

function getPrevYear() {
  return getCurrentYear() - 1;
}

function getNextYear() {
  return getCurrentYear() + 1;
}

function getCurrentQuarter() {
  return Math.ceil((new Date().getMonth() + 1) / 3);
}

function getQuarterTag() {
  return `Q${getCurrentQuarter()}-${getCurrentYear()}`;
}

function getMonthTag(date = new Date()) {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}`;
}

function shiftMonth(offset) {
  let date = new Date();
  date.setMonth(date.getMonth() + offset);
  return getMonthTag(date);
}

function getCurrentMonthTag() {
  return getMonthTag();
}

function getPrevMonthTag() {
  return shiftMonth(-1);
}

function getNextMonthTag() {
  return shiftMonth(1);
}

function getWeekNumber(date) {
  const firstDay = new Date(date.getFullYear(), 0, 1);
  const dayOfYear = Math.floor((date - firstDay) / 86400000) + 1;
  return Math.ceil((dayOfYear + firstDay.getDay()) / 7);
}

function getWeekTag(date = new Date()) {
  return `${date.getFullYear()}-W${String(getWeekNumber(date)).padStart(2, '0')}`;
}

function shiftWeek(offset) {
  let date = new Date();
  date.setDate(date.getDate() + (offset * 7));
  return getWeekTag(date);
}

function getCurrentWeekTag() {
  return getWeekTag();
}

function getPrevWeekTag() {
  return shiftWeek(-1);
}

function getNextWeekTag() {
  return shiftWeek(1);
}

module.exports = {
  getCurrentYear,
  getPrevYear,
  getNextYear,
  getCurrentQuarter,
  getQuarterTag,
  getCurrentMonthTag,
  getPrevMonthTag,
  getNextMonthTag,
  getCurrentWeekTag,
  getPrevWeekTag,
  getNextWeekTag
};