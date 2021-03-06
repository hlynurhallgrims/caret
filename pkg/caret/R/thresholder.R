#' Generate Data to Choose a Probability Threshold
#' 
#' This function uses the resampling results from a \code{\link{train}}
#'  object to generate performance statistics over a set of probability
#'  thresholds for two-class problems. 
#' 
#' @param x A \code{\link{train}} object where the values of
#'  \code{savePredictions} was either \code{TRUE}, \code{"all"},
#'  or \code{"final"} in \code{\link{trainControl}}. Also, the 
#'  control argument \code{clasProbs} should have been \code{TRUE}.
#' @param threshold A numeric vector of candidate probability thresholds
#'  between [0,1]. If the class probability corresponding to the first
#'  level of the outcome is greater than the threshold, the data point
#'  is classified as that level. 
#' @param final A logical: should only the final tuning parameters
#'   chosen by \code{\link{train}} be used when 
#'   \code{savePredictions = 'all'}?
#' @return A data frame with columns for each of the tuning parameters
#'  from the model along with an additional column called
#'  \code{prob_threshold} for the probability threshold. There are
#'  also columns for summary statistics averaged over resamples with
#'  column names \code{Sensitivity}, \code{Specificity}, \code{J},
#'  \code{Dist}. The last two correspond to Youden's J statistic 
#'  and the distance to the best possible cutoff (i.e. perfect
#'  sensitivity and specificity). 
#' @export
#' @importFrom plyr ddply
#' @examples 
#' \dontrun{
#' set.seed(2444)
#' dat <- twoClassSim(500, intercept = -10)
#' table(dat$Class)
#' 
#' ctrl <- trainControl(method = "cv", 
#'                      classProbs = TRUE,
#'                      savePredictions = "all",
#'                      summaryFunction = twoClassSummary)
#' 
#' set.seed(2863)
#' mod <- train(Class ~ ., data = dat, 
#'              method = "rda",
#'              tuneLength = 4,
#'              metric = "ROC",
#'              trControl = ctrl)
#' 
#' resample_stats <- thresholder(mod, 
#'                               threshold = seq(.5, 1, by = 0.05), 
#'                               final = TRUE)
#' 
#' ggplot(resample_stats, aes(x = prob_threshold, y = J)) + 
#'   geom_point()
#' ggplot(resample_stats, aes(x = prob_threshold, y = Dist)) + 
#'   geom_point()
#' ggplot(resample_stats, aes(x = prob_threshold, y = Sensitivity)) + 
#'   geom_point() + 
#'   geom_point(aes(y = Specificity), col = "red")
#' }
thresholder <- function(x, threshold, final = TRUE) {
  if(!inherits(x, "train"))
    stop("`x` should be an object of class 'train'", 
         call. = FALSE)
  if (!mod$control$classProbs)
    stop("`classProbs` must be TRUE in `trainControl`",
         call. = FALSE)
  if (is.null(threshold))
    stop("Please supply probability threshold values.",
         call. = FALSE)
  if (any(threshold > 1 | threshold < 0))
    stop("`threshold` should be on [0,1]", call. = FALSE)
  
  if (is.logical(x$control$savePredictions)) {
    if (!x$control$savePredictions)
      stop("`savePredictions` should be TRUE, 'all', or 'final'")
  } else {
    if (x$control$savePredictions == "none")
      stop("`savePredictions` should be TRUE, 'all', or 'final'")
  }
  if (length(levels(x$pred$obs)) > 2)
    stop("For two class problems only", call. = TRUE)
  
  disc <- c("pred", "rowIndex", x$levels[-1])
  
  ## Expand the predicted values with the candidate values of
  ## the threshold
  pred_dat <- expand_preds(if (final)
    merge(x$pred, x$bestTune)
    else
      x$pred,
    threshold,
    disc)
  
  param <- c("Resample", names(x$bestTune), "prob_threshold")
  
  ## Based on the threshold, recode the predicted classes
  pred_dat <- ddply(pred_dat, .variables = param, recode)
  
  ## Compute statistics per threshold and tuning parameters
  pred_stats <- ddply(pred_dat, .variables = param,  stats)
  
  ## Summarize over resamples
  pred_resamp <- ddply(pred_stats, .variables = param[-1],
                       summ_stats)
  pred_resamp
}

expand_preds <- function(df, th, excl = NULL) {
  th <- unique(th)
  nth <- length(th)
  ndf <- nrow(df)
  if (!is.null(excl))
    df <- df[, !(names(df) %in% excl), drop = FALSE]
  df <- df[rep(1:nrow(df), times = nth),]
  df$prob_threshold <- rep(th, each = ndf)
  df
}


recode <- function(dat) {
  lvl <- levels(dat$obs)
  dat$pred <- ifelse(dat[, lvl[1]] > dat$prob_threshold,
                     lvl[1], lvl[2])
  dat$pred <- factor(dat$pred, levels = lvl)
  dat
}

stats <- function(dat) {
  tab <- caret::confusionMatrix(dat$pred, dat$obs,
                                positive = levels(dat$obs)[1])
  res <- tab$byClass[c("Sensitivity", "Specificity")]
  res <- c(res,
           res["Sensitivity"] + res["Specificity"] - 1,
           sqrt((res["Sensitivity"] - 1) ^ 2 + (res["Specificity"] - 1) ^ 2))
  names(res)[3:4] <- c("J", "Dist")
  res
}

stat_names <- c("Sensitivity", "Specificity", "J", "Dist")

summ_stats <- function(x, cols = stat_names)
  colMeans(x[, cols, drop = FALSE])

