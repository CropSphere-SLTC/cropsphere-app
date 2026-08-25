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

## 1. Rainfall reaches the bands as a daily mean, not a weekly total

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

**Fix direction:** sum rather than average, or multiply the mean by 7 — but
confirm which the bands actually want first, and note that Open-Meteo's
`past_days=7&forecast_days=1` window is 8 days, not 7.

---

## 2. Humidity reaches the bands as a mean of daily maxima

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

**Fix direction:** request `relative_humidity_2m_mean` instead of `_max`.

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

## How they interact

- **1 and 2 are why the badges are wrong today.** Both conditions fail for
  every crop regardless of which weather source is used, which is why
  eaab9fa's fix to `_observed_conditions` — real, and it removed a
  display-vs-evaluation mismatch — changed nothing a farmer sees.
- **3 was created by fixing rainfall, not by the reseed being wrong.** It is
  the second half of a compensating pair.
- **4 is upstream of everything** and is the only one that cannot be fixed in
  this codebase.

Suggested order: 1 and 2 together (they are the same function and the only
ones that change what farmers see), then 3, then 4 when retraining is
possible.

## Reproducing

```bash
cd backend
python -m scripts.check_weather_trust      # item 4: the district gate
python -m scripts.derive_crop_bands        # the bands, re-validated
pytest tests/unit/services_test/test_weather_trust.py -v   # items 3, 4
pytest tests/unit/services_test/test_crop_suitability.py -v
```
