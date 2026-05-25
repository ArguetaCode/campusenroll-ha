import http from "k6/http";
import { check, group, sleep } from "k6";

// Small smoke test only. It creates real test rows for student, course,
// section, enrollment, payment, and notification validation.
const gatewayBaseUrl = __ENV.GATEWAY_BASE_URL || "http://localhost:8080";
const iterations = Number(__ENV.K6_FLOW_ITERATIONS || "1");
const vus = Number(__ENV.K6_FLOW_VUS || "1");

export const options = {
  scenarios: {
    enrollment_flow_smoke: {
      executor: "shared-iterations",
      vus: Number.isFinite(vus) && vus > 0 ? vus : 1,
      iterations: Number.isFinite(iterations) && iterations > 0 ? iterations : 1,
      maxDuration: __ENV.K6_FLOW_MAX_DURATION || "45s",
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
  return {
    headers: {
      "Content-Type": "application/json",
      ...extra,
    },
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
