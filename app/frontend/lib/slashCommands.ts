export type SlashCommandKind = "system" | "skill"

export type SlashCommandArg = {
  name: string
  required?: boolean
}

export type SlashCommand = {
  name: `/${string}`
  kind: SlashCommandKind
  args: SlashCommandArg[]
  description: string
  toPrompt?: (args: string) => string
  requiresConfirmation?: boolean
}

export type SlashCommandMatch = {
  command: SlashCommand
  token: string
  argsText: string
}

export const slashCommands = [
  { name: "/rename", kind: "system", args: [{ name: "title", required: true }], description: "Rename the current chat." },
  { name: "/clear", kind: "system", args: [], description: "Clear this chat's message history." },
  { name: "/new", kind: "system", args: [], description: "Start a new chat." },
  { name: "/bookmarks", kind: "system", args: [], description: "Show saved bookmarks in this chat." },
  { name: "/attach", kind: "system", args: [{ name: "owner/repo", required: false }], description: "Attach a repository or open attachment controls." },
  { name: "/settings", kind: "system", args: [], description: "Open chat settings." },
  {
    name: "/jobs",
    kind: "skill",
    args: [{ name: "filter", required: false }],
    description: "Ask the agent to inspect Jobs.",
    toPrompt: (args) => withOptionalArg(
      "Call the `list_jobs` MCP tool and return a compact status table with Job id, state, priority, PR or issue number, and title.",
      args,
      "Pass this operator filter through when choosing tool arguments"
    )
  },
  {
    name: "/job",
    kind: "skill",
    args: [{ name: "id", required: true }],
    description: "Ask the agent about one Job.",
    toPrompt: (args) => `Call the \`read_job\` MCP tool for Job id ${quotedArg(args)}. Summarize the Job state, PR or issue identifiers, priority, latest workflow state, and any latest workflow summary.`
  },
  {
    name: "/epic",
    kind: "skill",
    args: [{ name: "id", required: true }],
    description: "Ask the agent about an Epic.",
    toPrompt: (args) => `Call the \`read_epic\` MCP tool for Epic id ${quotedArg(args)}. Show the Epic state and a compact table of child Job statuses, including dependencies when present.`
  },
  {
    name: "/prs",
    kind: "skill",
    args: [],
    description: "Ask the agent to review open pull requests.",
    toPrompt: () => "Call the `list_open_prs` MCP tool and return a compact table of open pull requests with number, title, head branch, base branch, draft state, mergeability, and last update time."
  },
  {
    name: "/issues",
    kind: "skill",
    args: [],
    description: "Ask the agent to inspect open GitHub issues.",
    toPrompt: () => "Call the `list_open_issues` MCP tool and return a compact table of open GitHub issues with number, title, labels, author, creation time, and a short body excerpt when useful."
  },
  {
    name: "/proposals",
    kind: "skill",
    args: [],
    description: "Ask the agent to summarize proposed work.",
    toPrompt: () => "Call the `list_proposals` MCP tool and show the drafted proposal cards with status, scope, dependencies, and short summaries."
  },
  {
    name: "/canvas",
    kind: "skill",
    args: [],
    description: "Ask the agent to describe the whiteboard.",
    toPrompt: () => "Call the `read_scene` MCP tool and describe the current whiteboard contents, including notable shapes, text, connections, frames, and empty-state if there is nothing on the canvas."
  },
  {
    name: "/bookmark",
    kind: "skill",
    args: [{ name: "label", required: true }],
    description: "Ask the agent to bookmark context.",
    toPrompt: (args) => `Call the \`set_bookmark\` MCP tool with label ${quotedArg(args)} and kind "topic". Return a brief confirmation.`
  },
  { name: "/discard", kind: "skill", args: [{ name: "slug", required: true }], description: "Ask the agent to discard proposed work.", requiresConfirmation: true },
  { name: "/cancel", kind: "skill", args: [{ name: "id", required: true }], description: "Ask the agent to cancel work.", requiresConfirmation: true },
  { name: "/retry", kind: "skill", args: [{ name: "id", required: true }], description: "Ask the agent to retry failed work.", requiresConfirmation: true },
  { name: "/feedback", kind: "skill", args: [{ name: "id", required: true }], description: "Send feedback for the agent to address.", requiresConfirmation: true },
  { name: "/clear-canvas", kind: "skill", args: [], description: "Ask the agent to clear the whiteboard.", requiresConfirmation: true },
  {
    name: "/propose",
    kind: "skill",
    args: [],
    description: "Start a guided Job proposal wizard",
    toPrompt: proposeWizardPrompt
  }
] as const satisfies readonly SlashCommand[]

export const slashCommandPattern = /^\s*(\/[a-z]+(?:-[a-z]+)*)\b/i

export function slashCommandSignature(command: SlashCommand) {
  return command.args.map((arg) => arg.required ? `<${arg.name}>` : `[${arg.name}]`).join(" ")
}

export function findSlashCommand(text: string): SlashCommandMatch | null {
  const match = text.match(slashCommandPattern)
  if (!match) return null

  const token = match[1].toLowerCase()
  const command = slashCommands.find((item) => item.name === token)
  if (!command) return null

  return {
    command,
    token,
    argsText: text.slice(match[0].length).trim()
  }
}

export function slashCommandQuery(text: string) {
  const match = text.match(/^\s*\/([a-z-]*)$/i)
  return match ? match[1].toLowerCase() : null
}

export function filterSlashCommands(query: string) {
  return slashCommands
    .map((command, index) => ({ command, index, key: command.name.slice(1) }))
    .filter((item) => item.key.includes(query))
    .sort((left, right) => commandMatchRank(left.key, query) - commandMatchRank(right.key, query) || left.index - right.index)
    .map((item) => item.command)
}

export function slashCommandPrompt(text: string) {
  const match = findSlashCommand(text)
  if (!match || match.command.kind !== "skill" || !match.command.toPrompt) return text

  return match.command.toPrompt(match.argsText)
}

function commandMatchRank(commandName: string, query: string) {
  if (commandName === query) return 0
  if (commandName.startsWith(query)) return 1
  return 2
}

function withOptionalArg(prompt: string, args: string, label: string) {
  const trimmed = args.trim()
  if (!trimmed) return prompt

  return `${prompt} ${label}: ${quotedArg(trimmed)}.`
}

function quotedArg(value: string) {
  return JSON.stringify(value.trim())
}

function proposeWizardPrompt(args: string) {
  const trimmed = args.trim()
  const initialContext = trimmed.length > 0
    ? `\n\nThe operator included this initial context after the command:\n${trimmed}`
    : ""

  return `Start the guided Job proposal wizard.

Guide the operator through a natural back-and-forth conversation to draft one Job proposal. Ask for one missing detail at a time, in this order:

1. Job title
2. Job description
3. Optional Epic to attach it to; make it clear they can skip this

After you have enough information, call the propose_job tool to emit exactly one Job proposal card. Do not create a Job directly, and do not ask the operator to fill out a form.${initialContext}`
}
