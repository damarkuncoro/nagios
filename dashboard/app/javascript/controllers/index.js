import { application } from "controllers/application"

import AutoRefreshController from "controllers/auto_refresh_controller"
application.register("auto-refresh", AutoRefreshController)

import FilterController from "controllers/filter_controller"
application.register("filter", FilterController)

import ThemeController from "controllers/theme_controller"
application.register("theme", ThemeController)

import QuickSearchController from "controllers/quick_search_controller"
application.register("quick-search", QuickSearchController)
