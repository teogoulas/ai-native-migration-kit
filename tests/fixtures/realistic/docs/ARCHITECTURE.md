# Architecture

The app is a single-page Next.js 15 project.

## Directory layout

```
realistic-fixture/
├── src/
│   ├── app/              # Next.js App Router entry points
│   ├── components/       # Reusable React components (NOTE: this does not exist yet)
│   └── lib/              # Utility modules
├── tests/                # Vitest unit tests
└── docs/                 # This directory
```

## Modules

### AppLayout

**Path:** `src/components/AppLayout.tsx`  <!-- also does not exist — A05 drift -->

Wraps every page in the standard shell.

### hello

**Path:** `src/app/page.tsx`

Renders the hello-world route.
