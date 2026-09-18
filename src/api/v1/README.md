# Server route map

The production route handlers live in the existing TIARENTAL Next.js application so that they reuse its booking, pricing, authorization and Supabase transaction boundaries. This directory contains the public zero-dependency JavaScript client and its TypeScript declarations. `openapi/openapi.yaml` is the normative HTTP contract.

Do not deploy a second booking engine from this repository. Deploy the reviewed migration and main TIARENTAL release together, map `api.tiarental.com` to that Vercel project, and keep TIARENTAL as the single source of truth.
