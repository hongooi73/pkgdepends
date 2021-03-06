
### -----------------------------------------------------------------------
### API

#' @importFrom rematch2 re_match
#' @importFrom jsonlite fromJSON
#' @importFrom desc desc
#' @importFrom glue glue

parse_remote_github <- function(specs, config, ...) {

  pds <- re_match(specs, github_rx())
  if (any(unk <- is.na(pds$.match))) {
    pds[unk] <- re_match(specs[unk], github_url_rx())
    pds[unk, "subdir"] <- ""
  }

  pds$ref <- pds$.text
  cn <- setdiff(colnames(pds), c(".match", ".text"))
  pds <- pds[, cn]
  pds$type <- "github"
  pds$package <- ifelse(nzchar(pds$package), pds$package, pds$repo)
  lapply(
    seq_len(nrow(pds)),
    function(i) as.list(pds[i,])
  )
}

resolve_remote_github <- function(remote, direct, config, cache,
                                  dependencies, ...) {

  force(direct); force(dependencies)
  ## Get the DESCRIPTION data, and the SHA we need
  type_github_get_data(remote)$
    then(function(resp) {
      data <- list(
        desc = resp$description,
        sha = resp$sha,
        remote = remote,
        direct = direct,
        dependencies = dependencies[[2 - direct]])
      type_github_make_resolution(data)
    })
}

download_remote_github <- function(resolution, target, target_tree,
                                   config, cache, which, on_progress) {

  ## A GitHub package needs to be built, from the downloaded repo
  ## If we are downloading a solution, then we skip building the vignettes,
  ## because these will be built later by pkginstall.
  ##
  ## We cache both the downloaded repo snapshot and the built package in
  ## the package cache. So this is how we go:
  ##
  ## 1. If there is a built package in the cache (including vignettes
  ##    if they are needed), then we just use that.
  ## 2. If there is a repo snapshot in the cache, we build an R package
  ##    from it. (Add also add it to the cache.)
  ## 3. Otherwise we download the repo, add it to the cache, build the
  ##    R package, and add that to the cache as well.

  package <- resolution$package
  sha <- resolution$extra[[1]]$remotesha
  need_vignettes <- which == "resolution"

  ## 1. Check if we have a built package in the cache. We do not check the
  ## ref or the type, so the package could have been built from a local
  ## ref or from another repo. As long as the sha is the same, we are
  ## fine. If we don't require vignetted, then a package with or without
  ## vignettes is fine.

  hit <- cache$package$copy_to(
    target, package = package, sha256 = sha, built = TRUE,
    .list = c(if (need_vignettes) c(vignettes = TRUE)))
  if (nrow(hit)) {
    "!DEBUG found GH `resolution$ref`@`sha` in the cache"
    return("Had")
  }

  ## 2. Check if we have a repo snapshot in the cache.

  rel_target <- resolution$target
  subdir <- resolution$remote[[1]]$subdir
  hit <- cache$package$copy_to(
    target_tree, package = package, sha256 = sha, built = FALSE)
  if (nrow(hit)) {
    "!DEBUG found GH zip for `resolution$ref`@`sha` in the cache"
    return("Had")
  }

  ## 3. Need to download the repo

  "!DEBUG Need to download GH package `resolution$ref`@`sha`"
  urls <- resolution$sources[[1]]
  rel_zip <- paste0(rel_target, "-tree")
  type_github_download_repo(urls, target_tree, rel_zip, sha, package, cache,
                            on_progress)$
    then(function() {
      "!DEBUG Building package `resolution$package`"
      return("Got")
    })
}

type_github_download_repo <- function(urls, repo_zip, rel_zip, sha,
                                      package, cache, on_progress) {
  ## TODO: progress
  download_file(urls, repo_zip, on_progress = on_progress)$
    then(function() {
      cache$package$add(
        repo_zip, rel_zip, package = package, sha = sha, built = FALSE)
      "Got"
    })
}

## ----------------------------------------------------------------------

satisfy_remote_github <- function(resolution, candidate,
                                    config, ...) {

  ## 1. package name must match
  if (resolution$package != candidate$package) {
    return(structure(FALSE, reason = "Package names differ"))
  }

  ## 1. installed ref is good, if it has the same sha
  if (candidate$type == "installed") {
    sha1 <- tryCatch(candidate$extra[[1]]$remotesha, error = function(e) "")
    sha2 <- resolution$extra[[1]]$remotesha
    ok <- is_string(sha1) && is_string(sha2) && same_sha(sha1, sha2)
    if (!ok) {
      return(structure(FALSE, reason = "Installed package sha mismatch"))
    } else {
      return(TRUE)
    }
  }

  ## 2. other refs are also good, as long as they have the same sha
  sha1 <- tryCatch(candidate$extra[[1]]$remotesha, error = function(e) "")
  sha2 <- resolution$extra[[1]]$remotesha
  ok <- is_string(sha1) && is_string(sha2) && same_sha(sha1, sha2)
  if (!ok) {
    return(structure(FALSE, reason = "Candidate package sha mismatch"))
  } else {
    return(TRUE)
  }
}

## ----------------------------------------------------------------------
## Internal functions

#' @importFrom cli cli_alert_warning

type_github_builtin_token <- function() {
  pats <- c(
    paste0("3687d8b", "b0556b7c3", "72ba1681d", "e5e689b", "3ec61279"),
    paste0("8ffecf5", "13a136f3d", "23bfe46c4", "2d67b3c", "966baf7b")
  )
  once_per_session(cli_alert_warning(c(
    "Using bundled GitHub PAT. ",
    "Please add your own PAT to the env var {.envvar GITHUB_PAT}"
  )))
  sample(pats, 1)
}

type_github_get_headers <- function() {
  headers <- c("Accept" = "application/vnd.github.v3+json")
  token <- Sys.getenv("GITHUB_TOKEN", NA_character_)
  if (is.na(token)) token <- Sys.getenv("GITHUB_PAT", NA_character_)
  if (is.na(token)) token <- type_github_builtin_token()
  headers <- c(headers, c("Authorization" = paste("token", token)))
  headers
}

type_github_get_data <- function(rem) {
  dx <- if (!is.null(rem$pull) && rem$pull != "") {
    type_github_get_data_pull(rem)
  } else {
    type_github_get_data_ref(rem)
  }

  dx$then(function(data) {
    rethrow(
      dsc <- desc(text = data$desc),
      new_github_baddesc_error(rem, call)
    )
    list(sha = data$sha, description = dsc)
  })
}

type_github_get_data_ref <- function(rem) {
  user <- rem$username
  repo <- rem$repo
  ref <- rem$commitish %|z|% "master"
  subdir <- rem$subdir %&z&% paste0(utils::URLencode(rem$subdir), "/")

  query <- glue("{
    repository(owner: \"<user>\", name: \"<repo>\") {
      description: object(expression: \"<ref>:<subdir>DESCRIPTION\") {
        ... on Blob {
          isBinary
          text
        }
      }
      sha: object(expression: \"<ref>\") {
        oid
      }
    }
  }",
  .open = "<", .close = ">")

  github_query(query)$
    then(function(resp) {
      check_github_response_ref(resp$response, resp$obj, rem, call. = call)
    })$
    then(function(obj) {
      list(
        sha = obj[[c("data", "repository", "sha", "oid")]],
        desc = obj[[c("data", "repository", "description", "text")]]
      )
    })
}

check_github_response_ref <- function(resp, obj, rem, call.) {
  if (!is.null(obj$errors)) {
    throw(new_github_query_error(rem, resp, obj, call.))
  }
  if (isTRUE(obj[[c("data", "repository", "description", "isBinary")]])) {
    throw(new_github_baddesc_error(rem, call.))
  }
  if (is.null(obj[[c("data", "repository", "sha")]])) {
    throw(new_github_noref_error(rem, call.))
  }
  if (is.null(obj[[c("data", "repository", "description", "text")]])) {
    throw(new_github_no_package_error(rem, call.))
  }
  obj
}

type_github_get_data_pull <- function(rem) {
  call <- sys.call(-1)
  user <- rem$username
  repo <- rem$repo
  pull <- rem$pull
  ref <- NULL
  subdir <- rem$subdir %&z&% paste0(utils::URLencode(rem$subdir), "/")

  # Get the sha first, seemingly there is no good way to do this in one go
  query1 <- glue("{
    repository(owner: \"<user>\", name:\"<repo>\") {
      pullRequest(number: <pull>) {
        headRefOid
      }
    }
  }",
  .open = "<", .close = ">")

  github_query(query1)$
    then(function(resp) {
      check_github_response_pull1(resp$response, resp$obj, rem, call. = call)
    })$
    then(function(obj) {
      ref <<- obj[[c("data", "repository", "pullRequest", "headRefOid")]]
      query2 <- glue("{
        repository(owner: \"<user>\", name:\"<repo>\") {
          object(expression: \"<ref>:<subdir>DESCRIPTION\") {
            ... on Blob {
              isBinary
              text
            }
          }
        }
      }",
      .open = "<", .close = ">")
      github_query(query2)
    })$
    then(function(resp) {
      check_github_response_pull2(resp$response, resp$obj, rem, call. = call)
    })$
    then(function(obj) {
      txt <- obj[[c("data", "repository", "object", "text")]]
      list(sha = ref, desc = txt)
    })
}

check_github_response_pull1 <- function(resp, obj, rem, call.) {
  if (!is.null(obj$errors)) {
    throw(new_github_query_error(rem, resp, obj, call.))
  }
  obj
}

check_github_response_pull2 <- function(resp, obj, rem, call.) {
  if (!is.null(obj$errors)) {
    throw(new_github_query_error(rem, resp, obj, call.))
  }
  if (isTRUE(obj[[c("data", "repository", "object", "isBinary")]])) {
    throw(new_github_baddesc_error(rem, call.))
  }
  if (is.null(obj[[c("data", "repository", "object")]])) {
    throw(new_github_no_package_error(rem, call.))
  }
  obj
}

type_github_make_resolution <- function(data) {

  deps <- resolve_ref_deps(data$desc$get_deps(), data$desc$get("Remotes"))

  sha <- data$sha
  username <- data$remote$username
  repo <- data$remote$repo
  subdir <- data$remote$subdir %|z|% NULL
  commitish <- data$remote$commitish %|z|% NULL
  pull <- data$remote$pull %|z|% NULL
  release <- data$remote$release %|z|% NULL
  package <- data$desc$get_field("Package")
  version <- data$desc$get_field("Version")
  dependencies <- data$dependencies
  unknown <- deps$ref[deps$type %in% dependencies]
  unknown <- setdiff(unknown, c(base_packages(), "R"))

  meta <- c(
    RemoteType = "github",
    RemoteHost = "api.github.com",
    RemoteRepo = repo,
    RemoteUsername = username,
    RemotePkgRef = data$remote$ref,
    RemoteRef = if (is.null(pull)) commitish %||% "master" else NULL,
    RemotePull = pull,
    RemoteSha = sha,
    RemoteSubdir = subdir,
    GithubRepo = repo,
    GithubUsername = username,
    GithubRef = if (is.null(pull)) commitish %||% "master" else NULL,
    GitHubPull = pull,
    GithubSHA1 = sha,
    GithubSubdir = subdir)

  list(
    ref = data$remote$ref,
    type = data$remote$type,
    direct = data$direct,
    status = "OK",
    package = package,
    version = version,
    license = data$desc$get_field("License", NA_character_),
    sources = glue(
      "https://api.github.com/repos/{username}/{repo}/zipball/{sha}"),
    target = glue("src/contrib/{package}_{version}_{sha}.tar.gz"),
    remote = list(data$remote),
    deps = list(deps),
    unknown_deps = unknown,
    extra = list(list(remotesha = sha)),
    metadata = meta
  )
}

github_query <- function(query, url = "https://api.github.com/graphql",
                         headers = character(), ...) {

  query; url; headers; list(...)

  headers <- c(headers, type_github_get_headers())
  data <- jsonlite::toJSON(list(query = query), auto_unbox = TRUE)
  resp <- NULL
  obj <- NULL

  http_post(url, data = data, headers = headers, ...)$
    catch(error = function(err) throw(new_github_offline_error()))$
    then(function(res) {
      resp <<- res
      json <- rawToChar(res$content %||% raw())
      obj <<- if (nzchar(json)) jsonlite::fromJSON(json, simplifyVector = FALSE)
      res
    })$
    then(http_stop_for_status)$
    catch(async_http_error = function(err) {
      throw(new_github_http_error(resp, obj), parent = err)
    })$
    then(function(res) {
      list(response = resp, obj = obj)
    })
}

# -----------------------------------------------------------------------
# Errors

new_github_error <- function(..., call. = NULL) {
  cond <- new_error(..., call. = call.)
  class(cond) <- c("github_error", class(cond))
  cond
}

# No internet?

new_github_offline_error <- function(call. = NULL) {
  new_github_error("Cannot query GitHub, are you offline?", call. = call.)
}

# HTTP error

new_github_http_error <- function(response, obj, call. = NULL) {
  if (response$status_code == 401 &&
      nzchar(obj$message) && grepl("Bad credentials", obj$message)) {
    return(new_github_badpat_error(call. = call.))
  }
  new_github_error("GitHub HTTP error", call. = call.)
}

# Error in a query

new_github_query_error <- function(rem, response, obj, call. = NULL) {
  if ("RATE_LIMITED" %in% vcapply(obj$errors, "[[", "type")) {
    return(new_github_ratelimited_error(response, obj, call. = NULL))

  } else if (grepl("Could not resolve to a User",
                   vcapply(obj$errors, "[[", "message"))) {
    return(new_github_nouser_error(rem, obj, call. = call.))

  } else if (grepl("Could not resolve to a Repository",
                   vcapply(obj$errors, "[[", "message"))) {
    return(new_github_norepo_error(rem, obj, call. = call.))
  } else if (grepl("Could not resolve to a PullRequest",
                   vcapply(obj$errors, "[[", "message"))) {
    return(new_github_nopr_error(rem, obj, call. = call.))
  }

  # Otherwise some generic code
  ghmsgs <- sub("\\.?$", ".", vcapply(obj$errors, "[[", "message"))
  msg <- paste0("GitHub error: ", paste0(ghmsgs, collapse = ", "))
  new_github_error(msg, call. = call.)
}

# No such user/org

new_github_nouser_error <- function(rem, obj, call. = NULL) {
  ghmsgs <- sub("\\.?$", ".", vcapply(obj$errors, "[[", "message"))
  ghmsg <- grep("Could not resolve to a User", ghmsgs, value = TRUE)[1]
  msg <- glue(
    "Cannot resolve GitHub repo `{rem$username}/{rem$repo}`. ",
    "{ghmsg}"
  )
  new_github_error(msg, call. = call.)
}

# No such repo

new_github_norepo_error <- function(rem, obj, call. = NULL) {
  ghmsgs <- sub("\\.?$", ".", vcapply(obj$errors, "[[", "message"))
  ghmsg <- grep("Could not resolve to a Repository", ghmsgs, value = TRUE)[1]
  msg <- glue(
    "Cannot resolve GitHub repo `{rem$username}/{rem$repo}`. ",
    "{ghmsg}"
  )
  new_github_error(msg, call. = call.)
}

# Not an R package?

new_github_no_package_error <- function(rem, call. = NULL) {
  subdir <- rem$subdir %&z&% paste0(", in directory `", rem$subdir, "`")
  msg <- glue(
    "Cannot find R package in GitHub repo ",
    "`{rem$username}/{rem$repo}`{subdir}"
  )
  new_github_error(msg, call. = call.)
}

# Invalid GitHub PAT

new_github_badpat_error <- function(call. = NULL) {
  new_github_error(paste0(
    "Bad GitHub credentials, ",
    "make sure that your GitHub token is valid."
  ))
}

# DESCRIPTION does not parse

new_github_baddesc_error <- function(rem, call. = NULL) {
  subdir <- rem$subdir %&z&% paste0(", in directory `", rem$subdir, "`")
  msg <- glue(
    "Cannot parse DESCRIPTION file in GitHub repo ",
    "`{rem$username}/{rem$repo}`{subdir}"
  )
  new_github_error(msg)
}

# No such PR

new_github_nopr_error <- function(rem, obj, call. = NULL) {
  msg <- glue(
    "Cannot find pull request #{rem$pull} at repo ",
    "`{rem$username}/{rem$repo}`"
  )
  new_github_error(msg)
}

# No such branch/tag/ref

new_github_noref_error <- function(rem, call. = NULL) {
  ref <- rem$commitish %|z|% "master"
  msg <- glue("Cannot find branch/tag/commit `{ref}` in ",
              "GitHub repo `{rem$username}/{rem$repo}`.")
  new_github_error(msg)
}

# Rate limited

new_github_ratelimited_error <- function(response, obj, call. = NULL) {
  headers <- curl::parse_headers_list(response$headers)
  ghmsgs <- sub("\\.?$", ".", vcapply(obj$errors, "[[", "message"))
  msg <- paste0("GitHub error: ", paste0(ghmsgs, collapse = ", "))
  if ("x-ratelimit-reset" %in% names(headers)) {
    reset <- format(
      .POSIXct(headers$`x-ratelimit-reset`, tz = "UTC"),
      usetz = TRUE
    )
    msg <- paste0(msg, " Rate limit will reset at ", reset, ".")
  }
  new_github_error(msg, call. = call.)
}
