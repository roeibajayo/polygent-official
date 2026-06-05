# Creating a New React Page Guidelines

**Path are for example only, adjust based on actual project structure.**

## File Structure Pattern

Pages follow a strict organizational pattern with separation of concerns:

```text
pages/<PageName>/
├── index.tsx              # Main page component (presentation only)
├── use<PageName>.ts       # Custom hook (all state and logic)
├── <SubComponent1>.tsx    # Related sub-components (if needed)
├── <SubComponent2>.tsx    # More sub-components (if needed)
└── <Section>/             # Complex sections with multiple files
    ├── index.tsx
    └── use<Section>.ts
```

## Step 1: Create Main Page Component

**Location:** `@/pages/<PageName>/index.tsx`

**Template:**

```typescript
import Page from '@/components/Page';
import use<PageName> from './use<PageName>';

export default function <PageName>() {
  const {
    // Destructure state and handlers from custom hook
    data,
    loading,
    error,
    handleAction
  } = use<PageName>();

  if (loading) {
    return <Page loading={loading} />;
  }

  if (error) {
    return <Page title="page title">
      <div className="text-red-600">{error}</div>
    </Page>;
  }

  return (
    <Page title="page title">
      {/* Pure presentation JSX - no business logic */}
      <div className="space-y-4">
        {/* Your UI here */}
      </div>
    </Page>
  );
}
```

**Key Rules:**

- Component MUST be a default export function (not arrow function)
- Component MUST be presentation-only (no useState, useEffect, business logic)
- All state management delegated to custom hook
- Use `<Page>` wrapper component for consistent layout

## Step 2: Create Custom Hook

**Location:** `@/pages/<PageName>/use<PageName>.ts`

**Template:**

```typescript
import { useState, useEffect, useCallback } from 'react';
import { fetch<Action> } from '@/api/<domain>';
import type { <DataType> } from '@/api/<domain>';

export default function use<PageName>() {
  // State declarations
  const [data, setData] = useState<<DataType>[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // Data fetching
  const loadData = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      const result = await fetch<Action>();
      setData(result);
    } catch (err) {
      const error = err instanceof Error ? err : new Error(String(err));
      console.error('Error loading data:', error);
      setError(error.message);
    } finally {
      setLoading(false);
    }
  }, []);

  // Event handlers
  const handleAction = useCallback(async (id: number) => {
    try {
      // Perform action
      await loadData(); // Refresh data
    } catch (err) {
      console.error('Error performing action:', err);
    }
  }, [loadData]);

  // Initial load
  useEffect(() => {
    loadData();
  }, [loadData]);

  // Return all state and handlers
  return {
    data,
    loading,
    error,
    handleAction,
    loadData
  };
}
```

**Key Rules:**

- Hook MUST be a default export function named `use<PageName>`
- All useState, useEffect, useCallback, useMemo go here
- All API calls happen in the hook
- Use proper TypeScript types from API layer
- Return object with all state and handlers needed by component
- Handle errors with try/catch and user-friendly messages
- Use `useCallback` for functions to prevent re-renders

## Step 3: Add Route

Add route to the router configuration:

```typescript
import <PageName> from './pages/<PageName>';

// In the Routes component:
<Route path="/<page-path>" element={<<PageName> />} />
```

## Step 4: Add to Navigation (if needed)

Add menu item to navigation component

## Complex Page Example

For pages with multiple sections (like Home page):

```text
Home/
├── index.tsx                    # Main layout
├── useHome.tsx                  # Main state
├── AccountBalance/
│   ├── index.tsx               # Section component
│   ├── useAccountBalance.tsx   # Section state
│   └── AccountBalanceGraph.tsx # Sub-component
├── ActiveTrades/
│   ├── index.tsx
│   ├── useActiveTrades.tsx
│   ├── BuyPopup/
│   │   └── index.tsx
│   └── PlaceOrderModal/
│       └── index.tsx
└── HistoryTrades/
    ├── index.tsx
    └── useHistoryTrades.tsx
```

**Pattern:** Each complex section gets its own folder with hook and sub-components.

## Component Splitting Guidelines

Split into sub-components when:

1. A section has 50+ lines of JSX
2. A section has its own state/logic
3. A section could be reusable
4. A section handles a specific concern (e.g., data table, form, chart)

**Example:**

```typescript
// Home/index.tsx (main page - just layout)
export default function Home() {
  const { brokerAccountId, loading } = useHome();

  return (
    <Page loading={loading}>
      <Header />
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-12">
        <ActiveTrades />
        <PendingOrders />
      </div>
      <Footer />
    </Page>
  );
}
```

## Validation Checklist

- [ ] Page component created at correct location
- [ ] Component is default export function (not arrow function)
- [ ] Custom hook created with `use<PageName>` naming
- [ ] All state management in hook (no useState/useEffect in component)
- [ ] Route added to router
- [ ] No hardcoded text in component
- [ ] Proper TypeScript types from API layer
- [ ] Error handling implemented
- [ ] Loading states handled
- [ ] Navigation item added (if public page)
- [ ] Complex sections split into sub-components
- [ ] Responsive design with Tailwind classes (grid, flex, lg:)

## Anti-Patterns to Avoid

❌ **Don't:** Put business logic in component

```typescript
export default function MyPage() {
  const [data, setData] = useState([]);
  useEffect(() => {
    fetchData().then(setData);
  }, []); // ❌ WRONG
}
```

✅ **Do:** Put all logic in hook

```typescript
export default function MyPage() {
  const { data, loading } = useMyPage(); // ✅ CORRECT
}
```

❌ **Don't:** Use hardcoded strings

```typescript
<h1>My Page Title</h1> // ❌ WRONG
```

✅ **Do:** Use localization if available

```typescript
<h1>{locale.MyPageTitle}</h1> // ✅ CORRECT
```

❌ **Don't:** Mix component and hook in same file

```typescript
// MyPage.tsx - ❌ WRONG
function useMyPage() { ... }
export default function MyPage() { ... }
```

✅ **Do:** Separate into two files

```typescript
// useMyPage.ts - ✅ CORRECT
export default function useMyPage() { ... }

// index.tsx - ✅ CORRECT
export default function MyPage() { ... }
```
