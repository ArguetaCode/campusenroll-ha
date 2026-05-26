import http from "k6/http";
import { check, group, sleep } from "k6";

const gatewayBaseUrl = __ENV.GATEWAY_BASE_URL || "http://localhost:8080";
const billingBaseUrl = __ENV.BILLING_BASE_URL || gatewayBaseUrl;
const notificationBaseUrl = __ENV.NOTIFICATION_BASE_URL || gatewayBaseUrl;
const includeNotificationCheck = (__ENV.INCLUDE_NOTIFICATION_CHECK || "false").toLowerCase() === "true";
const testProfile = (__ENV.TEST_PROFILE || "smoke").toLowerCase();
const idempotencyKeyPrefix = __ENV.K6_IDEMPOTENCY_KEY_PREFIX || `k6-${testProfile}`;

if (testProfile !== "smoke") {
  throw new Error(`[ERROR] ${testProfile} profile is disabled in current project phase. Only smoke is allowed.`);
}

if (__ENV.K6_VUS) {
  throw new Error("[ERROR] K6_VUS override is disabled in current project phase. Smoke is fixed at 5 VUs.");
}

if (__ENV.K6_DURATION) {
  throw new Error("[ERROR] K6_DURATION override is disabled in current project phase. Smoke is fixed at 20s.");
}

if (__ENV.K6_SLEEP_SECONDS) {
  throw new Error("[ERROR] K6_SLEEP_SECONDS override is disabled to avoid accidental high-throughput smoke runs.");
}

console.warn("[WARN] load-test.js is a small smoke test and creates real test payment rows.");

const profileOptions = {
  smoke: {
    vus: 5,
    duration: "20s",
  },
};

const selectedProfile = profileOptions.smoke;
const configuredVus = selectedProfile.vus;
const iterationSleepSeconds = 1;
const profileThresholds = {
  smoke: {
    failureRate: "rate<0.01",
    p95Duration: "p(95)<1200",
    checksRate: "rate>0.99",
  },
};
const selectedThresholds = profileThresholds.smoke;
const failureRateThreshold = __ENV.K6_THRESHOLD_FAILURE_RATE || selectedThresholds.failureRate;
const p95DurationThreshold = __ENV.K6_THRESHOLD_P95_DURATION || selectedThresholds.p95Duration;
const checksRateThreshold = __ENV.K6_THRESHOLD_CHECKS_RATE || selectedThresholds.checksRate;

const thresholds = {
    http_req_failed: [failureRateThreshold],
    http_req_duration: [p95DurationThreshold],
    checks: [checksRateThreshold],
};

export const options = {
  vus: configuredVus,
  duration: selectedProfile.duration,
  thresholds,
};

export function setup() {
  const healthUrl = `${gatewayBaseUrl}/health`;
  for (let attempt = 0; attempt < 30; attempt += 1) {
    const response = http.get(healthUrl);
    if (response.status === 200) {
      return {};
    }
    sleep(1);
  }
  throw new Error(`gateway is not healthy at ${healthUrl}`);
}

export default function () {
  group("billing-service payment creation", () => {
    const payload = JSON.stringify({
      enrollmentId: Math.floor(Math.random() * 100000),
      studentId: Math.floor(Math.random() * 10000),
      amount: 250.0,
      simulateFailure: false,
    });

    const response = http.post(`${billingBaseUrl}/payments`, payload, {
      headers: {
        "Content-Type": "application/json",
        "Idempotency-Key": `${idempotencyKeyPrefix}-vu-${__VU}`,
      },
    });

    check(response, {
      "POST /payments status is 200": (r) => r.status === 200,
    });
  });

  if (includeNotificationCheck) {
    group("notification-service optional query", () => {
      const notificationResponse = http.get(`${notificationBaseUrl}/notifications`);
      check(notificationResponse, {
        "GET /notifications is reachable": (r) => r.status === 200 || r.status === 404,
      });
    });
  }

  if (iterationSleepSeconds > 0) {
    sleep(iterationSleepSeconds);
  }
}
