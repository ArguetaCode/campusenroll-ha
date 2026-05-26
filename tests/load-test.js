import http from "k6/http";
import { check, group, sleep } from "k6";

const gatewayBaseUrl = __ENV.GATEWAY_BASE_URL || "http://localhost:8080";
const notificationBaseUrl = __ENV.NOTIFICATION_BASE_URL || gatewayBaseUrl;
const includeNotificationCheck = (__ENV.INCLUDE_NOTIFICATION_CHECK || "false").toLowerCase() === "true";
const testProfile = (__ENV.TEST_PROFILE || "smoke").toLowerCase();

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

console.warn("[WARN] load-test.js is a small smoke test and creates real enrollment and payment rows.");

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
  group("enrollment-service payment creation", () => {
    const suffix = `${Date.now()}-${__VU}-${__ITER}`;
    const headers = { headers: { "Content-Type": "application/json" } };
    const student = http.post(`${gatewayBaseUrl}/students`, JSON.stringify({
      fullName: `Load Student ${suffix}`,
      email: `${suffix}@campusenroll.local`,
      status: "ACTIVE",
    }), headers);
    const studentId = student.json("id");

    const course = http.post(`${gatewayBaseUrl}/courses`, JSON.stringify({
      courseCode: `LD-${suffix}`,
      name: `Load Course ${suffix}`,
      description: "Enrollment payment smoke",
      status: "ACTIVE",
    }), headers);
    const courseId = course.json("id");

    const section = http.post(`${gatewayBaseUrl}/sections`, JSON.stringify({
      courseId,
      sectionCode: `LD-${__VU}-${__ITER}`,
      maxCapacity: 1,
      status: "ACTIVE",
      schedules: [],
    }), headers);
    const sectionId = section.json("id");

    const response = http.post(`${gatewayBaseUrl}/api/enrollments`, JSON.stringify({
      studentId,
      sectionId,
      amount: 250.0,
      simulatePaymentFailure: false,
    }), headers);

    check(response, {
      "POST /api/enrollments status is 200": (r) => r.status === 200,
      "enrollment payment is confirmed": (r) => r.json("status") === "CONFIRMED",
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
