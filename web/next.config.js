const path = require("path");

/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  // Emits .next/standalone with a self-contained server.js and only the
  // node_modules it actually imports, so the runtime image does not carry a
  // toolchain it will never use.
  output: "standalone",
  outputFileTracingRoot: path.join(__dirname),
  // The version of Next is nobody's business but ours.
  poweredByHeader: false,
  async headers() {
    return [
      {
        source: "/:path*",
        headers: [
          // Nothing here is meant to be framed by another site: a scoring
          // screen inside somebody else's page is a way to trick a captain
          // into tapping something.
          { key: "X-Frame-Options", value: "SAMEORIGIN" },
          // An upload served as text/html would run as a page on our origin.
          { key: "X-Content-Type-Options", value: "nosniff" },
          // A share link should not carry the whole path to another site —
          // a scoreboard link is a secret, and it lives in the URL.
          { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
          // The camera is used to scan an opposition's QR code at the ground;
          // nothing else is, and nobody embedded needs any of it.
          {
            key: "Permissions-Policy",
            value: "camera=(self), microphone=(), geolocation=(), payment=(), usb=()",
          },
        ],
      },
    ];
  },
};

module.exports = nextConfig;
