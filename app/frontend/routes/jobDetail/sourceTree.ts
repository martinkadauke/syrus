// Source-browser tree types + builders extracted from JobDetail.tsx.
//
// The nested source tree model, the language->syntax-highlighter mapping, and
// the flat-tree-items -> sorted nested tree builder. Pure over the job source
// payload; lifting the types here lets the SourceTreeRow / source-browser
// components move out of the 3k-line JobDetail.tsx.
import type { JobSourcePayload } from "../../api/jobs"
import type { SyntaxLanguage } from "../../lib/syntaxHighlight"

export type SourceTreeFile = JobSourcePayload["tree_items"][number]
export type SourceFile = NonNullable<JobSourcePayload["file"]>
export type SourceTreeNode = {
  path: string
  name: string
  children: SourceTreeNode[]
  file: SourceTreeFile | null
}

export function sourceLanguage(language: SourceFile["language"]): SyntaxLanguage | null {
  const supported: SyntaxLanguage[] = [ "ruby", "javascript", "typescript", "json", "yaml", "shell", "css", "html" ]
  return supported.includes(language as SyntaxLanguage) ? (language as SyntaxLanguage) : null
}

export function buildSourceTree(items: SourceTreeFile[]) {
  const root: SourceTreeNode = { path: "", name: "", children: [], file: null }
  const directories = new Map<string, SourceTreeNode>([["", root]])

  for (const item of items) {
    const parts = item.path.split("/").filter(Boolean)
    let parent = root
    let currentPath = ""

    parts.forEach((part, index) => {
      currentPath = currentPath ? `${currentPath}/${part}` : part
      let node = directories.get(currentPath)

      if (!node) {
        node = { path: currentPath, name: part, children: [], file: null }
        directories.set(currentPath, node)
        parent.children.push(node)
      }

      if (index === parts.length - 1) node.file = item
      parent = node
    })
  }

  sortSourceTree(root)
  return root.children
}

export function sortSourceTree(node: SourceTreeNode) {
  node.children.sort((a, b) => {
    if (!!a.file !== !!b.file) return a.file ? 1 : -1
    return a.name.localeCompare(b.name)
  })
  node.children.forEach(sortSourceTree)
}
