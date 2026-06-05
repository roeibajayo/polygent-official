---
name: module-documentation
description: Create and maintain module documentation in docs/modules/. Use when creating new module docs, updating existing module documentation, or documenting new features within modules.
---

# Module Documentation

Create and maintain standardized module documentation for the Wendi platform.

## Outline

Module documentation lives in `docs/modules/{MODULE_NAME}.md`.
MODULE_NAME MUST be kebab-case, up to 4 words.
CRITICAL: Strictly follow the `Template` section as a template.
Each document follows a consistent structure:

| Section         | Purpose                                                         |
| --------------- | --------------------------------------------------------------- |
| Overview        | 2-3 sentences explaining module purpose and business value      |
| Core Components | Numbered list of main building blocks                           |
| Data Structure  | Entities (NO Fields details), relationships, and file locations |
| API Endpoints   | API methods with paths and descriptions                         |
| Services        | Key services with responsibilities                              |
| Pages           | Frontend pages with paths and descriptions                      |
| Configuration   | Important config settings                                       |
| Core Flows      | Numbered flows showing user/system interactions                 |
| How-To Guides   | For complex implementation patterns                             |

### Content Guidelines

1. **Be specific** - Include actual file paths, exact field names, real enum values
2. **Show relationships** - Explain how entities connect (RelatedContentId maps to X based on ActionType)
3. **Document edge cases** - Rate limits, expiration, soft deletes

### Validation Checklist

Before finalizing module documentation:

- [ ] Overview clearly explains business value
- [ ] All entities are listed with brief descriptions, NO DTOs, models, or any fields-level details
- [ ] Core flows cover happy path and error cases
- [ ] API endpoints match actual implementation
- [ ] How-to guides include all necessary steps
- [ ] File paths and enum values are accurate
- [ ] Save document to `docs/modules/{MODULE_NAME}.md`
- [ ] Run `node ./scripts/update-index.js`

## Template

```markdown
# [Module Name]

## Overview

[2-3 sentences on purpose and value].

## Core Components

1. `UserService`: Manages user data and operations.
2. `ModuleController`: Handles API requests for module features.
3. `DataRepository`: Interfaces with the database for module data.

## Data Structure

### Entities

| Entity Name | Description       | File                   |
| ----------- | ----------------- | ---------------------- |
| User        | Represents a user | `src/Models/User.cs`   |
| Action      | Logs user actions | `src/Models/Action.cs` |
| Event       | System events     | `src/Models/Event.cs`  |

### Relationships

Action -> User (many-to-one)
Event -> Action (one-to-many)

## API Endpoints

| Method | Endpoint                | Description    | File                                                     |
| ------ | ----------------------- | -------------- | -------------------------------------------------------- |
| GET    | `/api/v2/module/data`   | Get user data  | `GetUserData` in `src/Controllers/ModuleController.cs`   |
| POST   | `/api/v2/module/action` | Perform action | `PerformAction` in `src/Controllers/ModuleController.cs` |

## Services

| Service Name    | Responsibility          | File                            |
| --------------- | ----------------------- | ------------------------------- |
| `UserService`   | Manages user operations | `src/Services/UserService.cs`   |
| `ActionService` | Handles action logging  | `src/Services/ActionService.cs` |

## Pages

| Page Name   | Path                      | Description              | File                                     |
| ----------- | ------------------------- | ------------------------ | ---------------------------------------- |
| `Dashboard` | `/admin/module/dashboard` | Overview of module stats | `src/Frontend/Pages/Dashboard/index.tsx` |
| `Settings`  | `/admin/module/settings`  | Configure module options | `src/Frontend/Pages/Settings/index.tsx`  |

## Configuration

| Setting Name     | Description                    | File                           |
| ---------------- | ------------------------------ | ------------------------------ |
| `Module:Enabled` | Enables or disables the module | `src/Backend/appsettings.json` |
| `Module:ApiKey`  | API key for external services  | `src/Backend/appsettings.json` |

## Core Flows

### Flow Name

1. User initiates action by doing X
2. System responds by doing Y
3. User completes process by doing Z

## How-To Guides

### How to Add a New ActionType

1. Add the new enum value to `ActionTypes` in `src/Backend/Enums/ActionType.cs`.
2. Add the new enum value to `ActionType` in `src/Frontend/Enums/ActionType.ts`.
3. Add new option in `ActionType` select in `src/Frontend/Components/ActionForm.tsx`.

## Notes

- User id 0 means system user
- Soft deletes are implemented via `IsDeleted` boolean field
```
