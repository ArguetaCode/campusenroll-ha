import http from "k6/http";
import { check, sleep } from "k6";

const baseUrl = __ENV.BASE_URL || "http://billing-service:8083";

export const options = {
  vus: 10,
  duration: "1m",
};

export default function () {
  const payload = JSON.stringify({
    enrollmentId: Math.floor(Math.random() * 100000),
    studentId: Math.floor(Math.random() * 10000),
    amount: 250.00,
    simulateFailure: false
  });

  const params = {
    headers: {
      "Content-Type": "application/json",
    },
  };

  const response = http.post(`${baseUrl}/payments`, payload, params);

  check(response, {
    "billing-service responded": (r) => r.status === 200,
  });

  sleep(1);
}
