/**
 * Flame Validation Plugin
 *
 * A minimal test plugin to validate key assumptions for Flame Graph Context Management.
 * This plugin validates:
 *
 * 1. Hook invocation timing - When do experimental transform hooks get called?
 * 2. Session ID access - How to get current session ID in transform hooks (empty input: {})
 * 3. Compaction output capture - Can we capture the generated summary via session.compacted event?
 * 4. File storage - Can we write to .opencode/flame/ from plugin context?
 * 5. Message prepend behavior - Do prepended synthetic messages appear in LLM calls and TUI?
 */

import type { Plugin } from "@opencode-ai/plugin"
import * as fs from "fs"
import * as path from "path"

// State tracking for validation
interface ValidationState {
  pluginInitTime: number
  hookInvocations: HookInvocation[]
  sessionEvents: SessionEvent[]
  currentSessionID: string | null
  messagesTransformCount: number
  systemTransformCount: number
  compactionEvents: CompactionEvent[]
  storageTestResult: StorageTestResult | null
}

interface HookInvocation {
  hook: string
  timestamp: number
  input: unknown
  output: unknown
  sessionID: string | null
  notes: string
}

interface SessionEvent {
  type: string
  timestamp: number
  sessionID: string
  parentID?: string
  title?: string
  details?: unknown
}

interface CompactionEvent {
  timestamp: number
  sessionID: string
  promptModified: boolean
  contextAdded: string[]
}

interface StorageTestResult {
  success: boolean
  path: string
  error?: string
  timestamp: number
}

// Global state
const state: ValidationState = {
  pluginInitTime: 0,
  hookInvocations: [],
  sessionEvents: [],
  currentSessionID: null,
  messagesTransformCount: 0,
  systemTransformCount: 0,
  compactionEvents: [],
  storageTestResult: null,
}

// Logging helper
function log(message: string, data?: unknown): void {
  const timestamp = new Date().toISOString()
  const entry = `[${timestamp}] [flame-validation] ${message}`
  console.log(entry, data !== undefined ? JSON.stringify(data, null, 2) : "")
}

// Get flame storage directory
function getFlameDir(projectDir: string): string {
  return path.join(projectDir, ".opencode", "flame")
}

// Test file storage capability
async function testStorage(projectDir: string): Promise<StorageTestResult> {
  const flameDir = getFlameDir(projectDir)
  const testFile = path.join(flameDir, "validation-log.json")

  try {
    // Ensure directory exists
    await fs.promises.mkdir(flameDir, { recursive: true })

    // Write test data
    const testData = {
      validationStarted: state.pluginInitTime,
      lastUpdated: Date.now(),
      hookInvocationCount: state.hookInvocations.length,
      sessionEventCount: state.sessionEvents.length,
      message: "Flame validation plugin storage test successful"
    }

    await fs.promises.writeFile(testFile, JSON.stringify(testData, null, 2))

    // Verify we can read it back
    const content = await fs.promises.readFile(testFile, "utf-8")
    const parsed = JSON.parse(content)

    if (parsed.message !== testData.message) {
      throw new Error("Read verification failed - content mismatch")
    }

    return {
      success: true,
      path: testFile,
      timestamp: Date.now()
    }
  } catch (error) {
    return {
      success: false,
      path: testFile,
      error: error instanceof Error ? error.message : String(error),
      timestamp: Date.now()
    }
  }
}

// Persist current validation state to disk
async function persistState(projectDir: string): Promise<void> {
  const flameDir = getFlameDir(projectDir)
  const stateFile = path.join(flameDir, "validation-state.json")

  try {
    await fs.promises.mkdir(flameDir, { recursive: true })
    await fs.promises.writeFile(stateFile, JSON.stringify(state, null, 2))
  } catch (error) {
    log("Failed to persist state", { error: error instanceof Error ? error.message : error })
  }
}

// Main plugin export
export const FlameValidation: Plugin = async (ctx) => {
  const { project, client, directory, worktree } = ctx

  state.pluginInitTime = Date.now()

  log("=== FLAME VALIDATION PLUGIN INITIALIZED ===")
  log("Plugin context received", {
    projectId: project.id,
    directory,
    worktree,
    initTime: new Date(state.pluginInitTime).toISOString()
  })

  // Test storage immediately on init
  state.storageTestResult = await testStorage(directory)
  log("Storage test result", state.storageTestResult)

  return {
    /**
     * Event hook - captures all session lifecycle events
     * This is our primary mechanism for tracking session IDs
     */
    event: async ({ event }) => {
      const timestamp = Date.now()

      // Track all session-related events
      if (event.type.startsWith("session.")) {
        const sessionEvent: SessionEvent = {
          type: event.type,
          timestamp,
          sessionID: "",
          details: event.properties
        }

        // Extract session info based on event type
        if (event.type === "session.created" && "info" in event.properties) {
          const info = event.properties.info as { id: string; parentID?: string; title?: string }
          sessionEvent.sessionID = info.id
          sessionEvent.parentID = info.parentID
          sessionEvent.title = info.title

          // Track current session for transform hooks
          state.currentSessionID = info.id

          log("SESSION CREATED", {
            sessionID: info.id,
            parentID: info.parentID,
            title: info.title,
            isChildSession: !!info.parentID
          })
        }

        if (event.type === "session.updated" && "info" in event.properties) {
          const info = event.properties.info as { id: string }
          sessionEvent.sessionID = info.id
          state.currentSessionID = info.id
        }

        if (event.type === "session.idle" && "sessionID" in event.properties) {
          sessionEvent.sessionID = event.properties.sessionID
          log("SESSION IDLE", { sessionID: event.properties.sessionID })
        }

        if (event.type === "session.compacted" && "sessionID" in event.properties) {
          sessionEvent.sessionID = event.properties.sessionID
          log("SESSION COMPACTED EVENT RECEIVED", {
            sessionID: event.properties.sessionID,
            timestamp: new Date(timestamp).toISOString(),
            note: "This event fires AFTER compaction is complete - summary should be available in messages"
          })

          // Try to fetch the session messages to find the compaction summary
          try {
            const messages = await client.session.messages({
              path: { id: event.properties.sessionID }
            })

            // Look for summary message
            const summaryMessage = messages.data?.find(
              (m: { info: { role: string; summary?: boolean } }) =>
                m.info.role === "assistant" && m.info.summary === true
            )

            if (summaryMessage) {
              log("COMPACTION SUMMARY FOUND", {
                messageId: summaryMessage.info.id,
                partsCount: summaryMessage.parts?.length,
                textContent: summaryMessage.parts?.find(
                  (p: { type: string }) => p.type === "text"
                )?.text?.substring(0, 200) + "..."
              })
            } else {
              log("COMPACTION SUMMARY NOT FOUND in messages", {
                messageCount: messages.data?.length
              })
            }
          } catch (error) {
            log("Failed to fetch messages for compaction analysis", {
              error: error instanceof Error ? error.message : error
            })
          }
        }

        if (event.type === "session.deleted" && "info" in event.properties) {
          const info = event.properties.info as { id: string }
          sessionEvent.sessionID = info.id
        }

        state.sessionEvents.push(sessionEvent)
        await persistState(directory)
      }

      // Also track message events to understand message flow
      if (event.type === "message.updated" && "info" in event.properties) {
        const info = event.properties.info as { id: string; sessionID: string; role: string; summary?: boolean }
        if (info.summary) {
          log("SUMMARY MESSAGE DETECTED via message.updated", {
            messageId: info.id,
            sessionID: info.sessionID,
            role: info.role
          })
        }
      }
    },

    /**
     * chat.message hook - receives sessionID in input
     * This hook fires when a new user message is created
     */
    "chat.message": async (input, output) => {
      const timestamp = Date.now()

      log("CHAT.MESSAGE HOOK INVOKED", {
        sessionID: input.sessionID,
        agent: input.agent,
        model: input.model,
        messageID: input.messageID,
        timestamp: new Date(timestamp).toISOString()
      })

      // Update current session ID
      state.currentSessionID = input.sessionID

      state.hookInvocations.push({
        hook: "chat.message",
        timestamp,
        input: {
          sessionID: input.sessionID,
          agent: input.agent,
          model: input.model,
          messageID: input.messageID
        },
        output: {
          messageRole: output.message.role,
          partsCount: output.parts.length
        },
        sessionID: input.sessionID,
        notes: "Receives sessionID - can track current session here"
      })

      await persistState(directory)
    },

    /**
     * experimental.chat.messages.transform hook
     * Called just before LLM invocation with all session messages
     * CRITICAL: input is {} - no sessionID available directly
     */
    "experimental.chat.messages.transform": async (input, output) => {
      const timestamp = Date.now()
      state.messagesTransformCount++

      const invocationNum = state.messagesTransformCount
      const trackedSessionID = state.currentSessionID

      log("=== MESSAGES TRANSFORM HOOK ===", {
        invocationNumber: invocationNum,
        timestamp: new Date(timestamp).toISOString(),
        inputKeys: Object.keys(input),
        inputIsEmpty: Object.keys(input).length === 0,
        trackedSessionID,
        messageCount: output.messages.length
      })

      // Log message structure for understanding
      if (output.messages.length > 0) {
        log("Message structure sample", {
          firstMessage: {
            role: output.messages[0].info.role,
            partsCount: output.messages[0].parts.length,
            partTypes: output.messages[0].parts.map((p: { type: string }) => p.type)
          },
          lastMessage: output.messages.length > 1 ? {
            role: output.messages[output.messages.length - 1].info.role,
            partsCount: output.messages[output.messages.length - 1].parts.length,
          } : "same as first"
        })
      }

      // TEST: Prepend a synthetic message to test visibility
      // This tests if prepended messages appear in LLM context and TUI
      const syntheticMessage = {
        info: {
          id: `flame-synthetic-${Date.now()}`,
          sessionID: trackedSessionID || "unknown",
          role: "user" as const,
          time: { created: timestamp },
          agent: "build",
          model: { providerID: "test", modelID: "test" },
          synthetic: true
        },
        parts: [
          {
            id: `flame-part-${Date.now()}`,
            sessionID: trackedSessionID || "unknown",
            messageID: `flame-synthetic-${Date.now()}`,
            type: "text" as const,
            text: `<flame-context validation="true" invocation="${invocationNum}">
This is a synthetic context message injected by Flame Validation Plugin.
Session ID (tracked): ${trackedSessionID || "unknown"}
Timestamp: ${new Date(timestamp).toISOString()}
Message count before injection: ${output.messages.length}
</flame-context>`,
            synthetic: true
          }
        ]
      }

      // Prepend the synthetic message
      output.messages.unshift(syntheticMessage as any)

      log("Synthetic message prepended", {
        newMessageCount: output.messages.length,
        syntheticId: syntheticMessage.info.id
      })

      state.hookInvocations.push({
        hook: "experimental.chat.messages.transform",
        timestamp,
        input: { ...input },
        output: {
          messageCountBefore: output.messages.length - 1,
          messageCountAfter: output.messages.length,
          syntheticPrepended: true
        },
        sessionID: trackedSessionID,
        notes: "Input is {} - sessionID not available directly. Using tracked sessionID from chat.message hook."
      })

      await persistState(directory)
    },

    /**
     * experimental.chat.system.transform hook
     * Called to transform the system prompt before LLM call
     * CRITICAL: input is {} - no sessionID available directly
     */
    "experimental.chat.system.transform": async (input, output) => {
      const timestamp = Date.now()
      state.systemTransformCount++

      const invocationNum = state.systemTransformCount
      const trackedSessionID = state.currentSessionID

      log("=== SYSTEM TRANSFORM HOOK ===", {
        invocationNumber: invocationNum,
        timestamp: new Date(timestamp).toISOString(),
        inputKeys: Object.keys(input),
        inputIsEmpty: Object.keys(input).length === 0,
        trackedSessionID,
        systemPartsCount: output.system.length
      })

      // Log system prompt structure
      if (output.system.length > 0) {
        log("System prompt structure", {
          partCount: output.system.length,
          firstPartPreview: output.system[0]?.substring(0, 100) + "...",
          totalLength: output.system.reduce((acc, s) => acc + s.length, 0)
        })
      }

      // Add a flame context marker to system prompt
      const flameSystemContext = `
<!-- Flame Validation Context -->
<!-- Session ID (tracked): ${trackedSessionID || "unknown"} -->
<!-- System transform invocation: ${invocationNum} -->
<!-- Timestamp: ${new Date(timestamp).toISOString()} -->
`

      output.system.push(flameSystemContext)

      state.hookInvocations.push({
        hook: "experimental.chat.system.transform",
        timestamp,
        input: { ...input },
        output: {
          systemPartsCount: output.system.length
        },
        sessionID: trackedSessionID,
        notes: "Input is {} - sessionID not available directly. Using tracked sessionID from chat.message hook."
      })

      await persistState(directory)
    },

    /**
     * experimental.session.compacting hook
     * Called before compaction LLM call - allows customizing the compaction prompt
     * CRITICAL: This hook DOES receive sessionID in input!
     */
    "experimental.session.compacting": async (input, output) => {
      const timestamp = Date.now()

      log("=== COMPACTING HOOK ===", {
        timestamp: new Date(timestamp).toISOString(),
        sessionID: input.sessionID,
        inputHasSessionID: "sessionID" in input,
        existingContext: output.context,
        existingPrompt: output.prompt
      })

      // Add custom context for frame-aware compaction
      const flameCompactionContext = `
## Flame Graph Context Management - Compaction Context

This session is being monitored by the Flame validation plugin.
Session ID: ${input.sessionID}
Compaction triggered at: ${new Date(timestamp).toISOString()}

Please preserve any frame-related context in your summary, including:
- Current task goals and status
- Key decisions made
- Artifacts created or modified
- Dependencies on other frames/sessions
`

      output.context.push(flameCompactionContext)

      state.compactionEvents.push({
        timestamp,
        sessionID: input.sessionID,
        promptModified: false,
        contextAdded: [flameCompactionContext.substring(0, 100) + "..."]
      })

      state.hookInvocations.push({
        hook: "experimental.session.compacting",
        timestamp,
        input: { sessionID: input.sessionID },
        output: {
          contextCount: output.context.length,
          hasCustomPrompt: !!output.prompt
        },
        sessionID: input.sessionID,
        notes: "This hook DOES receive sessionID in input - key difference from transform hooks!"
      })

      await persistState(directory)
    },

    /**
     * tool.execute.before hook - validates we can intercept tool calls
     * Useful for future frame context injection
     */
    "tool.execute.before": async (input, output) => {
      const timestamp = Date.now()

      // Only log occasionally to avoid spam
      if (input.tool === "read" || input.tool === "write" || input.tool === "bash") {
        log("TOOL EXECUTE (before)", {
          tool: input.tool,
          sessionID: input.sessionID,
          callID: input.callID,
          argsPreview: JSON.stringify(output.args).substring(0, 100)
        })
      }

      state.hookInvocations.push({
        hook: "tool.execute.before",
        timestamp,
        input: { tool: input.tool, sessionID: input.sessionID, callID: input.callID },
        output: { argsKeys: Object.keys(output.args) },
        sessionID: input.sessionID,
        notes: "Tool hooks receive sessionID - can be used for frame context tracking"
      })
    },

    /**
     * tool.execute.after hook - validates we can see tool results
     */
    "tool.execute.after": async (input, output) => {
      const timestamp = Date.now()

      // Only log occasionally to avoid spam
      if (input.tool === "read" || input.tool === "write" || input.tool === "bash") {
        log("TOOL EXECUTE (after)", {
          tool: input.tool,
          sessionID: input.sessionID,
          title: output.title,
          outputPreview: output.output?.substring(0, 50)
        })
      }

      state.hookInvocations.push({
        hook: "tool.execute.after",
        timestamp,
        input: { tool: input.tool, sessionID: input.sessionID, callID: input.callID },
        output: { title: output.title, hasOutput: !!output.output },
        sessionID: input.sessionID,
        notes: "Can capture tool results for frame activity logging"
      })
    }
  }
}

// Default export for OpenCode plugin system
export default FlameValidation
