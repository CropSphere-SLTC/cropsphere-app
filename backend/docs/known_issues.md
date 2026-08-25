# Known issues — weather inputs and the agronomic suitability flags

Four open defects, all feeding the same surface: the four per-crop suitability
conditions on `/api/recommend` (temperature, rainfall, humidity, soil pH) and
the forecast on `/api/weather/forecast`.

They are listed together because they interact. Fixing any one in isolation
will not make the suitability badges correct, and two of them currently mask
each other.

Everything here is measured, not estimated. The commands to reproduce each
figure are given.

---

## 1. ~~Rainfall reaches the bands as a daily mean, not a weekly total~~ — RESOLVED

**Where:** `frontend/lib/utils/farm_context.dart`, `fetchFarmWeather`

```dart
rainfallMm: avg('precipitation_sum').clamp(0, 300),
```

`avg()` averages Open-Meteo's **daily** `precipitation_sum` over 8 days, so the
field carries mm/**day**. The agronomic bands are derived from
`crop_min_weekly_rain_mm` / `crop_max_weekly_rain_mm` and are weekly: training
`rainfall_mm` has mean 24.3, median 16.8, and a Nuwara Eliya mean of 46.3 mm/wk.

The value therefore arrives roughly 7x too small against band floors of
8–10 mm. `rain_suitable` passes 57.7% of the time in the training data and
close to never in production.

**Impact:** the rainfall condition fails for all six crops in almost any week.

**FIXED.** `fetchFarmWeather` now SUMS `precipitation_sum` over the window
instead of averaging it, and the window is `past_days=7&forecast_days=0` —
exactly 7 complete, observed days. The previous 8-day window mixed a forecast
day into a figure presented as observed and inflated a weekly total by ~14%.

The `.clamp(0, 300)` ceiling went to `500`, matching the backend's own bound
(`RecommendRequest.rainfall_mm` is `ge=0, le=500`). 300 was sized for the
daily-mean reading, where it was unreachable; as a weekly total it is
reachable in a monsoon week and would have clipped exactly the extremes a
farmer most needs advice about.

Measured after the fix: Nuwara Eliya 22.8 mm/wk, Anuradhapura 7.0 mm/wk. The
rainfall condition now discriminates — it passes for every crop at Nuwara
Eliya and fails for every crop at Anuradhapura's genuinely dry week, which is
the behaviour the bands describe.

---

## 2. ~~Humidity reaches the bands as a mean of daily maxima~~ — RESOLVED

**Where:** same file, same function

```dart
'&daily=precipitation_sum,temperature_2m_max,temperature_2m_min,'
'relative_humidity_2m_max'
...
humidityPct: avg('relative_humidity_2m_max').clamp(0, 100),
```

`relative_humidity_2m_max` is each day's **peak**, and the mean of daily peaks
is far above a representative value. Training `humidity_pct` runs 52.0–89.1
with a mean of 68.7, and `humidity_suitable` passes **99.6%** of the time. The
bands top out at 82–88.

Observed values of 98% (Open-Meteo) and 91.9% (M2) both exceed the training
data's own maximum, so a condition that essentially never fails in training
now always fails.

**Impact:** the humidity condition fails for all six crops, in the hill country
especially.

**FIXED.** `fetchFarmWeather` now requests `relative_humidity_2m_mean`, which
Open-Meteo exposes directly, instead of `relative_humidity_2m_max`.

Measured after the fix: Anuradhapura 66.1% against that district's band-dataset
range of 54.8–73.9 (mean 64.9) — consistent. The aggregation is now comparable
to what the bands were derived from.

**It does not make the humidity condition pass in the hill country**, and that
is not a shortcoming of this fix — see item 5.

---

## 3. Humidity seeds below the scaler floor for Hambantota and Jaffna

**Where:** `app/user/services/weather_service.py`, `_DISTRICT_CLIMATE`

| District | Seed humidity | Normalized |
|---|---|---|
| Hambantota | 60.0 | **-0.048** |
| Jaffna | 58.0 | **-0.108** |

The M2 scaler's humidity floor is 61.6. `MinMaxScaler` does not clip, so both
seeds normalize negative — the same class of fault as the temperature
excursion in item 4, milder.

This was masked until the rainfall seeds were corrected (f9fd10c). Those two
districts previously forecast accurately because an inflated rainfall seed was
cancelling this out-of-range humidity one; correcting the rainfall exposed it:

```
Hambantota   error 1.6mm -> 7.3mm
Jaffna       error 0.5mm -> 8.1mm
```

**Impact:** rainfall under-predicted by ~7–8mm for two districts. Not severe
enough to warrant the low-confidence label — these districts' *training data*
is correct, unlike item 4 — but it is a real regression with a known cause.

**Fix direction:** reseed humidity from the training data the way rainfall was,
and re-measure. Do not clamp; see item 4 for why.

Reported at boot by `assert_weather_seeds_in_range()`.

---

## 4. Wrong hill-country temperatures in M2's training data (root cause)

**Where:** `models/files/Cropsphere_Real_Test_Dataset.csv`

M2's scaler was fit on this file — confirmed by its per-feature ranges matching
it to the decimal on all six features. The agronomic bands come from
`CropSphere_SL_Synthetic_Weekly.csv`. Both are weekly and they **agree on
rainfall**. They disagree on temperature:

| District | M2 training mean weekly max | Band dataset | Delta |
|---|---|---|---|
| Nuwara Eliya | 34.0 C | 18.9 C | **15.1** |
| Badulla | 31.6 C | 26.0 C | **5.6** |
| Monaragala | 34.1 C | 33.0 C | 1.1 |
| all others | — | — | <0.5 |

Nuwara Eliya sits at roughly 1,900 m. A 34 C mean weekly maximum is dry-zone
weather attached to the wrong district.

**The consequence is not a slightly-off forecast.** `_DISTRICT_CLIMATE` seeds
Nuwara Eliya with a *correct* 22 C maximum, which falls below the scaler's
27.81 C floor, normalizes to -0.441, and collapses the LSTM. Holding the
rainfall seed constant and sweeping temp_max alone moves predicted rainfall
from **1.58 to 68.28** — a 43x swing driven entirely by a variable that is not
rainfall.

So the seed is right and the training data is wrong. **No seed value fixes
this**: raising it into range would mean asserting that the hill country is
hot, and would launder a known-bad number into a confident-looking forecast.

**Impact:** Nuwara Eliya and Badulla forecasts are unusable. Both are labelled
`forecast_source: model_low_confidence` and the Weather page shows a caveat.

**Fix direction:** retrain M2 on corrected hill-country data. Nothing short of
that resolves it. Until then the labelling is the mitigation.

Gate derived by `python -m scripts.check_weather_trust`, which fails if
`_UNTRUSTED_FORECAST_DISTRICTS` goes stale.

---

## 5. The humidity condition is miscalibrated against real weather

**Where:** `models/files/CropSphere_SL_Synthetic_Weekly.csv`, `humidity_pct`,
and the humidity ceilings derived from it

Surfaced by fixing item 2. With the correct aggregation in place, the humidity
condition still fails far more often than the bands imply — and the cause is
**not** what it first looked like.

### It is not an upcountry problem

An earlier version of this item said the band dataset understated hill-country
humidity. That was wrong. Comparing the dataset's per-district means against
two years of observed weekly climatology, aggregated exactly as the dataset
defines each column:

| Column | Nuwara Eliya | Badulla | Largest error | Smallest error |
|---|---|---|---|---|
| rainfall_mm | **+1.2** | +9.5 | Ampara +16.4 | **Nuwara Eliya** |
| humidity_pct | +6.7 | **+3.7** | Hambantota +16.4 | **Badulla** |
| temp_max_c | **+0.9** | +2.3 | Jaffna −4.4 | **Nuwara Eliya** |
| temp_min_c | +1.6 | +3.7 | Badulla +3.7 | Hambantota +1.0 |

(positive = dataset is BELOW observed)

**Nuwara Eliya is among the best-matched districts in the whole dataset** —
best on rainfall, best on temp_max, mid-table on humidity. Badulla is the best
match on humidity. The largest errors are all **lowland**: Hambantota and
Anuradhapura understate humidity by 15–16 points, Ampara and Batticaloa
understate rainfall by ~16mm, Jaffna overstates temp_max by 4.4 C.

The dataset understates humidity for **all eight** districts, by +3.7 to
+16.4. It is one consistent bias, not a hill-country hole.

### What actually fails, and why

Humidity has almost no margin anywhere. The visible upcountry failure is
absolute humidity crossing a tight ceiling first — not a bad row.

| District | Observed mean | Headroom to the 82% ceiling | Weeks over 82% |
|---|---|---|---|
| Jaffna | 78.8% | +3.2 | 21% |
| Hambantota | 78.2% | +3.8 | 24% |
| Monaragala | 78.5% | +3.5 | 40% |
| Anuradhapura | 80.3% | +1.7 | 42% |
| Ampara | 79.3% | +2.7 | 43% |
| Badulla | 79.7% | +2.3 | 46% |
| Batticaloa | 80.5% | +1.5 | **48%** |
| **Nuwara Eliya** | **88.3%** | **−6.3** | **80%** |

Four of the six crops use an 82% ceiling; Cowpea 85%, Carrot 88%.

Lowland districts sit 1.5–4 points below the ceiling and already breach it in
21–48% of real weeks. Nuwara Eliya is simply the district that crosses first
and stays across. The bands were calibrated against data where
`humidity_suitable` passes **99.6%** of the time; against observed weather it
passes 70% in the lowlands and 39% upcountry.

**This is a system-wide calibration problem.** Treating it as an upcountry
issue would patch two districts and leave Batticaloa failing the same check in
half of all real weeks.

### What is working

The temperature condition at Nuwara Eliya is correct, not broken. Per-crop
pass rate across observed weeks:

```
Carrot          99%
Cowpea           0%
Finger millet    0%
Green gram       0%
Groundnut        0%
Maize            0%
```

Carrot and only Carrot, in essentially every week. That is the system
identifying prime carrot country.

### Impact

The humidity flag is unreliable everywhere, most visibly upcountry. At Nuwara
Eliya it fails for all six crops in most weeks, so Carrot reads "Workable —
2 of 4" (temperature and rainfall pass, humidity and soil pH fail) where it
should plausibly read higher.

### CAVEAT ON THIS EVIDENCE

All observed figures above are **two years (2023–24) of Open-Meteo reanalysis
sampled at a single point per district**, compared against a synthetic
dataset. The offsets are large and consistent enough that point-sampling is
unlikely to explain them, but this has **not** been validated against Sri
Lanka Department of Meteorology station data. That is the authoritative check,
and it should happen before anyone rebuilds band values from these numbers.
A single grid point is not a district, and reanalysis is not a gauge.

### Decision: option A (disclosure only), as a HOLDING POSITION

**No band value changed.** The Crop Recommendation results carry a
plain-language note whenever any crop fails the humidity condition, telling
the farmer the check is stricter than real growing conditions and to weigh
temperature, rainfall and soil more heavily.
See `_humidityCaveat` in `frontend/lib/screens/recommend/recommend_screen.dart`.

This changes no behaviour: the badge still counts humidity as a failure in its
tier calculation, so Carrot at Nuwara Eliya still reads "Workable — 2 of 4".
The disclosure asks the farmer to mentally correct for a number we know is
wrong rather than correcting it ourselves. That is weaker than fixing the
calibration and is chosen only because the fixes are blocked (below).

**Option B — shift the humidity band +11 points, both ends — is the
best-evidenced fix.** +11 is the mean understatement across the eight
districts, and the offset is consistent rather than noisy, which is exactly
the shape a constant correction assumes. Pass rates would move to 93% lowland
/ 82% upcountry. It raises floors as well as ceilings, so genuinely dry weeks
would start failing — the honest consequence of treating this as an offset.

**Option C — rebuild the humidity bands from observed weather in the districts
where `M5_valid_pairs` says each crop is actually grown — is the principled
fix.** It corrects the source rather than patching the output, on the premise
that a crop grown in a district is by revealed preference tolerant of that
district's real humidity.

**Both are blocked on Department of Meteorology validation.** Every observed
figure in this item is Open-Meteo reanalysis at a single grid point per
district over two years. B bakes an offset derived from it into the bands;
C bakes the distribution itself in. Neither should proceed on reanalysis
alone.

**Option B2 (raise ceilings only) was rejected.** It takes the lowland pass
rate to 100%, so the condition stops discriminating there entirely —
replacing a flag that never passed with one that never fails, which is no
better.

**Option D (drop humidity, badge becomes N of 3)** remains the fallback if DoM
data never materialises. It loses real signal — humidity drives fungal disease
pressure — but it is the only option with no risk of asserting a calibration
we cannot back.

Not by changing the aggregation, in any case.
`relative_humidity_2m_min` would put Nuwara Eliya at 77.2% and make the flag
pass, but that is reverse-engineering the input to reach a desired answer and
would corrupt every other district.

### Translations need a native-speaker pass

The caveat's Sinhala and Tamil strings were written by the implementer, not a
native speaker. They are faithful to the English and reuse terms already in
the file (`ආර්ද්‍රතාවය`, `ஈரப்பதம்`, `වර්ෂාපතනය`, `மழைவீழ்ச்சி` all appear in
`_failedConditions`), but they should be reviewed before release.

Register matters more here than in an ordinary field label: this sentence asks
a farmer to **discount a failure the app itself just reported**. Too tentative
and it reads as the app not trusting its own advice; too strong and it reads
as permission to ignore humidity altogether, which is not what the evidence
supports. That balance is hard to verify in a language you do not speak.

---

## How they interact

- **1 and 2 were why the badges were wrong.** Both are now fixed, and the
  badges discriminate: Anuradhapura returns five lowland crops at "Good match
  — 3 of 4, watch rainfall" and Carrot at 2 of 4 failing temperature, which is
  correct for the dry zone. Fixing them is also what finally gave
  eaab9fa's `_observed_conditions` change something visible to do.
- **5 was surfaced by fixing 2**, the same way 3 was surfaced by the rainfall
  reseed. Correcting an input reveals whether the reference data it is
  compared against was ever right. In both cases the newly-visible defect was
  larger in scope than the one that exposed it.
- **4 and 5 do NOT share a root cause**, despite both showing up upcountry.
  4 is a localised error in one dataset (one district, one column, 14 C wrong,
  unambiguous). 5 is a consistent bias across every district in a DIFFERENT
  dataset. They look related only because Nuwara Eliya is where both become
  visible first — 4 because its temperature is genuinely wrong there, 5
  because its humidity is genuinely highest there.
- **3 was created by fixing rainfall, not by the reseed being wrong.** It is
  the second half of a compensating pair.
- **4 is upstream of everything** and is the only one that cannot be fixed in
  this codebase.

Suggested order: ~~1 and 2~~ (done), then 5 — but note it is no longer a
one-district fix: it changes the humidity flag for all eight districts and all
six crops, and it needs Department of Meteorology validation before any band
value moves. Then 3, then 4 when retraining is possible.

## Reproducing

```bash
cd backend
python -m scripts.check_weather_trust      # item 4: the district gate
python -m scripts.derive_crop_bands        # the bands, re-validated
pytest tests/unit/services_test/test_weather_trust.py -v   # items 3, 4
pytest tests/unit/services_test/test_crop_suitability.py -v
```
