import dotenv from "dotenv";

dotenv.config();

console.log("D-POS Worker started...");

setInterval(() => {
  console.log("Worker heartbeat:", new Date().toISOString());
}, 10000);