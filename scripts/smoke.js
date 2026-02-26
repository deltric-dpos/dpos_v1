const http = require("http");

function get(path) {
  const url = `http://localhost:4001${path}`;
  return new Promise((resolve, reject) => {
    const req = http.get(url, { timeout: 8000 }, (res) => {
      let data = "";
      res.on("data", (c) => (data += c));
      res.on("end", () => resolve({ status: res.statusCode, body: data }));
    });
    req.on("error", reject);
    req.on("timeout", () => req.destroy(new Error(`Timeout: ${url}`)));
  });
}

(async () => {
  try {
    const h = await get("/healthz");
    if (h.status !== 200) {
      console.error("FAIL /healthz", h.status, h.body.slice(0, 200));
      process.exit(1);
    }
    const m = await get("/metrics");
    if (m.status !== 200 || !m.body || m.body.length < 20) {
      console.error("FAIL /metrics", m.status, (m.body || "").slice(0, 200));
      process.exit(1);
    }
    console.log("✅ CI smoke ok");
  } catch (e) {
    console.error("Smoke error:", e.message || e);
    process.exit(1);
  }
})();
