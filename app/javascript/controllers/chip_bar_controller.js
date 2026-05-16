import { Controller } from "@hotwired/stimulus"

// Composable-filter chip bar.
//
// Owns the JSON-encoded AST tree (Stimulus value), renders one chip
// per top-level child, exposes an add-filter popover backed by the
// Filters::Schema metadata, and routes chip clicks to a per-bucket
// editor that mutates the tree and submits the form with ?q=<encoded>.
//
// The tree shape this commit handles is a flat AND-of-chips. OR
// groups and NOT wrappers are added in subsequent commits — for now
// any non-chip node in the tree is rendered as a read-only "complex
// filter" badge so user-defined smart folders with OR/NOT can still
// be displayed without crashing.
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
    this.editingChipIndex = null
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

  // Returns the array of top-level children. Treats a missing or
  // malformed root as an empty AND.
  topChildren() {
    const tree = this.treeValue || {}
    return Array.isArray(tree.and) ? tree.and : []
  }

  setTopChildren(children) {
    this.treeValue = { and: children }
    this.syncQInput()
    this.renderChips()
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
    this.chipsTarget.replaceChildren(...children.map((node, index) => this.chipElement(node, index)))
  }

  chipElement(node, index) {
    if (node && typeof node === "object" && "field" in node) return this.flatChipElement(node, index)
    return this.complexBadgeElement(node, index)
  }

  flatChipElement(chip, index) {
    const meta = this.metaFor(chip.field)
    const wrapper = document.createElement("span")
    wrapper.className = "inline-flex items-center gap-1 rounded-md border border-gray-300 bg-gray-50 px-2 py-1 text-sm hover:bg-gray-100"

    const editLink = document.createElement("button")
    editLink.type = "button"
    editLink.className = "inline-flex items-baseline gap-1 cursor-pointer"
    editLink.dataset.action = "click->chip-bar#editChip"
    editLink.dataset.chipIndex = index
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
    removeButton.dataset.chipIndex = index

    wrapper.append(editLink, removeButton)
    return wrapper
  }

  complexBadgeElement(node, index) {
    // OR / NOT / unrecognized — show as a read-only badge so smart
    // folders that already carry composite trees still render.
    const wrapper = document.createElement("span")
    wrapper.className = "inline-flex items-center gap-1 rounded-md border border-amber-300 bg-amber-50 px-2 py-1 text-sm text-amber-800"
    wrapper.title = JSON.stringify(node)
    wrapper.textContent = node && (node.or ? "OR group" : node.not ? "NOT group" : "complex filter")

    const removeButton = document.createElement("button")
    removeButton.type = "button"
    removeButton.className = "ml-1 text-amber-600 hover:text-amber-900 cursor-pointer"
    removeButton.textContent = "×"
    removeButton.dataset.action = "click->chip-bar#removeChip"
    removeButton.dataset.chipIndex = index
    wrapper.append(removeButton)
    return wrapper
  }

  metaFor(field) {
    return (this.schemaValue || []).find(meta => meta.field === field)
  }

  // ---- Chip mutations ----

  removeChip(event) {
    const index = Number(event.currentTarget.dataset.chipIndex)
    const children = this.topChildren().slice()
    children.splice(index, 1)
    this.setTopChildren(children)
    this.submitForm()
  }

  clearAll() {
    this.setTopChildren([])
    this.submitForm()
  }

  // ---- Add-filter popover ----

  openAddMenu(event) {
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
    const children = this.topChildren().slice()
    const newIndex = children.length
    children.push({ field, op: defaults.op, value: defaults.value })
    this.setTopChildren(children)
    this.closePopovers()
    // Immediately open the editor on the new chip so the operator
    // can pick a value without an extra click.
    this.openEditorForIndex(newIndex)
  }

  // ---- Per-chip editor popover ----

  editChip(event) {
    const index = Number(event.currentTarget.dataset.chipIndex)
    this.openEditorForIndex(index)
  }

  openEditorForIndex(index) {
    const chip = this.topChildren()[index]
    if (!chip || !("field" in chip)) return
    const meta = this.metaFor(chip.field)
    if (!meta) return

    this.editingChipIndex = index
    this.editorTarget.replaceChildren(this.editorContent(chip, meta))

    const anchor = this.chipsTarget.children[index] || this.addButtonTarget
    this.positionPopover(this.editorTarget, anchor)
    this.editorTarget.classList.remove("hidden")
  }

  editorContent(chip, meta) {
    const root = document.createElement("div")
    root.className = "p-3 space-y-3"

    const header = document.createElement("div")
    header.className = "text-xs font-semibold uppercase tracking-wide text-gray-500"
    header.textContent = meta.label
    root.append(header)

    // Operator picker (only if the chip has more than one operator).
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
    footer.className = "flex justify-end pt-1"
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
        return null // operator IS the value; no separate editor needed
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

  // The editor's inputs use `data-chip-bar-target="editorInput"` to
  // namespace; on Done we re-read them all.
  applyEditor() {
    if (this.editingChipIndex === null) return
    const children = this.topChildren().slice()
    const chip = { ...children[this.editingChipIndex] }
    const opSelect = this.editorTarget.querySelector("select[data-action*='updateChipOp']")
    if (opSelect) chip.op = opSelect.value

    chip.value = readEditorValue(this.editorTarget, chip.op)
    children[this.editingChipIndex] = chip
    this.setTopChildren(children)
    this.closePopovers()
    this.submitForm()
  }

  updateChipOp(event) {
    // Re-render the editor when the operator changes — between/within_last
    // need different inputs than equals/contains, and predicates need
    // no value input at all.
    if (this.editingChipIndex === null) return
    const newOp = event.currentTarget.value
    const children = this.topChildren().slice()
    children[this.editingChipIndex] = { ...children[this.editingChipIndex], op: newOp, value: null }
    this.setTopChildren(children)
    this.openEditorForIndex(this.editingChipIndex)
  }

  closePopovers() {
    this.addMenuTarget.classList.add("hidden")
    this.editorTarget.classList.add("hidden")
    this.editingChipIndex = null
  }

  positionPopover(popover, anchor) {
    // Position relative to the controller's element. Operators see
    // the popover anchored to the chip / button they clicked,
    // tucked into the page flow.
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
  // base64-url without padding — matches Filters::QueryParam.encode.
  return btoa(unescape(encodeURIComponent(json)))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "")
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
  // For collection chips with no static values (tags don't have a
  // schema-time value list), drop back to a comma-separated input.
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

  // within_last / more_than_ago: { n, unit }
  const nInput = editor.querySelector('[data-role="n"]')
  const unitSelect = editor.querySelector('[data-role="unit"]')
  if (nInput && unitSelect) {
    return { n: Number(nInput.value || 0), unit: unitSelect.value }
  }

  // CSV (tag ids without a schema list)
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

  // Multiple inputs without explicit roles → array of values
  return Array.from(inputs).map(input => {
    if (input.type === "number") {
      const num = Number(input.value)
      return Number.isFinite(num) && input.value !== "" ? num : null
    }
    return input.value
  })
}
