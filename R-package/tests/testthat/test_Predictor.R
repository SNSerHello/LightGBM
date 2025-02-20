library(Matrix)

VERBOSITY <- as.integer(
  Sys.getenv("LIGHTGBM_TEST_VERBOSITY", "-1")
)

TOLERANCE <- 1e-6

test_that("Predictor$finalize() should not fail", {
    X <- as.matrix(as.integer(iris[, "Species"]), ncol = 1L)
    y <- iris[["Sepal.Length"]]
    dtrain <- lgb.Dataset(X, label = y)
    bst <- lgb.train(
        data = dtrain
        , params = list(
            objective = "regression"
        )
        , verbose = VERBOSITY
        , nrounds = 3L
    )
    model_file <- tempfile(fileext = ".model")
    bst$save_model(filename = model_file)
    predictor <- Predictor$new(modelfile = model_file)

    expect_true(lgb.is.Predictor(predictor))

    expect_false(lgb.is.null.handle(predictor$.__enclos_env__$private$handle))

    predictor$finalize()
    expect_true(lgb.is.null.handle(predictor$.__enclos_env__$private$handle))

    # calling finalize() a second time shouldn't cause any issues
    predictor$finalize()
    expect_true(lgb.is.null.handle(predictor$.__enclos_env__$private$handle))
})

test_that("predictions do not fail for integer input", {
    X <- as.matrix(as.integer(iris[, "Species"]), ncol = 1L)
    y <- iris[["Sepal.Length"]]
    dtrain <- lgb.Dataset(X, label = y)
    fit <- lgb.train(
        data = dtrain
        , params = list(
            objective = "regression"
        )
        , verbose = VERBOSITY
        , nrounds = 3L
    )
    X_double <- X[c(1L, 51L, 101L), , drop = FALSE]
    X_integer <- X_double
    storage.mode(X_double) <- "double"
    pred_integer <- predict(fit, X_integer)
    pred_double <- predict(fit, X_double)
    expect_equal(pred_integer, pred_double)
})

test_that("start_iteration works correctly", {
    set.seed(708L)
    data(agaricus.train, package = "lightgbm")
    data(agaricus.test, package = "lightgbm")
    train <- agaricus.train
    test <- agaricus.test
    dtrain <- lgb.Dataset(
        agaricus.train$data
        , label = agaricus.train$label
    )
    dtest <- lgb.Dataset.create.valid(
        dtrain
        , agaricus.test$data
        , label = agaricus.test$label
    )
    bst <- lightgbm(
        data = as.matrix(train$data)
        , label = train$label
        , params = list(
            num_leaves = 4L
            , learning_rate = 0.6
            , objective = "binary"
            , verbosity = VERBOSITY
        )
        , nrounds = 50L
        , valids = list("test" = dtest)
        , early_stopping_rounds = 2L
    )
    expect_true(lgb.is.Booster(bst))
    pred1 <- predict(bst, newdata = test$data, type = "raw")
    pred_contrib1 <- predict(bst, test$data, type = "contrib")
    pred2 <- rep(0.0, length(pred1))
    pred_contrib2 <- rep(0.0, length(pred2))
    step <- 11L
    end_iter <- 49L
    if (bst$best_iter != -1L) {
        end_iter <- bst$best_iter - 1L
    }
    start_iters <- seq(0L, end_iter, by = step)
    for (start_iter in start_iters) {
        n_iter <- min(c(end_iter - start_iter + 1L, step))
        inc_pred <- predict(bst, test$data
            , start_iteration = start_iter
            , num_iteration = n_iter
            , type = "raw"
        )
        inc_pred_contrib <- bst$predict(test$data
            , start_iteration = start_iter
            , num_iteration = n_iter
            , predcontrib = TRUE
        )
        pred2 <- pred2 + inc_pred
        pred_contrib2 <- pred_contrib2 + inc_pred_contrib
    }
    expect_equal(pred2, pred1)
    expect_equal(pred_contrib2, pred_contrib1)

    pred_leaf1 <- predict(bst, test$data, type = "leaf")
    pred_leaf2 <- predict(bst, test$data, start_iteration = 0L, num_iteration = end_iter + 1L, type = "leaf")
    expect_equal(pred_leaf1, pred_leaf2)
})

test_that("Feature contributions from sparse inputs produce sparse outputs", {
    data(mtcars)
    X <- as.matrix(mtcars[, -1L])
    y <- as.numeric(mtcars[, 1L])
    dtrain <- lgb.Dataset(X, label = y, params = list(max_bins = 5L))
    bst <- lgb.train(
      data = dtrain
      , obj = "regression"
      , nrounds = 5L
      , verbose = VERBOSITY
      , params = list(min_data_in_leaf = 5L)
    )

    pred_dense <- predict(bst, X, type = "contrib")

    Xcsc <- as(X, "CsparseMatrix")
    pred_csc <- predict(bst, Xcsc, type = "contrib")
    expect_s4_class(pred_csc, "dgCMatrix")
    expect_equal(unname(pred_dense), unname(as.matrix(pred_csc)))

    Xcsr <- as(X, "RsparseMatrix")
    pred_csr <- predict(bst, Xcsr, type = "contrib")
    expect_s4_class(pred_csr, "dgRMatrix")
    expect_equal(as(pred_csr, "CsparseMatrix"), pred_csc)

    Xspv <- as(X[1L, , drop = FALSE], "sparseVector")
    pred_spv <- predict(bst, Xspv, type = "contrib")
    expect_s4_class(pred_spv, "dsparseVector")
    expect_equal(Matrix::t(as(pred_spv, "CsparseMatrix")), unname(pred_csc[1L, , drop = FALSE]))
})

test_that("Sparse feature contribution predictions do not take inputs with wrong number of columns", {
    data(mtcars)
    X <- as.matrix(mtcars[, -1L])
    y <- as.numeric(mtcars[, 1L])
    dtrain <- lgb.Dataset(X, label = y, params = list(max_bins = 5L))
    bst <- lgb.train(
      data = dtrain
      , obj = "regression"
      , nrounds = 5L
      , verbose = VERBOSITY
      , params = list(min_data_in_leaf = 5L)
    )

    X_wrong <- X[, c(1L:10L, 1L:10L)]
    X_wrong <- as(X_wrong, "CsparseMatrix")
    expect_error(predict(bst, X_wrong, type = "contrib"), regexp = "input data has 20 columns")

    X_wrong <- as(X_wrong, "RsparseMatrix")
    expect_error(predict(bst, X_wrong, type = "contrib"), regexp = "input data has 20 columns")

    X_wrong <- as(X_wrong, "CsparseMatrix")
    X_wrong <- X_wrong[, 1L:3L]
    expect_error(predict(bst, X_wrong, type = "contrib"), regexp = "input data has 3 columns")
})

test_that("Feature contribution predictions do not take non-general CSR or CSC inputs", {
    set.seed(123L)
    y <- runif(25L)
    Dmat <- matrix(runif(625L), nrow = 25L, ncol = 25L)
    Dmat <- crossprod(Dmat)
    Dmat <- as(Dmat, "symmetricMatrix")
    SmatC <- as(Dmat, "sparseMatrix")
    SmatR <- as(SmatC, "RsparseMatrix")

    dtrain <- lgb.Dataset(as.matrix(Dmat), label = y, params = list(max_bins = 5L))
    bst <- lgb.train(
      data = dtrain
      , obj = "regression"
      , nrounds = 5L
      , verbose = VERBOSITY
      , params = list(min_data_in_leaf = 5L)
    )

    expect_error(predict(bst, SmatC, type = "contrib"))
    expect_error(predict(bst, SmatR, type = "contrib"))
})

test_that("predict() params should override keyword argument for raw-score predictions", {
  data(agaricus.train, package = "lightgbm")
  X <- agaricus.train$data
  y <- agaricus.train$label
  bst <- lgb.train(
    data = lgb.Dataset(
      data = X
      , label = y
      , params = list(
        data_seed = 708L
        , min_data_in_bin = 5L
      )
    )
    , params = list(
      objective = "binary"
      , min_data_in_leaf = 1L
      , seed = 708L
    )
    , nrounds = 10L
    , verbose = VERBOSITY
  )

  # check that the predictions from predict.lgb.Booster() really look like raw score predictions
  preds_prob <- predict(bst, X)
  preds_raw_s3_keyword <- predict(bst, X, type = "raw")
  preds_prob_from_raw <- 1.0 / (1.0 + exp(-preds_raw_s3_keyword))
  expect_equal(preds_prob, preds_prob_from_raw, tolerance = TOLERANCE)
  accuracy <- sum(as.integer(preds_prob_from_raw > 0.5) == y) / length(y)
  expect_equal(accuracy, 1.0)

  # should get the same results from Booster$predict() method
  preds_raw_r6_keyword <- bst$predict(X, rawscore = TRUE)
  expect_equal(preds_raw_s3_keyword, preds_raw_r6_keyword)

  # using a parameter alias of predict_raw_score should result in raw scores being returned
  aliases <- .PARAMETER_ALIASES()[["predict_raw_score"]]
  expect_true(length(aliases) > 1L)
  for (rawscore_alias in aliases) {
    params <- as.list(
      stats::setNames(
        object = TRUE
        , nm = rawscore_alias
      )
    )
    preds_raw_s3_param <- predict(bst, X, params = params)
    preds_raw_r6_param <- bst$predict(X, params = params)
    expect_equal(preds_raw_s3_keyword, preds_raw_s3_param)
    expect_equal(preds_raw_s3_keyword, preds_raw_r6_param)
  }
})

test_that("predict() params should override keyword argument for leaf-index predictions", {
  data(mtcars)
  X <- as.matrix(mtcars[, which(names(mtcars) != "mpg")])
  y <- as.numeric(mtcars[, "mpg"])
  bst <- lgb.train(
    data = lgb.Dataset(
      data = X
      , label = y
      , params = list(
        min_data_in_bin = 1L
        , data_seed = 708L
      )
    )
    , params = list(
      objective = "regression"
      , min_data_in_leaf = 1L
      , seed = 708L
    )
    , nrounds = 10L
    , verbose = VERBOSITY
  )

  # check that predictions really look like leaf index predictions
  preds_leaf_s3_keyword <- predict(bst, X, type = "leaf")
  expect_true(is.matrix(preds_leaf_s3_keyword))
  expect_equal(dim(preds_leaf_s3_keyword), c(nrow(X), bst$current_iter()))
  expect_true(min(preds_leaf_s3_keyword) >= 0L)
  trees_dt <- lgb.model.dt.tree(bst)
  max_leaf_by_tree_from_dt <- trees_dt[, .(idx = max(leaf_index, na.rm = TRUE)), by = tree_index]$idx
  max_leaf_by_tree_from_preds <- apply(preds_leaf_s3_keyword, 2L, max, na.rm = TRUE)
  expect_equal(max_leaf_by_tree_from_dt, max_leaf_by_tree_from_preds)

  # should get the same results from Booster$predict() method
  preds_leaf_r6_keyword <- bst$predict(X, predleaf = TRUE)
  expect_equal(preds_leaf_s3_keyword, preds_leaf_r6_keyword)

  # using a parameter alias of predict_leaf_index should result in leaf indices being returned
  aliases <- .PARAMETER_ALIASES()[["predict_leaf_index"]]
  expect_true(length(aliases) > 1L)
  for (predleaf_alias in aliases) {
    params <- as.list(
      stats::setNames(
        object = TRUE
        , nm = predleaf_alias
      )
    )
    preds_leaf_s3_param <- predict(bst, X, params = params)
    preds_leaf_r6_param <- bst$predict(X, params = params)
    expect_equal(preds_leaf_s3_keyword, preds_leaf_s3_param)
    expect_equal(preds_leaf_s3_keyword, preds_leaf_r6_param)
  }
})

test_that("predict() params should override keyword argument for feature contributions", {
  data(mtcars)
  X <- as.matrix(mtcars[, which(names(mtcars) != "mpg")])
  y <- as.numeric(mtcars[, "mpg"])
  bst <- lgb.train(
    data = lgb.Dataset(
      data = X
      , label = y
      , params = list(
        min_data_in_bin = 1L
        , data_seed = 708L
      )
    )
    , params = list(
      objective = "regression"
      , min_data_in_leaf = 1L
      , seed = 708L
    )
    , nrounds = 10L
    , verbose = VERBOSITY
  )

  # check that predictions really look like feature contributions
  preds_contrib_s3_keyword <- predict(bst, X, type = "contrib")
  num_features <- ncol(X)
  shap_base_value <- unname(preds_contrib_s3_keyword[, ncol(preds_contrib_s3_keyword)])
  expect_true(is.matrix(preds_contrib_s3_keyword))
  expect_equal(dim(preds_contrib_s3_keyword), c(nrow(X), num_features + 1L))
  expect_equal(length(unique(shap_base_value)), 1L)
  expect_equal(mean(y), shap_base_value[1L])
  expect_equal(predict(bst, X), rowSums(preds_contrib_s3_keyword))

  # should get the same results from Booster$predict() method
  preds_contrib_r6_keyword <- bst$predict(X, predcontrib = TRUE)
  expect_equal(preds_contrib_s3_keyword, preds_contrib_r6_keyword)

  # using a parameter alias of predict_contrib should result in feature contributions being returned
  aliases <- .PARAMETER_ALIASES()[["predict_contrib"]]
  expect_true(length(aliases) > 1L)
  for (predcontrib_alias in aliases) {
    params <- as.list(
      stats::setNames(
        object = TRUE
        , nm = predcontrib_alias
      )
    )
    preds_contrib_s3_param <- predict(bst, X, params = params)
    preds_contrib_r6_param <- bst$predict(X, params = params)
    expect_equal(preds_contrib_s3_keyword, preds_contrib_s3_param)
    expect_equal(preds_contrib_s3_keyword, preds_contrib_r6_param)
  }
})

.expect_has_row_names <- function(pred, X) {
    if (is.vector(pred)) {
        rnames <- names(pred)
    } else {
        rnames <- row.names(pred)
    }
    expect_false(is.null(rnames))
    expect_true(is.vector(rnames))
    expect_true(length(rnames) > 0L)
    expect_equal(row.names(X), rnames)
}

.expect_doesnt_have_row_names <- function(pred) {
    if (is.vector(pred)) {
        expect_null(names(pred))
    } else {
        expect_null(row.names(pred))
    }
}

.check_all_row_name_expectations <- function(bst, X) {

    # dense matrix with row names
    pred <- predict(bst, X)
    .expect_has_row_names(pred, X)
    pred <- predict(bst, X, type = "raw")
    .expect_has_row_names(pred, X)
    pred <- predict(bst, X, type = "leaf")
    .expect_has_row_names(pred, X)
    pred <- predict(bst, X, type = "contrib")
    .expect_has_row_names(pred, X)

    # dense matrix without row names
    Xcopy <- X
    row.names(Xcopy) <- NULL
    pred <- predict(bst, Xcopy)
    .expect_doesnt_have_row_names(pred)

    # sparse matrix with row names
    Xcsc <- as(X, "CsparseMatrix")
    pred <- predict(bst, Xcsc)
    .expect_has_row_names(pred, Xcsc)
    pred <- predict(bst, Xcsc, type = "raw")
    .expect_has_row_names(pred, Xcsc)
    pred <- predict(bst, Xcsc, type = "leaf")
    .expect_has_row_names(pred, Xcsc)
    pred <- predict(bst, Xcsc, type = "contrib")
    .expect_has_row_names(pred, Xcsc)
    pred <- predict(bst, as(Xcsc, "RsparseMatrix"), type = "contrib")
    .expect_has_row_names(pred, Xcsc)

    # sparse matrix without row names
    Xcopy <- Xcsc
    row.names(Xcopy) <- NULL
    pred <- predict(bst, Xcopy)
    .expect_doesnt_have_row_names(pred)
}

test_that("predict() keeps row names from data (regression)", {
    data("mtcars")
    X <- as.matrix(mtcars[, -1L])
    y <- as.numeric(mtcars[, 1L])
    dtrain <- lgb.Dataset(
      X
      , label = y
      , params = list(
        max_bins = 5L
        , min_data_in_bin = 1L
      )
    )
    bst <- lgb.train(
        data = dtrain
        , obj = "regression"
        , nrounds = 5L
        , verbose = VERBOSITY
        , params = list(min_data_in_leaf = 1L)
    )
    .check_all_row_name_expectations(bst, X)
})

test_that("predict() keeps row names from data (binary classification)", {
    data(agaricus.train, package = "lightgbm")
    X <- as.matrix(agaricus.train$data)
    y <- agaricus.train$label
    row.names(X) <- paste0("rname", seq(1L, nrow(X)))
    dtrain <- lgb.Dataset(X, label = y, params = list(max_bins = 5L))
    bst <- lgb.train(
        data = dtrain
        , obj = "binary"
        , nrounds = 5L
        , verbose = VERBOSITY
    )
    .check_all_row_name_expectations(bst, X)
})

test_that("predict() keeps row names from data (multi-class classification)", {
    data(iris)
    y <- as.numeric(iris$Species) - 1.0
    X <- as.matrix(iris[, names(iris) != "Species"])
    row.names(X) <- paste0("rname", seq(1L, nrow(X)))
    dtrain <- lgb.Dataset(X, label = y, params = list(max_bins = 5L))
    bst <- lgb.train(
        data = dtrain
        , obj = "multiclass"
        , params = list(num_class = 3L)
        , nrounds = 5L
        , verbose = VERBOSITY
    )
    .check_all_row_name_expectations(bst, X)
})

test_that("predictions for regression and binary classification are returned as vectors", {
    data(mtcars)
    X <- as.matrix(mtcars[, -1L])
    y <- as.numeric(mtcars[, 1L])
    dtrain <- lgb.Dataset(
      X
      , label = y
      , params = list(
        max_bins = 5L
        , min_data_in_bin = 1L
      )
    )
    model <- lgb.train(
      data = dtrain
      , obj = "regression"
      , nrounds = 5L
      , verbose = VERBOSITY
      , params = list(min_data_in_leaf = 1L)
    )
    pred <- predict(model, X)
    expect_true(is.vector(pred))
    expect_equal(length(pred), nrow(X))
    pred <- predict(model, X, type = "raw")
    expect_true(is.vector(pred))
    expect_equal(length(pred), nrow(X))

    data(agaricus.train, package = "lightgbm")
    X <- agaricus.train$data
    y <- agaricus.train$label
    dtrain <- lgb.Dataset(X, label = y)
    model <- lgb.train(
      data = dtrain
      , obj = "binary"
      , nrounds = 5L
      , verbose = VERBOSITY
    )
    pred <- predict(model, X)
    expect_true(is.vector(pred))
    expect_equal(length(pred), nrow(X))
    pred <- predict(model, X, type = "raw")
    expect_true(is.vector(pred))
    expect_equal(length(pred), nrow(X))
})

test_that("predictions for multiclass classification are returned as matrix", {
    data(iris)
    X <- as.matrix(iris[, -5L])
    y <- as.numeric(iris$Species) - 1.0
    dtrain <- lgb.Dataset(X, label = y)
    model <- lgb.train(
      data = dtrain
      , obj = "multiclass"
      , nrounds = 5L
      , verbose = VERBOSITY
      , params = list(num_class = 3L)
    )
    pred <- predict(model, X)
    expect_true(is.matrix(pred))
    expect_equal(nrow(pred), nrow(X))
    expect_equal(ncol(pred), 3L)
    pred <- predict(model, X, type = "raw")
    expect_true(is.matrix(pred))
    expect_equal(nrow(pred), nrow(X))
    expect_equal(ncol(pred), 3L)
})

test_that("predict type='class' returns predicted class for classification objectives", {
    data(agaricus.train, package = "lightgbm")
    X <- as.matrix(agaricus.train$data)
    y <- agaricus.train$label
    dtrain <- lgb.Dataset(X, label = y, params = list(max_bins = 5L))
    bst <- lgb.train(
        data = dtrain
        , obj = "binary"
        , nrounds = 5L
        , verbose = VERBOSITY
    )
    pred <- predict(bst, X, type = "class")
    expect_true(all(pred %in% c(0L, 1L)))

    data(iris)
    X <- as.matrix(iris[, -5L])
    y <- as.numeric(iris$Species) - 1.0
    dtrain <- lgb.Dataset(X, label = y)
    model <- lgb.train(
      data = dtrain
      , obj = "multiclass"
      , nrounds = 5L
      , verbose = VERBOSITY
      , params = list(num_class = 3L)
    )
    pred <- predict(model, X, type = "class")
    expect_true(all(pred %in% c(0L, 1L, 2L)))
})

test_that("predict type='class' returns values in the target's range for regression objectives", {
    data(agaricus.train, package = "lightgbm")
    X <- as.matrix(agaricus.train$data)
    y <- agaricus.train$label
    dtrain <- lgb.Dataset(X, label = y, params = list(max_bins = 5L))
    bst <- lgb.train(
        data = dtrain
        , obj = "regression"
        , nrounds = 5L
        , verbose = VERBOSITY
    )
    pred <- predict(bst, X, type = "class")
    expect_true(!any(pred %in% c(0.0, 1.0)))
})
