# Flame Graph Context Management - Development Status

**Generated:** 2025-12-24
**Status:** Active Development (Phase 1.7)

---

## 1. Current State Summary

### Overview

The Flame Graph Context Management system consists of two main components:

1. **Plugin** - Located in `/Users/sl/code/flame/.opencode/plugin/`
2. **UI** - Located in `/Users/sl/code/opencode/packages/app/src/components/flame/`

### Component Details

#### 1.1 Plugin Code (`/Users/sl/code/flame/`)

**Location:** `/Users/sl/code/flame/.opencode/plugin/`

| File | Lines | Description |
|------|-------|-------------|
| `flame.ts` | ~5,071 | Main plugin implementing Phase 1.7 (Agent Autonomy) |
| `flame-validation.ts` | ~561 | Validation plugin for testing hooks and assumptions |

**Key Features (Phase 1.7):**
- Frame State Manager with file-based persistence
- `/push` and `/pop` commands for frame lifecycle
- Token Budget Manager with configurable limits
- Intelligent Ancestor Selection and Sibling Relevance Filtering
- Context Caching with TTL
- Custom compaction prompts
- TaskTool/subagent session detection
- Planned frame support (`flame_plan`, `flame_plan_children`, `flame_activate`)
- Invalidation cascade (`flame_invalidate`)
- Frame tree visualization (`flame_tree`)
- Autonomy configuration (manual/suggest/auto modes)
- Push/pop heuristics for failure boundary and context switch detection

**Dependencies:**
```json
{
  "dependencies": {
    "@opencode-ai/plugin": "1.0.193"
  }
}
```

#### 1.2 UI Code (`/Users/sl/code/opencode/`)

**Location:** `/Users/sl/code/opencode/packages/app/src/components/flame/`

**Files Added/Modified (26 total flame-related files):**

| Directory | Files |
|-----------|-------|
| `flame/` (root) | `FlamePanel.tsx`, `FlameGraph.tsx`, `FlameProvider.tsx`, `index.tsx`, `types.ts`, `constants.ts`, `styles.css`, `Connection.tsx`, `ConnectionStatus.tsx`, `ContextMenu.tsx`, `ErrorBoundary.tsx`, `FilterDropdown.tsx`, `FrameRect.tsx`, `Legend.tsx`, `LoadingStates.tsx`, `SearchBar.tsx`, `Tooltip.tsx`, `ZoomControls.tsx` |
| `flame/dialogs/` | `EditGoal.tsx`, `InvalidateFrame.tsx`, `PlanChildren.tsx`, `PopFrame.tsx`, `PushFrame.tsx`, `index.tsx` |
| `flame/FrameDetails/` | `Artifacts.tsx`, `Decisions.tsx`, `Header.tsx`, `Summary.tsx`, `index.tsx` |
| `flame/hooks/` | `useAnimation.ts`, `useFlameEvents.ts`, `useKeyboard.ts`, `useLayout.ts`, `useZoom.ts` |
| `flame/utils/` | `api.ts`, `tree.ts` |
| `flame/__tests__/` | `flame.test.ts` |

**Server Changes:**
- `/Users/sl/code/opencode/packages/opencode/src/server/server.ts` - Added `/flame/tool` and `/flame/state` API endpoints

**Layout Changes:**
- `/Users/sl/code/opencode/packages/app/src/context/layout.tsx` - Added flame panel state management (open/close/toggle/resize)

---

## 2. Git State

### 2.1 Plugin Repository (`/Users/sl/code/flame/`)

**STATUS: NOT A GIT REPOSITORY**

The `/Users/sl/code/flame/` directory does not have a `.git` folder. Git needs to be initialized.

```bash
# No git history exists
$ git status
fatal: not a git repository (or any of the parent directories): .git
```

### 2.2 OpenCode Repository (`/Users/sl/code/opencode/`)

**STATUS: Has uncommitted changes on `dev` branch**

```
Branch: dev
Remote: origin -> git@github.com:sst/opencode.git
Status: Up to date with origin/dev (but has local uncommitted changes)
```

**Uncommitted Changes:**
```
Modified files (4):
  - bun.lock (+148 lines)
  - packages/app/package.json (+10 lines)
  - packages/app/src/context/layout.tsx (+36 lines)
  - packages/opencode/src/server/server.ts (+154 lines)

Untracked directories (1):
  - packages/app/src/components/flame/ (entire directory)

Total: +348 lines added
```

**Recent Commits (on dev):**
```
4b6575999 chore: generate
1a9ee3080 zen: sync
f4d61be8b feat(mcp): handle tools/list_changed notifications (#5913)
8b40e38cd test: add test for retry
7396d495e chore: regen sdk
```

---

## 3. Steps to Run Locally

### 3.1 Running OpenCode with Flame UI

```bash
# 1. Navigate to OpenCode repository
cd /Users/sl/code/opencode

# 2. Install dependencies (if not already done)
bun install

# 3. Run the development server
bun dev

# This runs:
# bun run --cwd packages/opencode --conditions=browser src/index.ts
```

**Requirement:** Bun 1.3+

### 3.2 Enabling the Flame Plugin

The flame plugin is loaded automatically from the `.opencode/plugin/` directory:

1. **Project-level plugin (current setup):**
   - Location: `/Users/sl/code/flame/.opencode/plugin/flame.ts`
   - This is auto-loaded when running OpenCode in `/Users/sl/code/flame/`

2. **Global plugin (alternative):**
   - Location: `~/.config/opencode/plugin/flame.ts`
   - Would be available in all projects

### 3.3 Testing the Setup

```bash
# Run OpenCode in the flame project directory
cd /Users/sl/code/flame
opencode  # or use the dev build from /Users/sl/code/opencode

# The flame plugin should auto-load
# Check for "Plugin initialized" messages in console
```

### 3.4 Running Tests

```bash
# For OpenCode
cd /Users/sl/code/opencode
bun test

# Specific flame tests
bun test packages/app/src/components/flame/__tests__/flame.test.ts
```

---

## 4. Steps to Save Progress to Git (Local)

### 4.1 Initialize Git for Flame Repository

```bash
# Initialize the flame repository
cd /Users/sl/code/flame
git init
git add .
git commit -m "feat: Flame Graph Context Management Plugin (Phase 1.7)

Implements tree-structured context management for AI agents:
- Frame State Manager with file-based persistence
- Push/pop commands for frame lifecycle management
- Token budget management with intelligent ancestor/sibling selection
- Subagent integration and automatic frame creation
- Planned frame support with invalidation cascade
- Agent autonomy with configurable push/pop heuristics
- Frame tree visualization"
```

### 4.2 Commit OpenCode Changes

```bash
cd /Users/sl/code/opencode

# Create a feature branch
git checkout -b feature/flame-graph-ui

# Stage all flame-related changes
git add packages/app/src/components/flame/
git add packages/app/src/context/layout.tsx
git add packages/opencode/src/server/server.ts
git add packages/app/package.json
git add bun.lock

# Commit
git commit -m "feat: Add Flame Graph UI for context management

Adds a visual flame graph panel for managing AI agent context:
- FlameGraph component with D3-based visualization
- FlamePanel with resizable sidebar integration
- Frame details panel (summary, artifacts, decisions)
- Dialogs for push/pop/plan/invalidate operations
- Server endpoints for flame state and tool execution
- Keyboard navigation and zoom controls
- Connection status and error handling"
```

**Suggested Commit Messages:**

| Scope | Message |
|-------|---------|
| Plugin | `feat: Flame Graph Context Management Plugin (Phase 1.7)` |
| UI | `feat: Add Flame Graph UI for context management` |
| Both (squashed) | `feat: Flame Graph Context Management System` |

---

## 5. Steps to Save Progress to Git (Remote)

### 5.1 Flame Repository (No Remote Exists)

Since `/Users/sl/code/flame/` is not a git repository and has no remote, you need to:

**Option A: Create a new repository (personal/organization)**

```bash
cd /Users/sl/code/flame

# Initialize git (if not done)
git init
git add .
git commit -m "feat: Flame Graph Context Management Plugin (Phase 1.7)"

# Add your remote (replace with your actual repo URL)
git remote add origin git@github.com:YOUR_USERNAME/flame.git
# or
git remote add origin https://github.com/YOUR_USERNAME/flame.git

# Push
git push -u origin main
```

**Option B: Push to GitHub (create repo first)**

```bash
# Create repo via GitHub CLI (if installed)
gh repo create flame --private --source=. --push
```

### 5.2 OpenCode Repository (Fork Recommended)

The OpenCode repo points to `git@github.com:sst/opencode.git`. To push without a PR to upstream:

**Option A: Push to a personal fork**

```bash
cd /Users/sl/code/opencode

# 1. Fork sst/opencode on GitHub first (via web or gh cli)
gh repo fork sst/opencode --clone=false

# 2. Add your fork as a remote
git remote add fork git@github.com:YOUR_USERNAME/opencode.git

# 3. Push your feature branch
git push -u fork feature/flame-graph-ui
```

**Option B: Push to origin (if you have write access)**

```bash
cd /Users/sl/code/opencode

# Push to a branch (not main/dev)
git push -u origin feature/flame-graph-ui
```

### Current Remote Configuration

| Repository | Remote | URL |
|------------|--------|-----|
| flame | none | Not initialized |
| opencode | origin | git@github.com:sst/opencode.git |

---

## 6. Steps to Publish the Flame Plugin

### 6.1 OpenCode Plugin Distribution Model

OpenCode plugins are distributed via:

1. **Local installation** (current approach) - `.opencode/plugin/` directory
2. **GitHub repositories** - Listed in the ecosystem documentation
3. **Community collections** - [awesome-opencode](https://github.com/awesome-opencode/awesome-opencode)

**There is no centralized plugin marketplace/registry.** Plugins are shared as:
- Git repositories
- NPM packages (optional)
- Direct file copies

### 6.2 Publishing as a GitHub Repository

```bash
# 1. Create a dedicated plugin repo structure
mkdir flame-plugin
cd flame-plugin

# 2. Copy plugin files
cp /Users/sl/code/flame/.opencode/plugin/flame.ts .
cp /Users/sl/code/flame/.opencode/package.json .

# 3. Add documentation
# Create README.md with installation instructions

# 4. Initialize and push
git init
git add .
git commit -m "Initial release: Flame Graph Context Management Plugin"
git remote add origin git@github.com:YOUR_USERNAME/flame-plugin.git
git push -u origin main
```

### 6.3 Plugin Installation for Users

Users install your plugin by:

```bash
# Clone to .opencode/plugin
git clone https://github.com/YOUR_USERNAME/flame-plugin ~/.config/opencode/plugin/flame-plugin

# Or for project-specific
git clone https://github.com/YOUR_USERNAME/flame-plugin .opencode/plugin/flame-plugin
```

### 6.4 Publishing to NPM (Optional)

```bash
# Update package.json with proper metadata
{
  "name": "@your-scope/flame-plugin",
  "version": "1.0.0",
  "description": "Flame Graph Context Management for OpenCode",
  "main": "flame.ts",
  "dependencies": {
    "@opencode-ai/plugin": "^1.0.193"
  }
}

# Publish
npm publish --access public
```

### 6.5 Getting Listed in Ecosystem

Submit a PR to add your plugin to:
- `/Users/sl/code/opencode/packages/web/src/content/docs/ecosystem.mdx`

Example entry:
```markdown
| [flame-plugin](https://github.com/YOUR_USERNAME/flame-plugin) | Tree-structured context management for AI agents |
```

---

## 7. Blockers and Issues

### 7.1 Critical

| Issue | Impact | Resolution |
|-------|--------|------------|
| Flame repo not git-initialized | Cannot save progress | Run `git init` in `/Users/sl/code/flame/` |
| No remote for flame repo | Cannot push to remote | Create GitHub repo and add remote |

### 7.2 Important

| Issue | Impact | Resolution |
|-------|--------|------------|
| OpenCode changes uncommitted | Risk of losing work | Commit to feature branch |
| No fork of OpenCode | Cannot push without upstream PR | Fork repo first |

### 7.3 Recommendations

1. **Separate Plugin from UI:** The flame plugin should be in its own repository for independent distribution. The UI requires changes to OpenCode core and may need a PR to upstream.

2. **Version Sync:** Keep plugin version in sync with OpenCode version requirements (`@opencode-ai/plugin": "1.0.193"`).

3. **Documentation:** Create a README.md for the plugin with:
   - Installation instructions
   - Configuration options
   - Available tools/commands
   - Examples

4. **Testing:** Add tests for the plugin (currently only UI tests exist).

---

## 8. Quick Reference Commands

```bash
# ===== FLAME REPOSITORY =====

# Initialize git
cd /Users/sl/code/flame
git init && git add . && git commit -m "Initial commit"

# Add remote and push
git remote add origin git@github.com:YOUR_USERNAME/flame.git
git push -u origin main


# ===== OPENCODE REPOSITORY =====

# Create feature branch and commit
cd /Users/sl/code/opencode
git checkout -b feature/flame-graph-ui
git add packages/app/src/components/flame/
git add packages/app/src/context/layout.tsx
git add packages/opencode/src/server/server.ts
git add packages/app/package.json bun.lock
git commit -m "feat: Add Flame Graph UI for context management"

# Fork and push (without PR to upstream)
gh repo fork sst/opencode --clone=false
git remote add fork git@github.com:YOUR_USERNAME/opencode.git
git push -u fork feature/flame-graph-ui


# ===== RUN LOCALLY =====

# Run OpenCode with flame plugin
cd /Users/sl/code/opencode
bun install
bun dev

# Test in flame project
cd /Users/sl/code/flame
opencode  # plugin auto-loads from .opencode/plugin/
```

---

## 9. File Inventory

### Plugin Files (`/Users/sl/code/flame/`)

```
.opencode/
├── plugin/
│   ├── flame.ts              # Main plugin (5,071 lines)
│   └── flame-validation.ts   # Validation plugin (561 lines)
├── flame/
│   ├── state.json           # Runtime state
│   ├── validation-state.json
│   ├── validation-log.json
│   └── frames/              # Frame storage
├── package.json             # Dependencies
├── bun.lock
└── node_modules/            # @opencode-ai/plugin, zod
```

### UI Files (`/Users/sl/code/opencode/packages/app/src/components/flame/`)

```
flame/
├── FlamePanel.tsx           # Main panel component
├── FlameGraph.tsx           # D3-based graph
├── FlameProvider.tsx        # Context provider
├── ContextMenu.tsx          # Right-click menu
├── FrameRect.tsx            # Individual frame
├── Tooltip.tsx              # Hover info
├── Connection.tsx           # Frame connections
├── ConnectionStatus.tsx     # Status indicator
├── SearchBar.tsx            # Frame search
├── FilterDropdown.tsx       # Status filters
├── ZoomControls.tsx         # Zoom +/-
├── Legend.tsx               # Status legend
├── LoadingStates.tsx        # Loading UI
├── ErrorBoundary.tsx        # Error handling
├── index.tsx                # Exports
├── types.ts                 # TypeScript types
├── constants.ts             # Config values
├── styles.css               # Component styles
├── dialogs/
│   ├── PushFrame.tsx
│   ├── PopFrame.tsx
│   ├── PlanChildren.tsx
│   ├── InvalidateFrame.tsx
│   ├── EditGoal.tsx
│   └── index.tsx
├── FrameDetails/
│   ├── Header.tsx
│   ├── Summary.tsx
│   ├── Artifacts.tsx
│   ├── Decisions.tsx
│   └── index.tsx
├── hooks/
│   ├── useAnimation.ts
│   ├── useFlameEvents.ts
│   ├── useKeyboard.ts
│   ├── useLayout.ts
│   └── useZoom.ts
├── utils/
│   ├── api.ts
│   └── tree.ts
└── __tests__/
    └── flame.test.ts
```

---

*This document was generated to help track the development status of the Flame Graph Context Management system.*
