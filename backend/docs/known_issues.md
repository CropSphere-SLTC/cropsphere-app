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

## 5. Band dataset understates real hill-country humidity

**Where:** `models/files/CropSphere_SL_Synthetic_Weekly.csv`, humidity_pct for
Nuwara Eliya

Surfaced by fixing item 2. With the correct aggregation in place, observed
humidity still fails every crop band at Nuwara Eliya:

| Source | Nuwara Eliya humidity |
|---|---|
| Band dataset (bands derived from this) | 73.6–89.1, mean **81.6** |
| M2 dataset | 78.9–94.9, mean 89.2 |
| **Observed (Open-Meteo, past 7 days)** | **93.0** |

Band ceilings are 82% for four crops, 85% for Cowpea, 88% for Carrot. An
observed 93.0% clears none of them, so `humidity_suitable` fails for all six
crops at Nuwara Eliya regardless of conditions.

Nuwara Eliya sits at ~1,910 m in a cloud-forest zone; ~93% mean relative
humidity is normal there, and carrots are grown in it commercially. The band
dataset's 81.6 mean does not describe that district. Note the M2 dataset is
much CLOSER to reality on humidity (89.2) even though it is the one that is
wrong on temperature (item 4) — the two synthetic sets are each wrong about
different variables.

Lowland districts are unaffected: Anuradhapura's observed 66.1 sits mid-band.

**Impact:** one of four conditions is permanently unavailable at Nuwara Eliya
and probably Badulla. Carrot there reads "Workable — 2 of 4" (temperature and
rainfall pass, humidity and soil pH fail) where it should plausibly read
higher.

**Fix direction:** NOT by changing the aggregation. Choosing
`relative_humidity_2m_min` would put Nuwara Eliya at 77.2% and make the flag
pass, but that is reverse-engineering the input to reach a desired answer, and
it would corrupt every other district. The honest options are to widen the
humidity band for high-elevation districts using real observations, or to
regenerate the synthetic dataset with correct hill-country humidity. Both are
band/data work, out of scope for a client-side aggregation fix.

---

## How they interact

- **1 and 2 were why the badges were wrong.** Both are now fixed, and the
  badges discriminate: Anuradhapura returns five lowland crops at "Good match
  — 3 of 4, watch rainfall" and Carrot at 2 of 4 failing temperature, which is
  correct for the dry zone. Fixing them is also what finally gave
  eaab9fa's `_observed_conditions` change something visible to do.
- **5 was surfaced by fixing 2**, the same way 3 was surfaced by the rainfall
  reseed. Correcting an input reveals whether the reference data it is
  compared against was ever right.
- **3 was created by fixing rainfall, not by the reseed being wrong.** It is
  the second half of a compensating pair.
- **4 is upstream of everything** and is the only one that cannot be fixed in
  this codebase.

Suggested order: ~~1 and 2~~ (done), then 5 (it is the only remaining defect
that changes what a farmer sees, and it affects one district), then 3, then 4
when retraining is possible.

## Reproducing

```bash
cd backend
python -m scripts.check_weather_trust      # item 4: the district gate
python -m scripts.derive_crop_bands        # the bands, re-validated
pytest tests/unit/services_test/test_weather_trust.py -v   # items 3, 4
pytest tests/unit/services_test/test_crop_suitability.py -v
```
