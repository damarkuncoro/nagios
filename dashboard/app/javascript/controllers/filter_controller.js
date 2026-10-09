import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "row", "filterBtn"]

  search() {
    const query = this.inputTarget.value.toLowerCase()
    this.rowTargets.forEach((row) => {
      const text = row.textContent.toLowerCase()
      if (text.includes(query)) {
        row.classList.remove("hidden")
      } else {
        row.classList.add("hidden")
      }
    })
  }

  filterByStatus(event) {
    const status = event.currentTarget.dataset.status

    // Update button active styles
    this.filterBtnTargets.forEach((btn) => {
      if (btn === event.currentTarget) {
        btn.classList.add("bg-slate-900", "text-white")
        btn.classList.remove("bg-white", "text-slate-600")
      } else {
        btn.classList.remove("bg-slate-900", "text-white")
        btn.classList.add("bg-white", "text-slate-600")
      }
    })

    this.rowTargets.forEach((row) => {
      if (status === "ALL" || row.dataset.status === status) {
        row.classList.remove("hidden")
      } else {
        row.classList.add("hidden")
      }
    })
  }
}
