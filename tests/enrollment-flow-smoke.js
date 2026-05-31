import http from "k6/http";
import { check, group, sleep } from "k6";

// Small smoke test only. It creates real test rows for student, course,
// section, enrollment, payment, and notification validation.
const gatewayBaseUrl = __ENV.GATEWAY_BASE_URL || "http://localhost:8080";
const iterations = Number(__ENV.K6_FLOW_ITERATIONS || "1");
const vus = Number(__ENV.K6_FLOW_VUS || "1");

if (__ENV.TEST_PROFILE && __ENV.TEST_PROFILE.toLowerCase() !== "smoke") {
  throw new Error(`[ERROR] ${__ENV.TEST_PROFILE} profile is disabled in current project phase. Only smoke is allowed.`);
}

if (!Number.isFinite(vus) || vus !== 1) {
  throw new Error("[ERROR] K6_FLOW_VUS must remain 1. enrollment-flow-smoke.js is demo/local smoke only.");
}

if (!Number.isFinite(iterations) || iterations !== 1) {
  throw new Error("[ERROR] K6_FLOW_ITERATIONS must remain 1. enrollment-flow-smoke.js creates real test data.");
}

if (__ENV.K6_FLOW_MAX_DURATION) {
  throw new Error("[ERROR] K6_FLOW_MAX_DURATION override is disabled in current project phase. Smoke is fixed at 45s.");
}

console.warn("[WARN] enrollment-flow-smoke.js is demo/local smoke and creates real test rows for student, course, section, enrollment, payment, and notification validation.");

export const options = {
  scenarios: {
    enrollment_flow_smoke: {
      executor: "shared-iterations",
      vus: 1,
      iterations: 1,
      maxDuration: "45s",
    },
  },
  thresholds: {
    http_req_failed: [__ENV.K6_THRESHOLD_FAILURE_RATE || "rate<0.01"],
    http_req_duration: [__ENV.K6_THRESHOLD_P95_DURATION || "p(95)<2000"],
    checks: [__ENV.K6_THRESHOLD_CHECKS_RATE || "rate>0.95"],
  },
};

export function setup() {
  const response = http.get(`${gatewayBaseUrl}/health`);
  if (response.status !== 200) {
    throw new Error(`gateway is not healthy at ${gatewayBaseUrl}/health`);
  }
}

function jsonHeaders(extra = {}) {
  const headers = {
    "Content-Type": "application/json",
  };

  Object.keys(extra).forEach((key) => {
    headers[key] = extra[key];
  });

  return {
    headers,
  };
}

function parseJson(response) {
  try {
    return response.json();
  } catch (error) {
    return null;
  }
}

export default function () {
  const suffix = `${Date.now()}-${__VU}-${__ITER}`;
  let studentId;
  let courseId;
  let sectionId;
  let enrollmentId;

  group("create student", () => {
    const response = http.post(
      `${gatewayBaseUrl}/students`,
      JSON.stringify({
        fullName: `Smoke Student ${suffix}`,
        email: `smoke-${suffix}@campusenroll.local`,
        status: "ACTIVE",
      }),
      jsonHeaders(),
    );

    const body = parseJson(response);
    studentId = body && body.id;

    check(response, {
      "POST /students returns 201": (r) => r.status === 201,
      "student id returned": () => Number.isFinite(Number(studentId)),
    });
  });

  group("create course and section", () => {
    const courseResponse = http.post(
      `${gatewayBaseUrl}/courses`,
      JSON.stringify({
        courseCode: `SMK-${suffix}`,
        name: `Smoke Course ${suffix}`,
        description: "Small k6 smoke course",
        status: "ACTIVE",
      }),
      jsonHeaders(),
    );

    const courseBody = parseJson(courseResponse);
    courseId = courseBody && courseBody.id;

    check(courseResponse, {
      "POST /courses returns 201": (r) => r.status === 201,
      "course id returned": () => Number.isFinite(Number(courseId)),
    });

    const sectionResponse = http.post(
      `${gatewayBaseUrl}/sections`,
      JSON.stringify({
        courseId,
        sectionCode: `A-${__VU}-${__ITER}`,
        maxCapacity: 5,
        status: "ACTIVE",
        schedules: [
          {
            dayOfWeek: "MONDAY",
            startTime: "08:00:00",
            endTime: "09:00:00",
            classroom: "LAB-SMOKE",
          },
        ],
      }),
      jsonHeaders(),
    );

    const sectionBody = parseJson(sectionResponse);
    sectionId = sectionBody && sectionBody.id;

    check(sectionResponse, {
      "POST /sections returns 201": (r) => r.status === 201,
      "section id returned": () => Number.isFinite(Number(sectionId)),
    });
  });

  group("create enrollment with approved payment", () => {
    const response = http.post(
      `${gatewayBaseUrl}/api/enrollments`,
      JSON.stringify({
        studentId,
        sectionId,
        amount: 250.0,
        simulatePaymentFailure: false,
      }),
      jsonHeaders(),
    );

    const body = parseJson(response);
    enrollmentId = body && body.id;

    check(response, {
      "POST /api/enrollments returns 200": (r) => r.status === 200,
      "enrollment id returned": () => Number.isFinite(Number(enrollmentId)),
      "enrollment confirmed": () => body && body.status === "CONFIRMED",
    });
  });

  group("notification eventually visible", () => {
    sleep(2);
    const response = http.get(`${gatewayBaseUrl}/students/${studentId}/notifications`);
    const notifications = parseJson(response);

    check(response, {
      "GET student notifications returns 200": (r) => r.status === 200,
      "notification list returned": () => Array.isArray(notifications),
    });
  });
}
