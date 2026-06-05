---
name: dotnet-refactor
description: Analyzes code quality, suggests improvements, and safely refactors code while preserving behavior. Use when improving code structure, addressing technical debt, or refactoring dotnet code.
---

# Refactor Skill

Systematic code refactoring with progressive disclosure.

## Workflow

### 1. Initial Assessment

- **Scope**: Identify files/modules to analyze
- **Language**: Detect programming language and idioms
- **Test Coverage**: Check if tests exist
- **Quick Scan**: Find code smells (file size, function length, complexity)

### 2. Deep Analysis

- **God Classes**: Classes or Interfaces with >4 public methods
- **Long Functions**: Functions >50 LOC or cyclomatic complexity >10
- **Deep Nesting**: Conditionals nested
- **Large Files**: Files >500 lines
- **Parameter Overload**: Public functions with >4 parameters
- **SOLID Principles**: Violations of SOLID design principles
- **Coupling**: High inter-module dependencies
- **Duplication**: Repeated code blocks (>=2 lines similar)
- **Magic Values**: Hardcoded numbers/strings without constants
- **Poor Naming**: Unclear variable/function names
- **Dead Code**: Unused functions, variables, imports
- **Global State**: Mutable global variables
- **Error Handling**: Missing error handling or overly broad catches
- **Performance Bottlenecks**: Inefficient algorithms, unnecessary loops
- **Security Concerns**: SQL injection risks, XSS vulnerabilities, exposed secrets
- **Memory Leaks**: Unclosed resources, circular references

### 3. Execute Refactoring

1. **Pre-Refactor**:
   - Ensure tests exist (warn if missing)
   - Run tests to establish baseline

2. **Refactor Incrementally**:
   - Apply one pattern at a time
   - Keep changes atomic
   - Preserve exact behavior
   - Update related documentation/comments

3. **Post-Refactor**:
   - Run tests after each change
   - Verify behavior unchanged
   - Update tests if needed (structure only)

## Refactoring Patterns Catalog

### Extract Function/Method

**When**: Function >30 LOC, doing multiple things, or code duplication

```typescript
// Before
function processUser(user: User) {
  if (!user.email || !user.email.includes('@')) {
    throw new Error('Invalid email');
  }
  const hash = crypto.createHash('sha256').update(user.password).digest('hex');
  user.password = hash;
  db.save(user);
  logger.info(`User ${user.email} processed`);
}

// After
function processUser(user: User) {
  validateEmail(user.email);
  user.password = hashPassword(user.password);
  saveUser(user);
  logUserProcessed(user.email);
}

function validateEmail(email: string) {
  if (!email || !email.includes('@')) {
    throw new Error('Invalid email');
  }
}

function hashPassword(password: string): string {
  return crypto.createHash('sha256').update(password).digest('hex');
}

function saveUser(user: User) {
  db.save(user);
}

function logUserProcessed(email: string) {
  logger.info(`User ${email} processed`);
}
```

### Extract Class/Module

**When**: Class >10 methods, multiple responsibilities

```python
# Before
class UserManager:
    def create_user(self, data): ...
    def update_user(self, id, data): ...
    def delete_user(self, id): ...
    def send_email(self, user, subject, body): ...
    def send_sms(self, user, message): ...
    def validate_password(self, password): ...
    def hash_password(self, password): ...

# After
class UserRepository:
    def create(self, data): ...
    def update(self, id, data): ...
    def delete(self, id): ...

class NotificationService:
    def send_email(self, user, subject, body): ...
    def send_sms(self, user, message): ...

class PasswordManager:
    def validate(self, password): ...
    def hash(self, password): ...
```

### Introduce Parameter Object

**When**: Functions with >4 parameters, parameters often used together

```java
// Before
public void createOrder(String userId, String productId, int quantity,
                       String address, String city, String zipCode,
                       String paymentMethod, String cardNumber) {
    // ...
}

// After
public void createOrder(OrderRequest request) {
    // ...
}

class OrderRequest {
    private String userId;
    private String productId;
    private int quantity;
    private Address shippingAddress;
    private PaymentInfo payment;
}
```

### Simplify Complex Conditionals

**When**: Nested conditionals >3 levels, hard to understand logic

```go
// Before
func canProcess(order Order) bool {
    if order.Status == "pending" {
        if order.Amount > 0 {
            if order.Customer != nil {
                if order.Customer.IsActive && order.Customer.CreditScore > 600 {
                    return true
                }
            }
        }
    }
    return false
}

// After
func canProcess(order Order) bool {
    return order.isPending() &&
           order.hasValidAmount() &&
           order.hasActiveCustomer() &&
           order.hasGoodCredit()
}

func (o Order) isPending() bool {
    return o.Status == "pending"
}

func (o Order) hasValidAmount() bool {
    return o.Amount > 0
}

func (o Order) hasActiveCustomer() bool {
    return o.Customer != nil && o.Customer.IsActive
}

func (o Order) hasGoodCredit() bool {
    return o.Customer != nil && o.Customer.CreditScore > 600
}
```

### Replace Magic Numbers/Strings

**When**: Hardcoded values without context

```csharp
// Before
public decimal CalculateTax(decimal amount) {
    if (amount > 10000) {
        return amount * 0.25;
    }
    return amount * 0.15;
}

// After
private const decimal HIGH_VALUE_THRESHOLD = 10000m;
private const decimal HIGH_VALUE_TAX_RATE = 0.25m;
private const decimal STANDARD_TAX_RATE = 0.15m;

public decimal CalculateTax(decimal amount) {
    if (amount > HIGH_VALUE_THRESHOLD) {
        return amount * HIGH_VALUE_TAX_RATE;
    }
    return amount * STANDARD_TAX_RATE;
}
```

### Invert Conditional Logic

**When**: Deeply nested conditionals, improve readability

```csharp
// Before
public decimal CalculateTax(decimal amount) {
    if (IsValidAmount(amount)) {
        // complex tax calculation logic
        return computedTax;
    }
    return 0;
}

// After
public decimal CalculateTax(decimal amount) {
    if (!IsValidAmount(amount)) {
        return 0;
    }
    // complex tax calculation logic
    return computedTax;
}

```

## Before/After Conversion Example

**Before (untestable mixed logic in endpoint):**

```csharp
public async Task<IResult> GetOrderSummary(int userId, CancellationToken ct)
{
    if (userId <= 0)
        throw new ArgumentException("Invalid user ID");

    var orders = await _orderRepository.GetByUserAsync(userId, ct);
    var user = await _userRepository.GetByIdAsync(userId, ct);

    var activeOrders = orders.Where(o => o.Status != OrderStatus.Cancelled).ToList();
    var totalSpent = activeOrders.Sum(o => o.Items.Sum(i => i.Price * i.Quantity));
    var hasDiscount = totalSpent > 1000 && user.MembershipLevel >= MembershipLevel.Gold;
    var discountPercent = hasDiscount ? 0.1m : 0m;

    return Results.Ok(new OrderSummaryDto
    {
        UserId = userId,
        UserName = user.FullName,
        ActiveOrderCount = activeOrders.Count,
        TotalSpent = totalSpent,
        DiscountPercent = discountPercent
    });
}
```

**After (thin endpoint + logic service orchestrator):**

```csharp
// Endpoint — thin, maps DTOs and calls logic service
public async Task<IResult> GetOrderSummary(GetOrderSummaryRequest request, CancellationToken ct)
{
    // Map endpoint DTO -> logic DTO
    var logicRequest = new GetOrderSummaryLogicRequest { UserId = request.UserId };

    var logicResponse = await _orderLogicService.GetOrderSummaryAsync(logicRequest, ct);

    // Map logic DTO -> endpoint DTO
    var response = new GetOrderSummaryResponse
    {
        UserName = logicResponse.UserName,
        ActiveOrderCount = logicResponse.ActiveOrderCount,
        TotalSpent = logicResponse.TotalSpent,
        DiscountPercent = logicResponse.DiscountPercent
    };
    return Results.Ok(response);
}

// Logic service (orchestrator) — owns the full flow
public class OrderLogicService(
    IOrderRepository orderRepository,
    IUserRepository userRepository)
{
    public async Task<GetOrderSummaryLogicResponse> GetOrderSummaryAsync(GetOrderSummaryLogicRequest request, CancellationToken ct)
    {
        // 1. Input validation
        ValidateUserId(request.UserId);

        // 2. Fetch data (repository)
        var orders = await orderRepository.GetByUserAsync(request.UserId, ct);
        var user = await userRepository.GetByIdAsync(request.UserId, ct);

        // 3. Logic functions
        return BuildOrderSummary(request.UserId, user, orders);
    }

    internal static void ValidateUserId(int userId)
    {
        if (userId <= 0)
            throw new ArgumentException("Invalid user ID");
    }

    internal static List<Order> GetActiveOrders(List<Order> orders)
    {
        return orders.Where(o => o.Status != OrderStatus.Cancelled).ToList();
    }

    internal static decimal CalculateTotalSpent(List<Order> activeOrders)
    {
        return activeOrders.Sum(o => o.Items.Sum(i => i.Price * i.Quantity));
    }

    internal static decimal CalculateDiscountPercent(decimal totalSpent, MembershipLevel level)
    {
        return totalSpent > 1000 && level >= MembershipLevel.Gold ? 0.1m : 0m;
    }

    internal static GetOrderSummaryLogicResponse BuildOrderSummary(int userId, User user, List<Order> orders)
    {
        var activeOrders = GetActiveOrders(orders);
        var totalSpent = CalculateTotalSpent(activeOrders);
        var discountPercent = CalculateDiscountPercent(totalSpent, user.MembershipLevel);

        return new GetOrderSummaryLogicResponse
        {
            UserId = userId,
            UserName = user.FullName,
            ActiveOrderCount = activeOrders.Count,
            TotalSpent = totalSpent,
            DiscountPercent = discountPercent
        };
    }
}
```

## Conversion Checklist

- [ ] Endpoint is thin — maps endpoint DTOs to/from logic DTOs, calls logic service, no business logic
- [ ] Logic service orchestrator does: validate → fetch (repository) → call pure functions → return
- [ ] All data access extracted to repository/service layer, injected into logic service
- [ ] All validation and business logic extracted to `internal static` pure functions
- [ ] Pure functions have NO async, NO injected dependencies, NO side effects
- [ ] `InternalsVisibleTo` configured for the test project
- [ ] Pure functions have **full test coverage** (all branches, edge cases, boundaries)
- [ ] Orchestrator has tests for most common success and failure paths

## Critical Rules

- **NO GOD CLASSES**: Any class or interface with more than 4 public methods MUST be split into single-responsibility classes

## Safety Rules

- Never change observable behavior
- Ensure tests exist before major refactoring
- Make atomic commits per refactoring step
- Run tests after each change
- Document breaking changes (if unavoidable)
- Preserve error handling behavior
- Maintain performance characteristics
- Keep API compatibility unless explicitly breaking
