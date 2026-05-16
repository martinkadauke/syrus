import { Controller } from "@hotwired/stimulus"

// Composable-filter chip bar.
//
// Owns the JSON-encoded AST tree (Stimulus value), renders one
// element per top-level AND child, and exposes an add-filter
// popover backed by Filters::Schema. Clicks on a chip route to a
// per-bucket editor that mutates the tree and submits the form
// with ?q=<encoded>.
//
// Tree shape supported here:
//   - top-level AND of flat chips
//   - OR sub-groups containing 2+ flat chips
//
// NOT wrappers are still rendered as a read-only "complex filter"
// badge — added in a follow-up commit.
//
// Chip addressing: paths are arrays. `[i]` = top-level i'th child.
// `[i, j]` = j'th child of the i'th top-level OR group. We pass
// paths through DOM via JSON strings on `data-chip-path`.
export default class extends Controller {
  static targets = [
    "form", "qInput", "chips", "addButton", "addMenu", "addSearch", "addList", "editor"
  ]
  static values = {
    tree: Object,
    schema: Array,
    submitUrl: String
  }

  connect() {
    this.editingChipPath = null
    this.pendingAddTarget = null  // null = top-level AND; { path } = append to OR group at path
    this.renderChips()
    document.addEventListener("click", this.handleDocumentClick)
  }

  disconnect() {
    document.removeEventListener("click", this.handleDocumentClick)
  }

  handleDocumentClick = (event) => {
    if (this.element.contains(event.target)) return
    this.closePopovers()
  }

  // ---- AST helpers ----

  topChildren() {
    const tree = this.treeValue || {}
    return Array.isArray(tree.and) ? tree.and : []
  }

  setTopChildren(children) {
    this.treeValue = { and: children }
    this.syncQInput()
    this.renderChips()
  }

  // Returns the node at `path`. Path semantics defined at top of file.
  nodeAtPath(path) {
    if (!Array.isArray(path) || path.length === 0) return null
    const top = this.topChildren()[path[0]]
    if (path.length === 1) return top
    if (!top || !Array.isArray(top.or)) return null
    return top.or[path[1]]
  }

  // Replace the node at `path`. If replacing inside an OR group leaves
  // it with a single child, auto-flatten back to a bare chip.
  replaceNodeAtPath(path, node) {
    const children = this.topChildren().slice()
    if (path.length === 1) {
      children[path[0]] = node
    } else {
      const group = children[path[0]]
      if (!group || !Array.isArray(group.or)) return
      const newOr = group.or.slice()
      newOr[path[1]] = node
      children[path[0]] = { or: newOr }
    }
    this.setTopChildren(children)
  }

  // Delete the node at `path`. Auto-flattens singleton OR groups and
  // removes empty OR groups.
  removeNodeAtPath(path) {
    const children = this.topChildren().slice()
    if (path.length === 1) {
      children.splice(path[0], 1)
    } else {
      const group = children[path[0]]
      if (!group || !Array.isArray(group.or)) return
      const newOr = group.or.slice()
      newOr.splice(path[1], 1)
      if (newOr.length === 0) {
        children.splice(path[0], 1)
      } else if (newOr.length === 1) {
        children[path[0]] = newOr[0]  // collapse singleton back to a flat chip
      } else {
        children[path[0]] = { or: newOr }
      }
    }
    this.setTopChildren(children)
  }

  // Wrap the flat chip at `path` (length 1) into an OR group so the
  // operator can append alternatives.
  wrapInOrGroup(path) {
    if (path.length !== 1) return path
    const children = this.topChildren().slice()
    const existing = children[path[0]]
    if (!existing || !("field" in existing)) return path
    children[path[0]] = { or: [ existing ] }
    this.setTopChildren(children)
    return [ path[0], 0 ]
  }

  syncQInput() {
    this.qInputTarget.value = encodeTree(this.treeValue)
  }

  submitForm() {
    this.formTarget.requestSubmit()
  }

  // ---- Chip rendering ----

  renderChips() {
    const children = this.topChildren()
    const elements = []
    children.forEach((node, i) => {
      if (i > 0) elements.push(separator("and"))
      elements.push(this.topElement(node, i))
    })
    this.chipsTarget.replaceChildren(...elements)
  }

  topElement(node, index) {
    if (node && typeof node === "object" && "field" in node) {
      return this.flatChipElement(node, [ index ])
    }
    if (node && typeof node === "object" && Array.isArray(node.or)) {
      return this.orGroupElement(node, index)
    }
    return this.complexBadgeElement(node, [ index ])
  }

  flatChipElement(chip, path) {
    const meta = this.metaFor(chip.field)
    const wrapper = document.createElement("span")
    wrapper.className = "inline-flex items-center gap-1 rounded-md border border-gray-300 bg-gray-50 px-2 py-1 text-sm hover:bg-gray-100"

    const editLink = document.createElement("button")
    editLink.type = "button"
    editLink.className = "inline-flex items-baseline gap-1 cursor-pointer"
    editLink.dataset.action = "click->chip-bar#editChip"
    editLink.dataset.chipPath = JSON.stringify(path)
    editLink.append(
      labelSpan(meta ? meta.label : chip.field),
      opSpan(chip.op),
      valueSpan(chip, meta)
    )

    const removeButton = document.createElement("button")
    removeButton.type = "button"
    removeButton.className = "ml-1 text-gray-400 hover:text-gray-700 cursor-pointer"
    removeButton.textContent = "×"
    removeButton.setAttribute("aria-label", `Remove ${meta ? meta.label : chip.field} filter`)
    removeButton.dataset.action = "click->chip-bar#removeChip"
    removeButton.dataset.chipPath = JSON.stringify(path)

    wrapper.append(editLink, removeButton)
    return wrapper
  }

  orGroupElement(orNode, index) {
    const wrapper = document.createElement("span")
    wrapper.className = "inline-flex items-center gap-1 rounded-md border border-indigo-300 bg-indigo-50 px-1.5 py-0.5 text-sm"

    const opening = document.createElement("span")
    opening.className = "text-xs font-semibold text-indigo-700"
    opening.textContent = "("
    wrapper.append(opening)

    orNode.or.forEach((child, j) => {
      if (j > 0) wrapper.append(separator("or"))
      const childPath = [ index, j ]
      if (child && typeof child === "object" && "field" in child) {
        wrapper.append(this.flatChipElement(child, childPath))
      } else {
        wrapper.append(this.complexBadgeElement(child, childPath))
      }
    })

    const addAlt = document.createElement("button")
    addAlt.type = "button"
    addAlt.className = "ml-1 inline-flex items-center rounded border border-dashed border-indigo-400 px-1.5 py-0.5 text-xs font-medium text-indigo-700 hover:bg-indigo-100 cursor-pointer"
    addAlt.textContent = "+ or"
    addAlt.dataset.action = "click->chip-bar#openAddMenuForOrGroup"
    addAlt.dataset.chipPath = JSON.stringify([ index ])
    wrapper.append(addAlt)

    const closing = document.createElement("span")
    closing.className = "text-xs font-semibold text-indigo-700"
    closing.textContent = ")"
    wrapper.append(closing)

    return wrapper
  }

  complexBadgeElement(node, path) {
    const wrapper = document.createElement("span")
    wrapper.className = "inline-flex items-center gap-1 rounded-md border border-amber-300 bg-amber-50 px-2 py-1 text-sm text-amber-800"
    wrapper.title = JSON.stringify(node)
    wrapper.textContent = node && node.not ? "NOT group" : "complex filter"

    const removeButton = document.createElement("button")
    removeButton.type = "button"
    removeButton.className = "ml-1 text-amber-600 hover:text-amber-900 cursor-pointer"
    removeButton.textContent = "×"
    removeButton.dataset.action = "click->chip-bar#removeChip"
    removeButton.dataset.chipPath = JSON.stringify(path)
    wrapper.append(removeButton)
    return wrapper
  }

  metaFor(field) {
    return (this.schemaValue || []).find(meta => meta.field === field)
  }

  // ---- Chip mutations ----

  removeChip(event) {
    const path = JSON.parse(event.currentTarget.dataset.chipPath)
    this.removeNodeAtPath(path)
    this.submitForm()
  }

  clearAll() {
    this.setTopChildren([])
    this.submitForm()
  }

  // ---- Add-filter popover ----

  // Default add: append a new chip at the top level (AND).
  openAddMenu(event) {
    this.pendingAddTarget = null
    this.closePopovers()
    this.positionPopover(this.addMenuTarget, event.currentTarget)
    this.populateAddMenu("")
    this.addMenuTarget.classList.remove("hidden")
    this.addSearchTarget.value = ""
    this.addSearchTarget.focus()
  }

  // Open the add menu in "append to OR group" mode. The button passes
  // the OR group's top-level path; the next addChip will append into
  // that group instead of the AND root.
  openAddMenuForOrGroup(event) {
    const path = JSON.parse(event.currentTarget.dataset.chipPath)
    this.pendingAddTarget = { kind: "or_group", path }
    this.closePopovers()
    this.positionPopover(this.addMenuTarget, event.currentTarget)
    this.populateAddMenu("")
    this.addMenuTarget.classList.remove("hidden")
    this.addSearchTarget.value = ""
    this.addSearchTarget.focus()
  }

  filterAddMenu() {
    this.populateAddMenu(this.addSearchTarget.value)
  }

  addMenuKeydown(event) {
    if (event.key !== "Enter") return
    event.preventDefault()
    const first = this.addListTarget.querySelector("button")
    if (first) first.click()
  }

  populateAddMenu(query) {
    const q = query.trim().toLowerCase()
    const items = (this.schemaValue || []).filter(meta => {
      if (!q) return true
      return meta.field.toLowerCase().includes(q) || meta.label.toLowerCase().includes(q)
    })

    this.addListTarget.replaceChildren(...items.map(meta => {
      const button = document.createElement("button")
      button.type = "button"
      button.className = "flex w-full items-center justify-between gap-2 px-3 py-2 text-left text-sm hover:bg-gray-50 cursor-pointer"
      button.dataset.action = "click->chip-bar#addChip"
      button.dataset.field = meta.field
      const label = document.createElement("span")
      label.textContent = meta.label
      const bucket = document.createElement("span")
      bucket.className = "text-xs text-gray-400"
      bucket.textContent = meta.bucket
      button.append(label, bucket)
      return button
    }))
  }

  addChip(event) {
    const field = event.currentTarget.dataset.field
    const meta = this.metaFor(field)
    if (!meta) return

    const defaults = defaultsFor(meta)
    const newChip = { field, op: defaults.op, value: defaults.value }

    let newPath
    if (this.pendingAddTarget && this.pendingAddTarget.kind === "or_group") {
      const groupIndex = this.pendingAddTarget.path[0]
      const children = this.topChildren().slice()
      const group = children[groupIndex]
      if (!group || !Array.isArray(group.or)) return
      const newOr = group.or.concat([ newChip ])
      children[groupIndex] = { or: newOr }
      this.setTopChildren(children)
      newPath = [ groupIndex, newOr.length - 1 ]
    } else {
      const children = this.topChildren().slice()
      children.push(newChip)
      this.setTopChildren(children)
      newPath = [ children.length - 1 ]
    }

    this.pendingAddTarget = null
    this.closePopovers()
    this.openEditorForPath(newPath)
  }

  // ---- Per-chip editor popover ----

  editChip(event) {
    const path = JSON.parse(event.currentTarget.dataset.chipPath)
    this.openEditorForPath(path)
  }

  openEditorForPath(path) {
    const chip = this.nodeAtPath(path)
    if (!chip || !("field" in chip)) return
    const meta = this.metaFor(chip.field)
    if (!meta) return

    this.editingChipPath = path
    this.editorTarget.replaceChildren(this.editorContent(chip, meta, path))

    const anchor = this.chipsTarget.querySelector(`[data-chip-path='${JSON.stringify(path)}']`) || this.addButtonTarget
    this.positionPopover(this.editorTarget, anchor)
    this.editorTarget.classList.remove("hidden")
  }

  editorContent(chip, meta, path) {
    const root = document.createElement("div")
    root.className = "p-3 space-y-3 min-w-[14rem]"

    const header = document.createElement("div")
    header.className = "text-xs font-semibold uppercase tracking-wide text-gray-500"
    header.textContent = meta.label
    root.append(header)

    if (meta.operators.length > 1) {
      const opSelect = document.createElement("select")
      opSelect.className = "block w-full rounded-md border border-gray-300 px-2 py-1.5 text-sm"
      opSelect.dataset.action = "change->chip-bar#updateChipOp"
      meta.operators.forEach(op => {
        const option = document.createElement("option")
        option.value = op
        option.textContent = humanizeOp(op)
        if (op === chip.op) option.selected = true
        opSelect.append(option)
      })
      root.append(opSelect)
    }

    const valueEditor = this.valueEditorFor(chip, meta)
    if (valueEditor) root.append(valueEditor)

    const footer = document.createElement("div")
    footer.className = "flex items-center justify-between gap-2 pt-1"

    // Add OR alternative: visible on flat chips (length-1 path) AND
    // on chips already inside an OR group (length-2 path). For flat
    // chips, applying wraps in an OR group first; for grouped chips,
    // it appends an alternative directly to the existing group.
    const addOr = document.createElement("button")
    addOr.type = "button"
    addOr.className = "rounded-md border border-indigo-300 px-2 py-1 text-xs font-medium text-indigo-700 hover:bg-indigo-50 cursor-pointer"
    addOr.textContent = "+ OR alternative"
    addOr.dataset.action = "click->chip-bar#addOrAlternativeFromEditor"
    footer.append(addOr)

    const done = document.createElement("button")
    done.type = "button"
    done.className = "rounded-md bg-blue-600 px-3 py-1.5 text-sm font-medium text-white hover:bg-blue-500 cursor-pointer"
    done.textContent = "Done"
    done.dataset.action = "click->chip-bar#applyEditor"
    footer.append(done)

    root.append(footer)

    return root
  }

  valueEditorFor(chip, meta) {
    if (isPredicateOp(chip.op)) return null

    switch (meta.bucket) {
      case "enum":
      case "fk":
      case "preset":
        return enumEditor(chip, meta)
      case "boolean":
        return null
      case "string":
        return stringEditor(chip)
      case "number":
        return numberEditor(chip)
      case "date":
        return dateEditor(chip)
      case "collection":
        return collectionEditor(chip, meta)
      default:
        return stringEditor(chip)
    }
  }

  applyEditor() {
    if (this.editingChipPath === null) return
    const current = this.nodeAtPath(this.editingChipPath)
    if (!current) return

    const opSelect = this.editorTarget.querySelector("select[data-action*='updateChipOp']")
    const updated = { ...current }
    if (opSelect) updated.op = opSelect.value
    updated.value = readEditorValue(this.editorTarget, updated.op)

    this.replaceNodeAtPath(this.editingChipPath, updated)
    this.closePopovers()
    this.submitForm()
  }

  // Apply current edits, then either wrap the chip in a fresh OR
  // group (if it's a flat top-level chip) or address the existing
  // OR group, and open the add menu for the alternative.
  addOrAlternativeFromEditor() {
    if (this.editingChipPath === null) return
    const current = this.nodeAtPath(this.editingChipPath)
    if (!current) return

    const opSelect = this.editorTarget.querySelector("select[data-action*='updateChipOp']")
    const updated = { ...current }
    if (opSelect) updated.op = opSelect.value
    updated.value = readEditorValue(this.editorTarget, updated.op)
    this.replaceNodeAtPath(this.editingChipPath, updated)

    let groupTopPath
    if (this.editingChipPath.length === 1) {
      const newPath = this.wrapInOrGroup(this.editingChipPath)
      groupTopPath = [ newPath[0] ]
    } else {
      groupTopPath = [ this.editingChipPath[0] ]
    }

    this.editorTarget.classList.add("hidden")
    this.editingChipPath = null
    this.pendingAddTarget = { kind: "or_group", path: groupTopPath }

    const anchor = this.chipsTarget.querySelector(`[data-chip-path='${JSON.stringify(groupTopPath)}']`)
      || this.chipsTarget.children[groupTopPath[0]]
      || this.addButtonTarget
    this.positionPopover(this.addMenuTarget, anchor)
    this.populateAddMenu("")
    this.addMenuTarget.classList.remove("hidden")
    this.addSearchTarget.value = ""
    this.addSearchTarget.focus()
  }

  updateChipOp(event) {
    if (this.editingChipPath === null) return
    const newOp = event.currentTarget.value
    const current = this.nodeAtPath(this.editingChipPath)
    if (!current) return
    this.replaceNodeAtPath(this.editingChipPath, { ...current, op: newOp, value: null })
    this.openEditorForPath(this.editingChipPath)
  }

  closePopovers() {
    this.addMenuTarget.classList.add("hidden")
    this.editorTarget.classList.add("hidden")
    this.editingChipPath = null
    this.pendingAddTarget = null
  }

  positionPopover(popover, anchor) {
    const containerRect = this.element.getBoundingClientRect()
    const anchorRect = anchor.getBoundingClientRect()
    popover.style.position = "absolute"
    popover.style.top = `${anchorRect.bottom - containerRect.top + 4}px`
    popover.style.left = `${anchorRect.left - containerRect.left}px`
  }
}

// ---- Pure helpers (kept at module scope for testability) ----

function defaultsFor(meta) {
  if (meta.operators.includes("is_true")) return { op: "is_true", value: null }
  if (meta.bucket === "collection") return { op: "contains_any", value: [] }
  if (meta.bucket === "date") return { op: "within_last", value: { n: 7, unit: "days" } }
  if (meta.bucket === "number") return { op: "equals", value: null }
  return { op: meta.operators[0] || "is", value: null }
}

function isPredicateOp(op) {
  return [ "is_true", "is_false", "is_set", "is_unset", "is_empty", "is_not_empty" ].includes(op)
}

function humanizeOp(op) {
  return op.replace(/_/g, " ")
}

function encodeTree(tree) {
  const json = JSON.stringify(tree || { and: [] })
  return btoa(unescape(encodeURIComponent(json)))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "")
}

function separator(kind) {
  const span = document.createElement("span")
  span.className = kind === "or"
    ? "text-xs font-semibold uppercase tracking-wide text-indigo-600"
    : "text-xs font-semibold uppercase tracking-wide text-gray-400"
  span.textContent = kind
  return span
}

function labelSpan(text) {
  const span = document.createElement("span")
  span.className = "font-medium text-gray-700"
  span.textContent = text
  return span
}

function opSpan(op) {
  const span = document.createElement("span")
  span.className = "text-xs text-gray-500"
  span.textContent = humanizeOp(op)
  return span
}

function valueSpan(chip, meta) {
  const span = document.createElement("span")
  span.className = "font-mono text-gray-900"
  span.textContent = formatChipValue(chip, meta)
  return span
}

function formatChipValue(chip, meta) {
  if (isPredicateOp(chip.op)) return ""
  if (chip.value === null || chip.value === undefined) return "(unset)"
  if (Array.isArray(chip.value)) return chip.value.map(v => labelForOption(v, meta)).join(", ")
  if (typeof chip.value === "object") return JSON.stringify(chip.value)
  return labelForOption(chip.value, meta)
}

function labelForOption(value, meta) {
  if (!meta || !Array.isArray(meta.values)) return String(value)
  const match = meta.values.find(v => (typeof v === "object" ? v.value === value : v === value))
  if (!match) return String(value)
  return typeof match === "object" ? match.label : match
}

// ---- Per-bucket value editors ----

function enumEditor(chip, meta) {
  const wrapper = document.createElement("div")
  const multi = [ "is_one_of", "is_none_of", "contains_any", "contains_all", "contains_none" ].includes(chip.op)
  const select = document.createElement("select")
  select.className = "block w-full rounded-md border border-gray-300 px-2 py-1.5 text-sm"
  select.dataset.chipBarTarget = "editorInput"
  if (multi) {
    select.multiple = true
    select.size = Math.min(Math.max(meta.values.length, 2), 6)
  }

  const currentValues = multi ? Array(chip.value || []).flat() : [ chip.value ]
  meta.values.forEach(v => {
    const option = document.createElement("option")
    const val = typeof v === "object" ? v.value : v
    const label = typeof v === "object" ? v.label : v
    option.value = val
    option.textContent = label
    if (currentValues.some(curr => String(curr) === String(val))) option.selected = true
    select.append(option)
  })

  wrapper.append(select)
  return wrapper
}

function stringEditor(chip) {
  const input = document.createElement("input")
  input.type = "text"
  input.value = chip.value ?? ""
  input.placeholder = "value"
  input.className = "block w-full rounded-md border border-gray-300 px-2 py-1.5 text-sm"
  input.dataset.chipBarTarget = "editorInput"
  return input
}

function numberEditor(chip) {
  if (chip.op === "between") {
    const wrapper = document.createElement("div")
    wrapper.className = "flex items-center gap-2"
    const range = Array.isArray(chip.value) ? chip.value : []
    wrapper.append(numberInput(range[0], "min"), numberInput(range[1], "max"))
    return wrapper
  }
  return numberInput(chip.value, "value")
}

function numberInput(value, placeholder) {
  const input = document.createElement("input")
  input.type = "number"
  input.value = value ?? ""
  input.placeholder = placeholder
  input.className = "block w-full rounded-md border border-gray-300 px-2 py-1.5 text-sm"
  input.dataset.chipBarTarget = "editorInput"
  return input
}

function dateEditor(chip) {
  if (chip.op === "within_last" || chip.op === "more_than_ago") {
    const wrapper = document.createElement("div")
    wrapper.className = "flex items-center gap-2"
    const spec = chip.value && typeof chip.value === "object" ? chip.value : {}
    const nInput = document.createElement("input")
    nInput.type = "number"
    nInput.min = "0"
    nInput.value = spec.n ?? 7
    nInput.className = "block w-20 rounded-md border border-gray-300 px-2 py-1.5 text-sm"
    nInput.dataset.chipBarTarget = "editorInput"
    nInput.dataset.role = "n"

    const unitSelect = document.createElement("select")
    unitSelect.className = "block w-full rounded-md border border-gray-300 px-2 py-1.5 text-sm"
    unitSelect.dataset.chipBarTarget = "editorInput"
    unitSelect.dataset.role = "unit";
    [ "minutes", "hours", "days", "weeks", "months" ].forEach(unit => {
      const option = document.createElement("option")
      option.value = unit
      option.textContent = unit
      if ((spec.unit || "days") === unit) option.selected = true
      unitSelect.append(option)
    })
    wrapper.append(nInput, unitSelect)
    return wrapper
  }

  if (chip.op === "between") {
    const wrapper = document.createElement("div")
    wrapper.className = "flex items-center gap-2"
    const range = Array.isArray(chip.value) ? chip.value : []
    wrapper.append(dateInput(range[0]), dateInput(range[1]))
    return wrapper
  }

  return dateInput(chip.value)
}

function dateInput(value) {
  const input = document.createElement("input")
  input.type = "date"
  input.value = value ? String(value).slice(0, 10) : ""
  input.className = "block w-full rounded-md border border-gray-300 px-2 py-1.5 text-sm"
  input.dataset.chipBarTarget = "editorInput"
  return input
}

function collectionEditor(chip, meta) {
  if (!Array.isArray(meta.values) || meta.values.length === 0) {
    const input = document.createElement("input")
    input.type = "text"
    input.value = Array.isArray(chip.value) ? chip.value.join(",") : (chip.value || "")
    input.placeholder = "comma-separated ids"
    input.className = "block w-full rounded-md border border-gray-300 px-2 py-1.5 text-sm"
    input.dataset.chipBarTarget = "editorInput"
    input.dataset.role = "csv"
    return input
  }
  return enumEditor(chip, meta)
}

function readEditorValue(editor, op) {
  if (isPredicateOp(op)) return null

  const inputs = editor.querySelectorAll('[data-chip-bar-target="editorInput"]')
  if (inputs.length === 0) return null

  const nInput = editor.querySelector('[data-role="n"]')
  const unitSelect = editor.querySelector('[data-role="unit"]')
  if (nInput && unitSelect) {
    return { n: Number(nInput.value || 0), unit: unitSelect.value }
  }

  const csvInput = editor.querySelector('[data-role="csv"]')
  if (csvInput) {
    return csvInput.value.split(",").map(s => s.trim()).filter(Boolean)
  }

  if (inputs.length === 1) {
    const input = inputs[0]
    if (input.tagName === "SELECT" && input.multiple) {
      return Array.from(input.selectedOptions).map(o => o.value)
    }
    if (input.type === "number") {
      const num = Number(input.value)
      return Number.isFinite(num) && input.value !== "" ? num : null
    }
    return input.value === "" ? null : input.value
  }

  return Array.from(inputs).map(input => {
    if (input.type === "number") {
      const num = Number(input.value)
      return Number.isFinite(num) && input.value !== "" ? num : null
    }
    return input.value
  })
}
