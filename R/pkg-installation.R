
#' @param refs Package names or references. See
#'   ['Package references'][pkg_refs] for the syntax.
#' @param config Configuration options, a named list. See
#'  ['Configuration'][pkg_config]. If it does not include `library`, then
#'  `.libPaths()[1]` is added as `library`.
#' @param ... Additional arguments, passed to
#'   [`pkg_installation_proposal$new()`](#method-new).
#'
#' @export
#' @rdname pkg_installation_proposal

new_pkg_installation_proposal <- function(refs, config = list(), ...) {
  config$library <- config$library %||% .libPaths()[[1]]
  pkg_installation_proposal$new(refs, config = config, ...)
}

#' R6 class for package download and installation.
#'
#' @description
#' Download and install R packages, with their dependencies, from various
#' sources.
#'
#' @details
#' `new_pkg_installation_proposal()` creates a new object from the
#' `pkg_installation_proposal` class. The advantage of
#' `new_pkg_installation_proposal()` compared to using the
#' [pkg_installation_proposal] constructor directly is that it avoids
#' making pkgdepends a build time dependency.
#'
#' Typical workflow to install a set of packages:
#'
#' 1. Create a `pkg_installation_proposal` object with
#'    `new_pkg_installation_proposal()`.
#' 1. Resolve all possible dependencies with
#'    [`pkg_installation_proposal$resolve()`](#method-resolve).
#' 1. Solve the package dependencies, to get an installation plan, with
#'    [`pkg_installation_proposal$solve()`](#method-solve).
#' 1. Download all files with
#'    [`pkg_installation_proposal$download()`](#method-download).
#' 1. Install the downloaded files with
#'    [`pkg_installation_proposal$install()`](#methods-install).
#'
#' @param refs Package names or references. See
#'   ['Package references'][pkg_refs] for the syntax.
#'
#' @export
#' @examplesIf pkgdepends:::is_online()
#' pdi <- new_pkg_installation_proposal(
#'   "pak",
#'   config = list(library = tempfile())
#' )
#' pdi
#'
#' pdi$resolve()
#' pdi
#'
#' pdi$solve()
#' pdi
#'
#' pdi$download()
#' pdi

pkg_installation_proposal <- R6::R6Class(
  "pkg_installation_proposal",
  public = list(

    #' @description
    #' Create a new `pkg_installation_proposal` object. Consider using
    #' `new_pkg_installation_proposal()` instead of calling the constructor
    #' directly.
    #'
    #' The returned object can be used to look up (recursive) dependencies
    #' of R packages from various sources, and then download and install
    #' the package files.
    #'
    #' @param config Configuration options, a named list. See
    #'   ['Configuration'][pkg_config]. It needs to include the package
    #'   library to install to, in `library`.
    #' @param policy Solution policy. See ['The dependency
    #'   solver'][pkg_solution].
    #' @param remote_types Custom remote ref types, this is for advanced
    #'   use, and experimental currently.
    #'
    #' @examples
    #' pdi <- new_pkg_installation_proposal(
    #'   "r-lib/pkgdepends",
    #'   config = list(library = tempfile()))
    #' pdi

    initialize = function(
      refs,
      config = list(),
      policy = c("lazy", "upgrade"),
      remote_types = NULL) {

      policy <- match.arg(policy)
      assert_that(is_path(config$library))
      private$library <- config$library
      private$policy <- policy
      private$plan <- pkg_plan$new(
        refs,
        config = config,
        library = config$library,
        remote_types = remote_types
      )
    },

    #' @description
    #' The package refs that were used to create the
    #' `pkg_installation_proposal` object.
    #'
    #' @return
    #' A character vector of package refs that were used to create the
    #' `pkg_installation_proposal` object.
    #'
    #' @examples
    #' pdi <- new_pkg_installation_proposal("r-lib/pkgdepends")
    #' pdi$get_refs()

    get_refs = function() private$plan$get_refs(),

    #' @description
    #' Configuration options for the `pkg_installation_proposal` object. See
    #' ['Configuration'][pkg_config] for details.
    #'
    #' @return
    #' Named list. See ['Configuration'][pkg_config] for the configuration
    #' options.
    #'
    #' @examples
    #' pdi <- new_pkg_installation_proposal(
    #'   "pak",
    #'   config = list(library = tempfile())
    #' )
    #' pdi$get_config()

    get_config = function() private$plan$get_config(),

    #' @description
    #' Resolve the dependencies of the specified package references. This
    #' usually means downloading metadata from CRAN and Bioconductor,
    #' unless already cached, and also from GitHub if GitHub refs were
    #' included, either directly or indirectly. See
    #' ['Dependency resolution'][pkg_resolution] for details.
    #'
    #' @return
    #' The `pkg_installation_proposal` object, invisibly.
    #'
    #' @examplesIf pkgdepends:::is_online()
    #' pdi <- new_pkg_installation_proposal(
    #'   "pak",
    #'   config = list(library = tempfile())
    #' )
    #'
    #' pdi$resolve()
    #' pdi$get_resolution()

    resolve = function() {
      private$plan$resolve()
      invisible(self)
    },

    #' @description
    #' The same as [`resolve()`](#method-resolve), but asynchronous. This
    #' method is for advanced use.
    #'
    #' @return
    #' A deferred value.

    async_resolve = function() private$plan$async_resolve(),

    #' @description
    #' Query the result of the dependency resolution. This method can be
    #' called after [`resolve()`](#method-resolve) has completed.
    #'
    #' @return
    #' A [pkg_resolution_result] object, which is also a tibble. See
    #' ['Dependency resolution'][pkg_resolution] for its columns.
    #'
    #' @examplesIf pkgdepends:::is_online()
    #' pdi <- new_pkg_installation_proposal(
    #'   "r-lib/pkgdepends",
    #'   config = list(library = tempfile())
    #' )
    #' pdi$resolve()
    #' pdi$get_resolution()

    get_resolution = function() private$plan$get_resolution(),

    #' @description
    #' Returns the current policy of the dependency solver.
    #' See ['The dependency solver'][pkg_solution] for details.
    #'
    #' @return
    #' A character vector of length one.
    #'
    #' @examples
    #' pdi <- new_pkg_installation_proposal(
    #'   "r-lib/pkgdepends",
    #'   config = list(library = tempfile())
    #' )
    #' pdi$get_solve_policy()
    #' pdi$set_solve_policy("upgrade")
    #' pdi$get_solve_policy()

    get_solve_policy = function() private$policy,

    #' @description
    #' Set the current policy of the dependency solver.
    #' If the object already contains a solution and the new policy is
    #' different than the old policy, then the solution is deleted.
    #' See ['The dependency solver'][pkg_solution] for details.
    #'
    #' @param policy Policy to set.
    #'
    #' @examples
    #' pdi <- new_pkg_installation_proposal(
    #'   "r-lib/pkgdepends",
    #'   config = list(library = tempfile())
    #' )
    #' pdi$get_solve_policy()
    #' pdi$set_solve_policy("upgrade")
    #' pdi$get_solve_policy()

    set_solve_policy = function(policy = c("lazy", "upgrade")) {
      policy <- match.arg(policy)
      if (private$policy != policy) {
        private$plan$delete_solution()
        private$policy <- policy
      }
    },

    #' @description
    #' Solve the package dependencies. Out of the resolved dependencies,
    #' it works out a set of packages, that can be installed together to
    #' create a functional installation. The set includes all directly
    #' specified packages, and all required (or suggested, depending on
    #' the configuration) packages as well. It includes every package at
    #' most once. See ['The dependency solver'][pkg_solution] for details.
    #'
    #' @return
    #' The `pkg_installation_proposal` object itself, invisibly.
    #'
    #' @examplesIf pkgdepends:::is_online()
    #' pdi <- new_pkg_installation_proposal(
    #'   "r-lib/pkgdepends",
    #'   config = list(library = tempfile())
    #' )
    #' pdi$resolve()
    #' pdi$solve()
    #' pdi$get_solution()

    solve = function() {
      private$plan$solve(policy = private$policy)
      invisible(self)
    },

    #' @description
    #' Returns the solution of the package dependencies.
    #'
    #' @return
    #' A [pkg_solution_result] object, which is a list. See
    #' [pkg_solution_result] for details.
    #'
    #' @examplesIf pkgdepends:::is_online()
    #' pdi <- new_pkg_installation_proposal(
    #'   "r-lib/pkgdepends",
    #'   config = list(library = tempfile())
    #' )
    #' pdi$resolve()
    #' pdi$solve()
    #' pdi$get_solution()

    get_solution = function() private$plan$get_solution(),

    #' @description
    #' Error if the dependency solver failed to find a consistent set of
    #' packages that can be installed together.
    #'
    #' @examplesIf pkgdepends:::is_online()
    #' # This is an error, because the packages conflict:
    #' pdi <- new_pkg_installation_proposal(
    #'   c("r-lib/pak", "cran::pak"),
    #'   config = list(library = tempfile())
    #' )
    #' pdi$resolve()
    #' pdi$solve()
    #' pdi
    #' # This fails:
    #' # pdi$stop_for_solution_error()

    stop_for_solution_error = function() {
      private$plan$stop_for_solve_error()
    },

    #' @description
    #' Draw a tree of package dependencies. It returns a `tree` object, see
    #' [cli::tree()]. Printing this object prints the dependency tree to the
    #' screen.
    #'
    #' @return
    #' A `tree` object from the cli package, see [cli::tree()].
    #'
    #' @examplesIf pkgdepends:::is_online()
    #' pdi <- new_pkg_installation_proposal(
    #'   "pak",
    #'   config = list(library = tempfile())
    #' )
    #' pdi$resolve()
    #' pdi$solve()
    #' pdi$draw()

    draw = function() private$plan$draw_solution_tree(),

    #' @description
    #' Download all packages that are part of the solution. It uses the
    #' package cache in the pkgcache package by default, to avoid downloads
    #' if possible.
    #'
    #' @return
    #' The `pkg_installation_proposal` object itself, invisibly.
    #'
    #' @examplesIf pkgdepends:::is_online()
    #' pdi <- new_pkg_installation_proposal(
    #'   c("r-lib/pak", "cran::pak"),
    #'   config = list(library = tempfile())
    #' )
    #' pdi$resolve()
    #' pdi$solve()
    #' pdi$download()
    #' pdi$get_downloads()

    download = function() invisible(private$plan$download_solution()),

    #' @description
    #' The same as [`download()`](#method-download), but asynchronous.
    #' This method is for advanced use.
    #'
    #' @return
    #' A deferred value.

    async_download = function() private$plan$async_download_solution(),

    #' @description
    #' Returns the summary of the package downloads.
    #'
    #' @return
    #' A [pkg_download_result] object, which is a list. See
    #' [pkg_download_result] for details.
    #'
    #' @examplesIf pkgdepends:::is_online()
    #' pdi <- new_pkg_installation_proposal(
    #'   c("r-lib/pak", "cran::pak"),
    #'   config = list(library = tempfile())
    #' )
    #' pdi$resolve()
    #' pdi$solve()
    #' pdi$download()
    #' pdi$get_downloads()

    get_downloads = function() private$plan$get_solution_download(),

    #' @description
    #' Throw and error if the some of the downloads have failed for the
    #' most recent
    #' [`pkg_installation_proposal$download()`](#method-download) call.

    stop_for_download_error = function() {
      private$plan$stop_for_solution_download_error()
    },

    #' @description
    #' Install the downloaded packages. It calls [install_package_plan()].
    #'
    #' @return
    #' The return value of [install_package_plan()].

    install = function() {
      plan <- private$plan$get_install_plan()
      nw <- get_num_workers()
      install_package_plan(plan, lib = private$library, num_workers = nw)
    },

    #' @description
    #' Create an installation plan for the downloaded packages.
    #'
    #' @return
    #' An installation plan, see ['Installation plans'][install_plans] for
    #' the format.
    #'
    #' @examplesIf pkgdepends:::is_online()
    #' pdi <- new_pkg_installation_proposal(
    #'   "pak",
    #'   config = list(library = tempfile())
    #' )
    #' pdi$resolve()
    #' pdi$solve()
    #' pdi$download()
    #' pdi$get_install_plan()

    get_install_plan = function() private$plan$get_install_plan(),

    #' @description
    #' Format a `pkg_installation_proposal` object, typically for printing.
    #'
    #' @param ... not used currently.
    #'
    #' @return
    #' A character vector, each element should be a line in the printout.

    format = function(...) {
      refs <- private$plan$get_refs()

      has_dls <- private$plan$has_solution_downloads()
      dls <- if (has_dls) private$plan$get_solution_download()
      dls_err <- has_dls && any(dls$status == "Failed")

      has_sol <- private$plan$has_solution()
      sol <- if (has_sol) private$plan$get_solution()
      sol_err <- has_sol && sol$status != "OK"

      c("<pkg_installation_proposal>",
        "+ refs:", paste0("  - ", refs),
        paste0("+ solution policy: ", private$policy),
        if (has_sol) "+ has solution",
        if (sol_err) "x has solution errors",
        if (has_dls) "+ has downloads",
        if (dls_err) "x has download errors",
        if (!has_sol) "(use `$solve()` to solve dependencies)",
        if (has_sol && !sol_err && !has_dls)
          "(use `$download()` to download packages)",
        if (has_sol) "(use `$get_solution()` to see solution results)",
        if (has_sol && !sol_err) "(use `$draw()` to draw the dependency tree)",
        if (has_dls) "(use `$get_downloads()` to get download data)",
        if (has_dls) "(use `$get_install_plan()` to get the installation plan)",
        if (has_dls) "(use `$install()` to install the packages)"
      )
    },

    #' @description
    #' Prints a `pkg_installation_proposal` object to the screen.
    #'
    #' The printout includes:
    #'
    #' * The package refs.
    #' * The policy of the dependency solver.
    #' * Whether the object has the solved dependencies.
    #' * Whether the solution had errors.
    #' * Whether the object has downloads.
    #' * Whether the downloads had errors.
    #' * Advice on which methods to call next.
    #'
    #' See the example below.
    #'
    #' @param ... not used currently.
    #' @return
    #' The `pkg_installation_proposal` object itself, invisibly.
    #'
    #' @examplesIf pkgdepends:::is_online()
    #' pdi <- new_pkg_installation_proposal(
    #'   "pak",
    #'   config = list(library = tempfile())
    #' )
    #' pdi
    #'
    #' pdi$resolve()
    #' pdi
    #'
    #' pdi$solve()
    #' pdi
    #'
    #' pdi$download()
    #' pdi

    print = function(...) cat(self$format(...), sep = "\n")
  ),

  private = list(
    plan = NULL,
    policy = NULL,
    library = NULL
  )
)
