// Coding-files tree type + builder extracted from Chat.tsx.
//
// FileTreeNode is the nested directory/file model the coding-files panel
// renders; buildFileTree turns a flat path list into that sorted tree
// (directories first, then name order). Pure — lifting the type here lets the
// FileTreeEntry / CodingFilesPanel components move out of Chat.tsx.

export type FileTreeNode = {
  name: string
  path: string
  type: "file" | "directory"
  children: FileTreeNode[]
}

export function buildFileTree(files: string[]): FileTreeNode[] {
  const nodeMap = new Map<string, FileTreeNode>()

  for (const filePath of files) {
    const parts = filePath.split("/")
    for (let i = 1; i < parts.length; i++) {
      const dirPath = parts.slice(0, i).join("/")
      if (!nodeMap.has(dirPath)) {
        nodeMap.set(dirPath, { name: parts[i - 1], path: dirPath, type: "directory", children: [] })
      }
    }
    nodeMap.set(filePath, { name: parts[parts.length - 1], path: filePath, type: "file", children: [] })
  }

  for (const [path, node] of nodeMap) {
    const parts = path.split("/")
    if (parts.length > 1) {
      const parentPath = parts.slice(0, -1).join("/")
      nodeMap.get(parentPath)?.children.push(node)
    }
  }

  function sortNodes(nodes: FileTreeNode[]): FileTreeNode[] {
    return [...nodes]
      .sort((a, b) => (a.type !== b.type ? (a.type === "directory" ? -1 : 1) : a.name.localeCompare(b.name)))
      .map((n) => ({ ...n, children: sortNodes(n.children) }))
  }

  const roots: FileTreeNode[] = []
  for (const [path, node] of nodeMap) {
    if (!path.includes("/")) roots.push(node)
  }
  return sortNodes(roots)
}
