
context("metadata")

test_that("install_binary metadata", {

  pkg <- binary_test_package("foo")

  libpath <- test_temp_dir()

  metadata <- c("Foo" = "Bar", "Foobar" = "baz")
  expect_error_free(
    install_binary(pkg, lib = libpath, metadata = metadata, quiet = TRUE))

  dsc <- desc::desc(file.path(libpath, "foo"))
  expect_equal(dsc$get("Foo")[[1]], "Bar")
  expect_equal(dsc$get("Foobar")[[1]], "baz")

  rds <- readRDS(file.path(libpath, "foo", "Meta", "package.rds"))
  dsc2 <- rds$DESCRIPTION
  expect_equal(dsc2[["Foo"]], "Bar")
  expect_equal(dsc2[["Foobar"]], "baz")
})

test_that("install_package_plan metadata", {

  skip_if_offline()

  pkg <- source_test_package("foo")
  libpath <- test_temp_dir()

  withr::with_options(list(pkg.show_progress = FALSE), {
    plan <- make_install_plan(
      paste0("local::", pkg), lib = libpath)
    plan$metadata[[1]] <- c("Foo" = "Bar", "Foobar" = "baz")
    plan$vignettes <- FALSE
    expect_error_free(
      install_package_plan(plan, lib = libpath, num_workers = 1)
    )
  })

  dsc <- desc::desc(file.path(libpath, "foo"))
  expect_equal(dsc$get("Foo")[[1]], "Bar")
  expect_equal(dsc$get("Foobar")[[1]], "baz")

  rds <- readRDS(file.path(libpath, "foo", "Meta", "package.rds"))
  dsc2 <- rds$DESCRIPTION
  expect_equal(dsc2[["Foo"]], "Bar")
  expect_equal(dsc2[["Foobar"]], "baz")
})
