# Wales 20mph DiD project — design notes

**Identification strategy (current):** Within-Wales comparison of 30mph roads reduced to 20mph in Sept 2023 (treatment) vs. 30mph roads designated as exceptions and kept at 30mph (control). Documented, along with outcome variables and data-download code, in `WalesSpeedLimit.qmd` in the user's local `C:\RCode\Claude_Test` project folder.

## Outcome variables selected
- **Primary:** STATS19 collisions/casualties (total, by severity/KSI, by road-user type).
- **Mechanism:** vehicle speed, from Transport for Wales' national monitoring sites (~40 fixed sites) — site-level data not yet obtained, may need a data/FOI request.
- **Robustness/placebo:** DfT AADF traffic volume, to check for displacement onto control roads.
- **Ruled out for this road-level design** (too sparse geographically): air quality, active travel counts, bus punctuality, hospital admissions.

## Key data sources
- STATS19: `stats19` R package (rOpenSci/CRAN); Wales-specific files also at gov.wales/road-collision-open-data.
- DfT traffic counts (AADF/raw counts): https://storage.googleapis.com/dft-statistics/road-traffic/downloads/data-gov-uk/

## Treatment/control road classification
**DataMapWales GIS route: dead end.** The intended primary source (a DataMapWales layer meant to consolidate all highway authorities' 20mph/30mph-exception status) turned out to be broken — the map reports no layers, its stored layer names don't exist in the live WFS catalog, and a similarly-named real layer (`geonode:_30mph_roads_in_wales`) is just an attribute-less boundary/mask polygon layer. Not yet tried: finding this dataset's standalone GeoNode layer page (vs. the broken map page), or emailing `data@gov.wales`.

**Current approach: compiled from local authority sources.** A subagent worked through each Welsh council's published exception/reverted-road lists (council pages, local press). Result: `data/wales_30mph_exceptions.csv` in the qmd's folder, 414 rows across 16 of 22 authorities (Newport 85, Caerphilly 61, Wrexham 48, Vale of Glamorgan 39, Torfaen 36, Powys 28, RCT 26, Anglesey 24, Conwy 19, Swansea 17, Flintshire 14, Merthyr Tydfil 4, Cardiff 4, Bridgend 3, Ceredigion 3, Gwynedd 3). Zero-row authorities: Denbighshire/Neath Port Talbot/Monmouthshire/Blaenau Gwent confirmed no (or no named) changes (a real finding); Pembrokeshire/Carmarthenshire lists exist but weren't extractable (Pembrokeshire only on the broken map or in person; Carmarthenshire's PDF gave a 403).

Each row has `status`: `original_exception`, `reverted_after_review`, `proposed_not_confirmed` (exclude from core analysis — not yet real), `unclear`.

**Known gaps to close before finalising the estimation sample:**
- Cardiff and Swansea's *original* day-one exception lists were never published as text (map-only) — only their much smaller 2025 proposed-reversion lists are captured. These are two of the highest-power authorities, so this matters.
- Gwynedd has ~85 original exceptions, individually unnamed in any source found — only 3 later-review roads captured.
- Several entries (Vale of Glamorgan, Newport, Caerphilly, Wrexham, Cardiff, Carmarthenshire) were AI-extracted from PDFs, not verbatim — spot-check road descriptions against `source_url` before using for precise geocoding.

Rejected approach: inferring treated roads from STATS19 by checking which roads have accidents both before and after the policy with `speed_limit` switching 30→20 — conditions the sample on the outcome (excludes roads where the policy fully eliminated post-period accidents; skews toward busier roads). Retained only as a validation cross-check.

## Note on file sync
On 2026-09-10 an in-progress qmd edit was overwritten because the user had the file open in RStudio from before the edit and saved over it (their editor's stale buffer, plus two ad-hoc test chunks they'd pasted in, clobbered the disk version). Fixed by re-reading the file fresh and rewriting in full. Worth closing the file's tab in RStudio without saving and reopening it after Claude edits it externally, to avoid this recurring.
