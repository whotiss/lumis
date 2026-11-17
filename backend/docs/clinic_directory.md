# Clinic directory (FR6)

Lumis tells people to see a doctor, ideally a dermatologist. The clinic directory answers "where?": a list of
places in the Klang Valley where a dermatologist practises, sorted by distance when the person allows location.

- Data: `app/data/clinics.json` (version and check date inside the file)
- Code: `app/clinics.py` (loading, checks, distance), `app/routers/clinics.py` (endpoints)
- Tests: `tests/test_clinics.py`

## What is listed, and why

**Rule:** a place is listed when at least one dermatologist in the Persatuan Dermatologi Malaysia (PDM) Directory of
Dermatologists names it as where they practise. Each entry links to those directory pages
(`dermatologist_source`), so every listing can be traced back to a named specialist.

**Why this rule:** Lumis's advice is to see a dermatologist, so the list must lead to one. Search engines and
clinic aggregators return many "skin clinics" that are aesthetic clinics run by doctors who are not
dermatologists. These were checked for the Sunway, Subang, USJ and Puchong area and left out on purpose.

**Coverage:** Kuala Lumpur, Putrajaya and the Selangor districts around them. Every PDM profile listed under these
three states was read on 2026-11-17 (108 profiles). 106 of them lead to a listed place; the other places they
name are in `excluded` in the data file, each with its reason (outside the Klang Valley, an academic office, or a
clinic that no current source could confirm).

| Kind of place | Count | Note for the person (`access`) |
|---|---|---|
| Government hospital (Ministry of Health) | 8 | Usually needs a referral letter from a klinik kesihatan or GP |
| University hospital | 6 | Usually needs a referral letter; the hospital's private specialist centre may take appointments |
| Private hospital | 36 | Call to book with a dermatologist |
| Dermatologist's own clinic | 23 | Call to book |
| **Total** | **73** | |

Hospital Tunku Azizah is marked `children_only` (paediatric dermatology).

### Sunway and Subang in more detail

Within about 8 km of Sunway University (straight line):

| km | Place | Kind |
|---|---|---|
| 0.6 | Sunway Medical Centre | private hospital (5 dermatologists listed) |
| 1.7 | Subang Jaya Medical Centre | private hospital (5) |
| 2.2 | Klinik Pakar Kulit Ranjit, SS15 | dermatologist's clinic |
| 4.7 | Chua Skin Specialist, Bandar Puteri Puchong | dermatologist's clinic |
| 5.2 | Columbia Asia Hospital Puchong | private hospital |
| 5.5 | Assunta Hospital | private hospital |
| 5.5 | Klinik Pakar Kulit Chang, SEA Park | dermatologist's clinic |
| 5.8 | MSU Medical Centre | private hospital |
| 6.8 | Ara Damansara Medical Centre | private hospital |
| 6.8 | Columbia Asia Hospital Petaling Jaya | private hospital |
| 7.0 | KPJ Selangor Specialist Hospital | private hospital |
| 7.5 | University Malaya Medical Centre and UM Specialist Centre | university hospital |
| 7.8 | AY Skin and Koh & Wong (Damansara Utama) | dermatologists' clinics |

There is no government dermatology service in Sunway or Subang itself. The nearest public options are UMMC
(university hospital, 7.5 km) and HCTM UKM (14 km); the nearest Ministry of Health hospitals with dermatology are
Hospital Kuala Lumpur (16 km) and Hospital Serdang (16 km). All of them usually need a referral letter, so for
someone in Sunway the realistic first step is often a GP or klinik kesihatan.

## Map positions

Positions come from OpenStreetMap (looked up with Nominatim, 2026-11-17). Each entry records how exact its pin is:

| `location_precision` | Meaning | Count |
|---|---|---|
| building | The hospital or clinic building itself | 58 |
| street | The street the clinic is on (the building is not on the map) | 10 |
| area | The neighbourhood or shopping complex | 4 |
| none | Could not be placed; listed, but not in distance sorting | 1 (Klinik Pakar Kulit P.G. Low, Cheras) |

Wherever positions are shown, the app must show "Map data © OpenStreetMap contributors" (ODbL licence); the API
returns this text as `attribution`.

## Privacy

`POST /clinics/nearby` takes the location in the request body, uses it to sort the list and forgets it. It is not
stored, not logged, and not echoed back. It is a POST, not a GET with `?lat=&lon=`, because Cloud Run's request log
records each request's address, including the query string, but not its body. A test checks the logs, the response
and the database for the coordinates. This is what the consent text promises: "it is used only to sort clinics
by distance, and it is not stored."

Distances are straight-line, not driving distances; the app should say so.

## Limits (for the report)

- The directory is a snapshot. Dermatologists move, and the PDM directory itself may lag behind. Each entry has
  sources and the file has a check date, so it can be re-checked.
- Being a PDM member is how a dermatologist was found, not a quality rating. Lumis does not rank or recommend
  any place; it only sorts by distance.
- Opening hours, fees and waiting times are not included: they change often and would go out of date.
- Coverage is the Klang Valley only. Elsewhere the API says `outside_coverage: true`, and the app should
  point to the PDM directory for other states.

## Updating it

1. Edit `app/data/clinics.json` (add, change or remove an entry; change `version` and `checked`).
2. Run `python -m pytest -q tests/test_clinics.py`. The checks refuse an entry without a dermatologist source, an
   unknown kind of place, a pin outside the Klang Valley or a pin without its precision and source. The server
   refuses to start with a file that fails them.
3. Commit, then deploy as usual (deploy/README.md, steps 1, 7 and 8).
