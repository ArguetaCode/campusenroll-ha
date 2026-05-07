import http from "k6/http";
import { check, sleep } from "k6";

export const options = {
  vus: 10,
  duration: "30s",
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

  const response = http.post("http://localhost:8083/payments", payload, params);

  check(response, {
    "billing-service responded": (r) => r.status === 200,
  });

  sleep(1);
}