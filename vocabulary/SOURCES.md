# EMS vocabulary sources

The compact prompt in `ems_prompt.txt` was curated for local EMS dictation on
2026-08-04 using terminology represented in these current reference sources:

- National Library of Medicine, 2026 Medical Subject Headings (MeSH):
  https://www.nlm.nih.gov/databases/download/mesh.html
- National Emergency Medical Services Information System (NEMSIS), version
  3.5.1 data dictionary and defined EMS lists:
  https://nemsis.org/technical-resources/version-3/version-3-data-dictionaries/
  https://nemsis.org/technical-resources/version-3/version-3-resources/

NLM freely provides MeSH data under its terms and requires attribution without
implying NLM endorsement:
https://www.nlm.nih.gov/databases/download/terms_and_conditions_mesh.html

This project is not endorsed by NLM, NHTSA, or NEMSIS. The bundled prompt is a
small project-authored selection, not a redistribution of either full dataset,
and may not reflect later terminology revisions. Harborview and Medic One terms
were added for this project's local EMS context. Patient names, other
agency-specific terms, and machine-specific configuration belong only in the
local `~/.local-whisper/prompt` file and must not be committed.
