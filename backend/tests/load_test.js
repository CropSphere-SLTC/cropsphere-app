/**
 * CropSphere — k6 Load Test
 * ==========================
 * Sprint 1 | Performance Testing
 *
 * Tests all 6 API endpoints under realistic load:
 * 15 virtual users, 3-phase profile (ramp-up → sustained → ramp-down)
 * Total duration: ~7 minutes
 *
 * Prerequisites:
 *   1. Install k6:          brew install k6
 *   2. Backend running:     docker-compose up (check http://localhost:8000/api/health)
 *   3. Get JWT token:       Open Flutter web app → Chrome DevTools →
 *                           Network tab → any /api/ request → copy Authorization header value
 *   4. Set token:           export K6_TOKEN="Bearer eyJ..."
 *
 * Run:
 *   k6 run --env TOKEN=$K6_TOKEN load_test.js
 *
 * Save report:
 *   k6 run --env TOKEN=$K6_TOKEN load_test.js 2>&1 | tee load_test_report.txt
 *
 * Pass/fail:
 *   Green ✓ = all thresholds met → system handles 15 concurrent users
 *   Red ✗   = threshold breached → note which endpoint and response time
 */

import http from "k6/http";
import { check, sleep, group } from "k6";
import { Rate, Trend } from "k6/metrics";

// ─────────────────────────────────────────────
// Configuration
// ─────────────────────────────────────────────

const BASE_URL = __ENV.BASE_URL || "http://localhost:8000";
const TOKEN    = __ENV.TOKEN    || "Bearer eyJhbGciOiJSUzI1NiIsImtpZCI6Ijg2OGU0YWNlMGI2NTE2ZDM2YjlmNTZkZThjZTQ5Nzg4ZmNjZGFjNDMiLCJ0eXAiOiJKV1QifQ.eyJuYW1lIjoiZnlwIHRlc3QiLCJwaWN0dXJlIjoiaHR0cHM6Ly9saDMuZ29vZ2xldXNlcmNvbnRlbnQuY29tL2EvQUNnOG9jS2p3UTdnNWNXOHhzQmhqS2V1dG1HTHFfZzRuVVJJYjdKZ2k3V3M1VmktdmtFbDl3PXM5Ni1jIiwiaXNzIjoiaHR0cHM6Ly9zZWN1cmV0b2tlbi5nb29nbGUuY29tL2Nyb3BzcGhlcmUtMmU4N2MiLCJhdWQiOiJjcm9wc3BoZXJlLTJlODdjIiwiYXV0aF90aW1lIjoxNzc4MzI3NTYyLCJ1c2VyX2lkIjoib0RueExOU3FDNmJwempZVjE3dWlWUzhoYUttMiIsInN1YiI6Im9EbnhMTlNxQzZicHpqWVYxN3VpVlM4aGFLbTIiLCJpYXQiOjE3Nzg2NjIyNTYsImV4cCI6MTc3ODY2NTg1NiwiZW1haWwiOiJmeXB0ZXN0MjVAZ21haWwuY29tIiwiZW1haWxfdmVyaWZpZWQiOnRydWUsImZpcmViYXNlIjp7ImlkZW50aXRpZXMiOnsiZ29vZ2xlLmNvbSI6WyIxMDg0MTU1NDQxNTM5ODY3MTU3MzIiXSwiZW1haWwiOlsiZnlwdGVzdDI1QGdtYWlsLmNvbSJdfSwic2lnbl9pbl9wcm92aWRlciI6Imdvb2dsZS5jb20ifX0.AF_aQZN34C4ny9rg64ITmI3Mw6VYubQy0BeWonrvGwNZxKlVFkEu4GtK1DovW1AE0WaiFOpDrc_00v5WmSCc0QsJqWJISOYPLk5rJ73gtxT4ZZDR2YbMTSpcGcYUVRGGcDn-73Kb8zxQ09knS1vBR37AR6A3QtQt_qtjggCTm1c6WYGyT422Cnc1K7xthj9ep72yxSJLloIAkR8b9-30aD5WD98HflpvPG3acqDHBPqo0w_hsJ2bGxcLycJCwFOW5LvtpnPwFPNOebdhi1kG_ifxEM2ADOQzawHGF3JsJvB-IF2QAH2jkXVoHn_KrTcC6JV6QoOdSqySVIwAR44V5g";

// ─────────────────────────────────────────────
// Custom metrics — one trend per endpoint
// ─────────────────────────────────────────────

const yieldTrend     = new Trend("yield_duration",     true);
const weatherTrend   = new Trend("weather_duration",   true);
const priceTrend     = new Trend("price_duration",     true);
const demandTrend    = new Trend("demand_duration",    true);
const recommendTrend = new Trend("recommend_duration", true);
const chatTrend      = new Trend("chat_duration",      true);
const errorRate      = new Rate("error_rate");

// ─────────────────────────────────────────────
// Test profile — 3 phases
// ─────────────────────────────────────────────

export const options = {
  stages: [
    { duration: "2m", target: 15 },  // Phase 1: ramp up 0 → 15 users
    { duration: "3m", target: 15 },  // Phase 2: hold 15 users steady
    { duration: "2m", target: 0  },  // Phase 3: ramp down 15 → 0
  ],

  thresholds: {
    // Overall error rate must stay below 1%
    "http_req_failed":     ["rate<0.01"],
    "error_rate":          ["rate<0.01"],

    // Per-endpoint p95 response time thresholds
    // M1 Random Forest — fast single model
    "yield_duration":      ["p(95)<2000"],
    // M2 LSTM — medium, sequence model
    "weather_duration":    ["p(95)<3000"],
    // M3 LSTM per crop — medium
    "price_duration":      ["p(95)<3000"],
    // M4 XGBoost — fast tabular model
    "demand_duration":     ["p(95)<2000"],
    // M2→M1→M3→M5 chain — heaviest endpoint
    "recommend_duration":  ["p(95)<5000"],
    // M6 LLaMA via Groq — external API call
    "chat_duration":       ["p(95)<8000"],

    // Overall p95 across all requests
    "http_req_duration":   ["p(95)<8000"],
  },
};

// ─────────────────────────────────────────────
// Shared headers
// ─────────────────────────────────────────────

const headers = {
  "Content-Type":  "application/json",
  "Authorization": TOKEN,
};

// ─────────────────────────────────────────────
// Request payloads
// Valid inputs from the API contract — same shape the Flutter app sends
// ─────────────────────────────────────────────

const YIELD_PAYLOAD = JSON.stringify({
  crop:              "Carrot",
  district:          "Nuwara Eliya",
  season:            "Maha",
  week_of_year:      10,
  rainfall_mm:       45.0,
  temp_min_c:        12.0,
  temp_max_c:        22.0,
  humidity_pct:      78.0,
  wind_speed_kmh:    10.0,
  solar_radiation_mj:16.0,
  soil_ph:           6.2,
  soil_moisture_pct: 55.0,
  cultivated_area_ha:250.0,
  seed_variety:      "Nantes",
  fertilizer_index:  0.75,
  pesticide_index:   0.65,
  irrigation_type:   "rainfed",
  N_index:           0.6,
  P_index:           0.5,
  K_index:           0.7,
  prev_crop:         "Green gram",
  demand_index:      85.0,
  inflation_index:   1.2,
  holiday_flag:      0,
  festival_flag:     0,
});

const WEATHER_PAYLOAD = JSON.stringify({
  district:    "Nuwara Eliya",
  start_date:  "2025-03-01",
  weeks_ahead: 2,
});

const PRICE_PAYLOAD = JSON.stringify({
  crop:                   "Carrot",
  district:               "Nuwara Eliya",
  season:                 "Maha",
  week_of_year:           10,
  inflation_index:        1.2,
  fuel_price_index:       1.1,
  transport_cost_index:   1.3,
  supply_index:           70.0,
  demand_index:           85.0,
  holiday_flag:           0,
  festival_flag:          0,
  farmgate_price_lag1:    54.0,
  farmgate_price_lag2:    52.0,
  farmgate_price_lag4:    50.0,
});

const DEMAND_PAYLOAD = JSON.stringify({
  crop:                 "Carrot",
  season:               "Maha",
  week_of_year:         10,
  demand_lag1:          85.0,
  demand_lag2:          83.0,
  demand_lag4:          80.0,
  retail_price_lkr_kg:  83.0,
  inflation_index:      1.2,
  holiday_flag:         0,
  festival_flag:        0,
  consumer_pref_index:  72.0,
  search_trend_index:   68.0,
});

const RECOMMEND_PAYLOAD = JSON.stringify({
  district:          "Nuwara Eliya",
  season:            "Maha",
  week_of_year:      10,
  rainfall_mm:       45.0,
  temp_min_c:        12.0,
  temp_max_c:        22.0,
  humidity_pct:      78.0,
  soil_ph:           6.2,
  soil_moisture_pct: 55.0,
  N_index:           0.6,
  P_index:           0.5,
  K_index:           0.7,
  irrigation_type:   "rainfed",
});

const CHAT_PAYLOAD = JSON.stringify({
  message:              "What is the best crop to plant in Nuwara Eliya this Maha season?",
  conversation_history: [],
  user_id:              "load_test_user",
  district:             "Nuwara Eliya",
});

// ─────────────────────────────────────────────
// Helper — make a POST request and record metrics
// ─────────────────────────────────────────────

function post(endpoint, payload, trend, checkName, maxMs) {
  const res = http.post(`${BASE_URL}${endpoint}`, payload, { headers });

  // Record to custom trend
  trend.add(res.timings.duration);

  // Check response
  const ok = check(res, {
    [`${checkName} status 200`]:     (r) => r.status === 200,
    [`${checkName} not 500`]:        (r) => r.status !== 500,
    [`${checkName} under ${maxMs}ms`]: (r) => r.timings.duration < maxMs,
  });

  // Track errors
  errorRate.add(!ok);

  // Log failures for debugging (only shown with k6 --verbose)
  if (res.status !== 200) {
    console.warn(
      `[VU ${__VU}] ${endpoint} → ${res.status}: ${res.body.substring(0, 200)}`
    );
  }

  return res;
}

// ─────────────────────────────────────────────
// Main virtual user scenario
// Each VU runs this function repeatedly for the test duration
// ─────────────────────────────────────────────

export default function () {

  // 1. Yield prediction — M1 Random Forest
  group("M1 yield prediction", () => {
    post(
      "/api/yield/predict",
      YIELD_PAYLOAD,
      yieldTrend,
      "yield",
      2000
    );
  });
  sleep(1);

  // 2. Weather forecast — M2 LSTM
  group("M2 weather forecast", () => {
    post(
      "/api/weather/forecast",
      WEATHER_PAYLOAD,
      weatherTrend,
      "weather",
      3000
    );
  });
  sleep(1);

  // 3. Price prediction — M3 LSTM
  group("M3 price prediction", () => {
    post(
      "/api/price/predict",
      PRICE_PAYLOAD,
      priceTrend,
      "price",
      3000
    );
  });
  sleep(1);

  // 4. Demand prediction — M4 XGBoost
  group("M4 demand prediction", () => {
    post(
      "/api/demand/predict",
      DEMAND_PAYLOAD,
      demandTrend,
      "demand",
      2000
    );
  });
  sleep(1);

  // 5. Crop recommendation — M2→M1→M3→M5 chain (heaviest)
  group("M5 crop recommendation", () => {
    post(
      "/api/recommend",
      RECOMMEND_PAYLOAD,
      recommendTrend,
      "recommend",
      5000
    );
  });
  sleep(2);  // Extra pause after heavy endpoint

  // 6. Chatbot — M6 LLaMA via Groq
  group("M6 chatbot", () => {
    post(
      "/api/chat",
      CHAT_PAYLOAD,
      chatTrend,
      "chat",
      8000
    );
  });
  sleep(2);  // Extra pause after external API call
}

// ─────────────────────────────────────────────
// Summary — printed at end of test
// ─────────────────────────────────────────────

export function handleSummary(data) {
  const thresholds = data.metrics;

  // Build a simple result table for the report
  const endpoints = [
    { name: "M1 Yield",        metric: "yield_duration",     limit: 2000 },
    { name: "M2 Weather",      metric: "weather_duration",   limit: 3000 },
    { name: "M3 Price",        metric: "price_duration",     limit: 3000 },
    { name: "M4 Demand",       metric: "demand_duration",    limit: 2000 },
    { name: "M5 Recommend",    metric: "recommend_duration", limit: 5000 },
    { name: "M6 Chat",         metric: "chat_duration",      limit: 8000 },
  ];

  let table = "\n╔══════════════════════════════════════════════════════════════╗\n";
  table    += "║          CropSphere Load Test Results — Sprint 1             ║\n";
  table    += "╠══════════════════════════════════════════════════════════════╣\n";
  table    += "║  Endpoint          avg      p95      max      limit  status ║\n";
  table    += "╠══════════════════════════════════════════════════════════════╣\n";

  for (const ep of endpoints) {
    const m = thresholds[ep.metric];
    if (!m) {
      table += `║  ${ep.name.padEnd(18)} no data                           ║\n`;
      continue;
    }
    const avg  = Math.round(m.values["avg"]          || 0);
    const p95  = Math.round(m.values["p(95)"]        || 0);
    const max  = Math.round(m.values["max"]          || 0);
    const pass = p95 <= ep.limit ? " PASS ✓" : " FAIL ✗";
    table += `║  ${ep.name.padEnd(18)} ${String(avg).padStart(5)}ms  ${String(p95).padStart(5)}ms  ${String(max).padStart(5)}ms  ${String(ep.limit).padStart(5)}ms ${pass} ║\n`;
  }

  const errMetric  = thresholds["error_rate"];
  const errPct     = errMetric
    ? (errMetric.values["rate"] * 100).toFixed(2)
    : "0.00";
  const errPass    = parseFloat(errPct) < 1.0 ? "PASS ✓" : "FAIL ✗";

  table += "╠══════════════════════════════════════════════════════════════╣\n";
  table += `║  Error rate: ${errPct}%   threshold: <1%   ${errPass.padEnd(26)}║\n`;
  table += "╚══════════════════════════════════════════════════════════════╝\n";
  table += "\nSave this output as load_test_report.txt for FYP evidence.\n";

  return {
    stdout: table,
  };
}
