# tools

- `gen_locales.py` + `translations.py` – build `Locales.lua`: `python3 tools/gen_locales.py .`
- `test_sim.py` – loads the data, log, lookup and sharing code in Lua 5.1 with stubbed game APIs: `python3 tools/test_sim.py .`
- `parse_v.py` → `build_data.py` – rebuild `Data.lua` from the vmangos `world_full_14_june_2021.sql` dump plus QuestieDB/Questie zone files (paths are relative to the working directory; see the scripts).
