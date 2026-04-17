# Rloco Guidelines

## Token Control (AI)
- Use targeted search (grep/glob) before broad file reads
- Prefer search_replace over full-file edits
- One concern per change; skip unrelated refactors
- No redundant explanations-code is enough

## Code Style
- Small files; extract helpers/components
- Flexbox/Grid by default; avoid absolute unless needed
- Functional components; custom hooks for reuse
- Colocate styles with components

## Stack Reference
- **Frontend**: `@/` -> `frontend/src/`, MUI + Radix primitives
- **Backend**: Gin handlers, services in `internal/`
- **Mobile**: Capacitor-shared web build, platform plugins for native features
