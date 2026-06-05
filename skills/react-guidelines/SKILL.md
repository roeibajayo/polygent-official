---
name: react-guidelines
description: React coding guidelines and best practices. MUST follow these rules. Use when reviewing or writing React code or tasks.
---

# IMPORTANT React Guidelines

- NEVER use `useState` or `useEffect` directly in React Components. ALWAYS use custom hook in separated for that (e.g., `useBot` for `Bot` component/page)
- NEVER combine multiple hooks or components in a single file, even if they are small. EVERY hook, component or Modal should have its OWN file
- React components should ALWAYS be functions with default export (`export default function ComponentName() {}`), not class-based or arrow functions
- NEVER use `any` type OR anonymous types in TypeScript, ALWAYS use explicit types, if not existing - create them
- If any frontend changes are made, run `cd <path-to-project> && npx -y tsc --noEmit --skipLibCheck --project tsconfig.app.json && npx -y eslint .` and ensure no errors. DON'T run build for production to make sure the code is not broken
- If any frontend changes are made for `*.{js,ts,jsx,tsx,css,json,scss}` files, run `cd <path-to-project> && npx -y prettier <path/to/file> --write` and ensure no errors
- When creating a new React page, follow the provided instructions in [`references/instructions.md`](./references/instructions.md)
- Files containing ONLY interfaces or type aliases MUST use the `.d.ts` suffix (e.g., `Announcements.d.ts`)
