---
name: dotnet-guidelines
description: C# coding guidelines and best practices. MUST follow these rules. Use when reviewing/writing C# code or dotnet tasks
---

# IMPORTANT Server Guideline

- ALWAYS Use Primary Constructors for classes
- ALWAYS Prefer `record` types for immutable data structures
- NEVER mix multiple classes or DTOs in a single file, even if they are small. Filename ALWAYS matches the class or DTO name, for example `UserDto.cs` for a `UserDto` class
- Private fields should NOT be prefixed with `_` (e.g., `repository` not `_repository`)
- Add (.) to the end of all server-side log messages
- Use `string?` over `string` for nullable strings
- Use `var` for local variables
- Don't use Regions in code files
- Use Collection initializers feature
- Use Anonymous static function where applicable (e.g., `Select(static x => x.Property)`)
- ALWAYS use `sealed` accessor for classes or records if not intended for inheritance
- ALWAYS use `ILogger` with Structured logging to log, no string interpolation and no other logging methods
- ALWAYS use Data Transfer Objects (DTO) for API input and output, never use domain models or entities
- ALWAYS use `x` as a parameter name in lambdas and anonymous functions
- NEVER use try-catch blocks solely to log and rethrow exceptions
- If any backend changes are made, run `dotnet build` in solution-level to ensure no build errors
- NEVER parallel DbContext or IRepository<> queries
- Do NOT create wrapper methods for specific cases that simply call another method with fixed parameters
- Unit tests MUST NOT simulated helper or logic methods, they MUST test the actual code by calling the actual method being tested
- When creating multiple unit tests ALWAYS make sure the first created test passes before creating the rest
