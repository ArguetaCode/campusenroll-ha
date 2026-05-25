import http from "k6/http";
import { check, group, sleep } from "k6";

const gatewayBaseUrl = __ENV.GATEWAY_BASE_URL || "http://localhost:8080";
const billingBaseUrl = __ENV.BILLING_BASE_URL || gatewayBaseUrl;
const notificationBaseUrl = __ENV.NOTIFICATION_BASE_URL || gatewayBaseUrl;
const includeNotificationCheck = (__ENV.INCLUDE_NOTIFICATION_CHECK || "false").toLowerCase() === "true";
const testProfile = (__ENV.TEST_PROFILE || "smoke").toLowerCase();
const idempotencyKeyPrefix = __ENV.K6_IDEMPOTENCY_KEY_PREFIX || `k6-${testProfile}`;

const profileOptions = {
  smoke: {
    vus: 5,
    duration: "20s",
  },
  baseline: {
    vus: 20,
    duration: "60s",
  },
  volume50k: {
    vus: 50,
    iterations: 50000,
    maxDuration: "15m",
    sleepSeconds: 0,
  },
};

const selectedProfile = profileOptions[testProfile] || profileOptions.smoke;
const vusOverride = __ENV.K6_VUS ? Number(__ENV.K6_VUS) : null;
const durationOverride = __ENV.K6_DURATION || null;
const configuredVus = Number.isFinite(vusOverride) && vusOverride > 0 ? vusOverride : selectedProfile.vus;
const sleepSecondsOverride = __ENV.K6_SLEEP_SECONDS ? Number(__ENV.K6_SLEEP_SECONDS) : null;
const iterationSleepSeconds = Number.isFinite(sleepSecondsOverride) && sleepSecondsOverride >= 0
  ? sleepSecondsOverride
  : (selectedProfile.sleepSeconds ?? 1);
const profileThresholds = {
  smoke: {
    failureRate: "rate<0.01",
    p95Duration: "p(95)<1200",
    checksRate: "rate>0.99",
  },
  baseline: {
    failureRate: "rate<0.05",
    p95Duration: "p(95)<2500",
    checksRate: "rate>0.95",
  },
  volume50k: {
    failureRate: "rate<0.01",
    p95Duration: "p(95)<3000",
    checksRate: "rate>0.99",
  },
};
const selectedThresholds = profileThresholds[testProfile] || profileThresholds.smoke;
const failureRateThreshold = __ENV.K6_THRESHOLD_FAILURE_RATE || selectedThresholds.failureRate;
const p95DurationThreshold = __ENV.K6_THRESHOLD_P95_DURATION || selectedThresholds.p95Duration;
const checksRateThreshold = __ENV.K6_THRESHOLD_CHECKS_RATE || selectedThresholds.checksRate;

const thresholds = {
    http_req_failed: [failureRateThreshold],
    http_req_duration: [p95DurationThreshold],
    checks: [checksRateThreshold],
};

export const options = selectedProfile.iterations
  ? {
      scenarios: {
        payments: {
          executor: "shared-iterations",
          vus: configuredVus,
          iterations: selectedProfile.iterations,
          maxDuration: selectedProfile.maxDuration,
        },
      },
      thresholds,
    }
  : {
      vus: configuredVus,
      duration: durationOverride || selectedProfile.duration,
      thresholds,
    };

export function setup() {
  const healthUrl = `${gatewayBaseUrl}/health`;
  for (let attempt = 0; attempt < 30; attempt += 1) {
    const response = http.get(healthUrl);
    if (response.status === 200) {
      if (testProfile !== "volume50k") {
        return {};
      }

      const seedResponse = http.post(
        `${billingBaseUrl}/payments`,
        JSON.stringify({
          enrollmentId: 9000001,
          studentId: 900001,
          amount: 1.0,
          simulateFailure: false,
        }),
        {
          headers: {
            "Content-Type": "application/json",
            "Idempotency-Key": `${idempotencyKeyPrefix}-seed`,
          },
        },
      );
      if (seedResponse.status !== 200) {
        throw new Error(`volume50k seed payment failed with status ${seedResponse.status}`);
      }
      return { paymentId: seedResponse.json("paymentId") };
    }
    sleep(1);
  }
  throw new Error(`gateway is not healthy at ${healthUrl}`);
}

export default function (setupData) {
  if (testProfile === "volume50k") {
    const response = http.get(`${billingBaseUrl}/payments/${setupData.paymentId}`);
    check(response, {
      "GET /payments/{id} status is 200": (r) => r.status === 200,
    });
    return;
  }

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
