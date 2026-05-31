import http from "k6/http";

const gatewayBaseUrl = __ENV.GATEWAY_BASE_URL || "http://localhost:8080";

export const options = {
  vus: Number(__ENV.K6_VUS || "500"),
  duration: __ENV.K6_DURATION || "5m",
};

export default function () {
  http.get(`${gatewayBaseUrl}/students`);
}
