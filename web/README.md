# Fishers web dashboard

Next.js App Router dashboard against the same Fishers API as iOS.

## Run

```bash
# API must be on :7312 (bound to 0.0.0.0 for LAN phones)
cd web
cp .env.local.example .env.local
npm install
npm run dev
```

`npm run dev` listens on **all interfaces** (`0.0.0.0:7311`). Always open the dashboard on the LAN host:

Open [http://192.168.1.99:7311](http://192.168.1.99:7311).

Demo login: `demo@fishers.test` / `password123`

API / Swagger: [http://192.168.1.99:7312/swagger-ui](http://192.168.1.99:7312/swagger-ui)
