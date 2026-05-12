import http from "k6/http";
import { check, group, sleep } from "k6";

const billingBaseUrl = __ENV.BILLING_BASE_URL || "http://localhost:8083";
const notificationBaseUrl = __ENV.NOTIFICATION_BASE_URL || "http://localhost:8084";
const includeNotificationCheck = (__ENV.INCLUDE_NOTIFICATION_CHECK || "false").toLowerCase() === "true";

export const options = {
  vus: 10,
  duration: "30s",
};

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
      const notificationResponse = http.get(`${notificationBaseUrl}/students/1/notifications`);
      check(notificationResponse, {
        "GET /students/1/notifications is reachable": (r) => r.status === 200 || r.status === 404,
      });
    });
  }

  sleep(1);
}
