import http from "k6/http";
import { check, group, sleep } from "k6";

const gatewayBaseUrl = __ENV.GATEWAY_BASE_URL || "http://localhost:8080";
const billingBaseUrl = __ENV.BILLING_BASE_URL || gatewayBaseUrl;
const notificationBaseUrl = __ENV.NOTIFICATION_BASE_URL || gatewayBaseUrl;
const includeNotificationCheck = (__ENV.INCLUDE_NOTIFICATION_CHECK || "false").toLowerCase() === "true";
const testProfile = (__ENV.TEST_PROFILE || "smoke").toLowerCase();

const profileOptions = {
  smoke: {
    vus: 5,
    duration: "20s",
  },
  baseline: {
    vus: 20,
    duration: "60s",
  },
};

const selectedProfile = profileOptions[testProfile] || profileOptions.smoke;
const vusOverride = __ENV.K6_VUS ? Number(__ENV.K6_VUS) : null;
const durationOverride = __ENV.K6_DURATION || null;
const failureRateThreshold = __ENV.K6_THRESHOLD_FAILURE_RATE || "rate<0.01";
const p95DurationThreshold = __ENV.K6_THRESHOLD_P95_DURATION || "p(95)<1200";
const checksRateThreshold = __ENV.K6_THRESHOLD_CHECKS_RATE || "rate>0.99";

export const options = {
  vus: Number.isFinite(vusOverride) && vusOverride > 0 ? vusOverride : selectedProfile.vus,
  duration: durationOverride || selectedProfile.duration,
  thresholds: {
    http_req_failed: [failureRateThreshold],
    http_req_duration: [p95DurationThreshold],
    checks: [checksRateThreshold],
  },
};

export function setup() {
  const healthUrl = `${gatewayBaseUrl}/health`;
  for (let attempt = 0; attempt < 30; attempt += 1) {
    const response = http.get(healthUrl);
    if (response.status === 200) {
      return;
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

  sleep(1);
}
