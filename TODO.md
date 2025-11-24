To-Do List

## Current focuses
* sleep data pipeline
* daily note embed refactor

### 💤 Sleep Data Pipeline TODO

* **Shortcuts**

  * [ ] Create new *Sleep Data Backfill* shortcut to fetch fresh data.
  * [x] Update and test *Daily Sleep Data Upload* shortcut.
  * [x] Schedule both shortcuts to run automatically.
  * [x] Update sleep data upload for 2 days instead of one.
  * [x] Update sleep data upload to include today and yesterday's wake time via Data Jar.
  * [x] Verify functionality of shortcut changes.
  * [x] Repeat run safeguard is failing to allow the shortcut to run when conditions allow.
  * [ ] edit upload shortcut to trigger sleep processor script using the run script over ssh action

* **Scripts**

  * [ ] Run `backfill-into-raws.js` to generate daily raw files.
  * [ ] Run `raws-into-summaries.js` to produce summaries.
  * [ ] Verify the *daily processor* script runs correctly and is scheduled.
  * [x] Update daily processor to trim raw file using today and yesterday wake time.

* **Integration**

  * [ ] Add analyzed sleep data to the daily note template by using obsidian's embed feature.
  * [x] Confirm summaries appear correctly in Obsidian.

### ✅ **TODO — F1 Daily Snapshot System**

1. **Update Daily Note Template**
   Add the embed line for current data:

   ```
   ![[F1/Rolling#main]]
   ```

2. **Define Rolling.md Structure**
   Create `F1/Rolling.md` with a stable `## main` block that your update script rewrites daily.

3. **Write Snapshot Script**
   A cron-triggered script that:

   * Finds yesterday’s daily note
   * Replaces the embed line with the raw text from `F1/Rolling.md`
   * Saves & commits the result

4. **Schedule Cron Job**
   Run snapshot script before the next F1 update (e.g., 23:59 or early morning before your update pipeline).

5. **Integrate Into Automation Pipeline**
   Ensure:

   * Morning pipeline updates Rolling.md
   * Evening pipeline runs the snapshot script
   * Daily notes remain clean with the embed replaced once per day

High Priority

    * refactor daily note to utilize obsidian's embed feature wherever possible
    
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

    * replace day plan util script with obsidian embed
Low Priority / Someday

    • use advanced uri for enhanced ios shortcuts

    - Explore using AGENTS.md as a unified config for all cron jobs—design parser integration and alias workflow for easy editing and syncing.

Notes

    • Year theme: Standing on Business (2025)

    • Maintain automation server (daemon), laptop (ghost), and PC (phantom) coordination.

    • Next automation candidates: workout schedule injection script + sleep/workout data pipelines.
