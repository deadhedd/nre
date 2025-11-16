To-Do List

## Current focuses
* sleep data pipeline
* cascading tasks to implement awkward tasks

### 💤 Sleep Data Pipeline TODO

* **Shortcuts**

  * [ ] Create new *Sleep Data Backfill* shortcut to fetch fresh data.
  * [x] Update and test *Daily Sleep Data Upload* shortcut.
  * [x] Schedule both shortcuts to run automatically.
  * [ ] update sleep data upload for 2 days instead of one
  * [ ] update sleep data upload to include today and yesterday's wake up time via data jar

* **Scripts**

  * [ ] Run `backfill-into-raws.js` to generate daily raw files.
  * [ ] Run `raws-into-summaries.js` to produce summaries.
  * [ ] Verify the *daily processor* script runs correctly and is scheduled.
  * [ ] update daily processor to trim raw file using the today and yesterday wake time

* **Integration**

  * [ ] Add analyzed sleep data to the daily note template.
  * [ ] Confirm summaries appear correctly in Obsidian.


High Priority

    • Sleep Data Automation

    • Workout Data Automation

    • Workout schedule implemented in daily notes

    • Add recycling and filling water jug to daily notes which are a little complicated due to the interval to repeat. consider utilizing the cascading tasks system

    • set up grocery list automation

    - set up windows vault to pull on boot, and push on off, and auto push late at night in case of forgetting off
Medium Priority

    • fix moon phase illumination bug

    • add newline after day headline so it doesnt mess with pagan timings

    • improve yardwork sutiability analysis to include precipitation and ideal time for work

    • implement automated budget analysis

    - add leave for work checklist to daily notes
Low Priority / Someday

    • use advanced uri for enhanced ios shortcuts

    - Explore using AGENTS.md as a unified config for all cron jobs—design parser integration and alias workflow for easy editing and syncing.

Notes

    • Year theme: Standing on Business (2025)

    • Maintain automation server (daemon), laptop (ghost), and PC (phantom) coordination.

    • Next automation candidates: workout schedule injection script + sleep/workout data pipelines.
