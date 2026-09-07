# Fishers web dashboard

Next.js App Router dashboard against the same Fishers API as iOS.

## Run

```bash
# API must be on :8080 (bound to 0.0.0.0 for LAN phones)
cd web
cp .env.local.example .env.local
npm install
npm run dev
```

`npm run dev` listens on **all interfaces** (`0.0.0.0:3000`). Always open the dashboard on the LAN host:

Open [http://192.168.1.99:3000](http://192.168.1.99:3000).

Demo login: `demo@fishers.test` / `password123`

API / Swagger: [http://192.168.1.99:8080/swagger-ui](http://192.168.1.99:8080/swagger-ui)
