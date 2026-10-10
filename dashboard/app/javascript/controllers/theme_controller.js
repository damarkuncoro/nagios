import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["sunIcon", "moonIcon"]

  connect() {
    this.updateIcons()
  }

  toggle() {
    if (document.documentElement.classList.contains("dark")) {
      document.documentElement.classList.remove("dark")
      localStorage.setItem("theme", "light")
    } else {
      document.documentElement.classList.add("dark")
      localStorage.setItem("theme", "dark")
    }
    this.updateIcons()
  }

  updateIcons() {
    const isDark = document.documentElement.classList.contains("dark")
    if (this.hasSunIconTarget && this.hasMoonIconTarget) {
      if (isDark) {
        this.sunIconTarget.classList.remove("hidden")
        this.moonIconTarget.classList.add("hidden")
      } else {
        this.sunIconTarget.classList.add("hidden")
        this.moonIconTarget.classList.remove("hidden")
      }
    }
  }
}
