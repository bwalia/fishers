const path = require("path");

/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  // Emits .next/standalone with a self-contained server.js and only the
  // node_modules it actually imports, so the runtime image does not carry a
  // toolchain it will never use.
  output: "standalone",
  outputFileTracingRoot: path.join(__dirname),
};

module.exports = nextConfig;
