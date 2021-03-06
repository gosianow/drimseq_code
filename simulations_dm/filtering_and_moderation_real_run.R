######################################################
## ----- filtering_and_moderation_real_run
## <<filtering_and_moderation_real_run.R>>

# BioC 3.2
# Created 14 Jan 2015 

##############################################################################

Sys.time()

##############################################################################

library(BiocParallel)
library(pryr)
library(plyr)
library(dirmult)
library(limma)
library(DRIMSeq)
library(ggplot2)
library(reshape2)
library(tools)


##############################################################################
# Arguments for testing the code
##############################################################################

# rwd='/home/gosia/multinomial_project/simulations_dm/drimseq/'
# simulation_script='/home/gosia/R/drimseq_paper/simulations_dm/dm_simulate.R'
# workers=4
# sim_name='test_'
# run='run1'
# m=100 # Number of genes
# n=6 # Number of samples
# 
# min_feature_expr=0
# min_feature_prop=NULL
# 
# param_nm_path='/home/gosia/multinomial_project/simulations_dm/drimseq/dm_parameters_drimseq_0_3_3/kim_kallisto/nm_kim_kallisto_lognormal.txt'
# ### Common dispersion of gene expression
# param_nd_path='/home/gosia/multinomial_project/simulations_dm/drimseq/dm_parameters_drimseq_0_3_3/kim_kallisto/nd_common_kim_kallisto.txt'
# param_pi_path='/home/gosia/multinomial_project/simulations_dm/drimseq/dm_parameters_drimseq_0_3_3/kim_kallisto/prop_kim_kallisto_fcutoff.txt'
# ### Genewise dispersion of feature proportions
# param_gamma_path='/home/gosia/multinomial_project/simulations_dm/drimseq/dm_parameters_drimseq_0_3_3/kim_kallisto/disp_genewise_kim_kallisto_lognormal.txt'



##############################################################################
# Read in the arguments
##############################################################################

## Read input arguments
args <- (commandArgs(trailingOnly = TRUE))
for (i in 1:length(args)) {
  eval(parse(text = args[[i]]))
}

print(args)

print(rwd)
print(simulation_script)
print(workers)
print(sim_name)
print(run)
print(m)
print(n)
print(min_feature_expr)
print(min_feature_prop)
print(param_nm_path)
print(param_nd_path)
print(param_pi_path)
print(param_gamma_path)


##############################################################################

source(simulation_script)


### Proportions
pi <- read.table(param_pi_path, header = TRUE, sep = "\t", as.is = TRUE)
pi_list <- split(pi$proportions, pi$gene_id)


### Dispersion
params <- read.table(param_gamma_path, header = FALSE, sep = "\t")

sim_disp_common <- FALSE
sim_disp_genewise <- FALSE

### Common dispersion
if(ncol(params) == 1){
  g0 <- as.numeric(params)
  print(g0)
  sim_disp_common <- TRUE
}

### Genewise dispersion from lognormal distribution
if(ncol(params) == 2){
  g0_meanlog <- params[1, 2]
  g0_sdlog <- params[2, 2]
  print(g0_meanlog)
  print(g0_sdlog)
  sim_disp_genewise <- TRUE
}




### Mean gene expression
params <- read.table(param_nm_path, header = FALSE, sep = "\t")

nm_meanlog <- params[1, 2]
nm_sdlog <- params[2, 2]

print(nm_meanlog)
print(nm_sdlog)


# Negative binomial dispersion of gene expression
params <- read.table(param_nd_path, header = FALSE, sep = "\t")

nd <- as.numeric(params)

print(nd)




if(is.null(min_feature_expr)){
  min_feature_expr <- rep(0, length(min_feature_prop))
  out_suffix <- paste0("famr_min_feature_prop")
}


if(is.null(min_feature_prop)){
  min_feature_prop <- rep(0, length(min_feature_expr))
  out_suffix <- paste0("famr_min_feature_expr")
}



##############################################################################

dir.create(rwd, recursive = T, showWarnings = FALSE)
setwd(rwd)

out_dir <- "filtering_and_moderation_real/run/"
dir.create(out_dir, recursive = T, showWarnings = FALSE)


out_name <- paste0(sim_name, "n", n, "_", basename(file_path_sans_ext(param_nm_path)), "_", basename(file_path_sans_ext(param_nd_path)), "_", basename(file_path_sans_ext(param_pi_path)), "_",  basename(file_path_sans_ext(param_gamma_path)), "_")

out_name



if(workers > 1){
  BPPARAM <- MulticoreParam(workers = workers)
}else{
  BPPARAM <- SerialParam()
}


##############################################################################
### Simulations 
##############################################################################



### Random dispersion
if(sim_disp_genewise)
  g0 <- rlnorm(m, meanlog = g0_meanlog, sdlog = g0_sdlog)

### Random proportions
pi <- pi_list[sample(1:length(pi_list), m, replace = TRUE)]

### Random gene expression
nm <- round(rlnorm(m, meanlog = nm_meanlog, sdlog = nm_sdlog))

counts <- dm_simulate(m = m, n = 2*n, pi = pi, g0 = g0, nm = nm, nd = nd, mc.cores = workers)
print(head(counts))

group_split <- strsplit2(rownames(counts), ":")

d_org <- dmDSdata(counts = counts, gene_id = group_split[, 1], feature_id = group_split[, 2], sample_id = paste0("s", 1:ncol(counts)), group = rep(c("c1", "c2"), each = n))

names(g0) <- names(d_org@counts)
names(pi) <- names(d_org@counts)
names(nm) <- names(d_org@counts)




### Different filtering

est <- list()
fp <- list()

for(j in 1:length(min_feature_expr)){
  # j = 1
  print(min_feature_expr[j])
  print(min_feature_prop[j])
  
  d_tmp <- dmFilter(d_org, min_samps_gene_expr = 0, min_samps_feature_expr = n, min_samps_feature_prop = n, min_gene_expr = 0, min_feature_expr = min_feature_expr[j], min_feature_prop = min_feature_prop[j], max_features = Inf)
  
  keep_genes <- names(d_tmp@counts) # Not all the genes pass the filter 
  
  
  ### Use no moderation for dispersion estimation
  
  d <- dmDispersion(d_tmp, mean_expression = FALSE, common_dispersion = TRUE, genewise_dispersion = TRUE, disp_adjust = TRUE, disp_mode = "grid", disp_interval = c(0, 1e+05), disp_tol = 1e-08, disp_init = 100, disp_init_weirMoM = TRUE, disp_grid_length = 21, disp_grid_range = c(-10, 10), disp_moderation = "none", disp_prior_df = 0.1, disp_span = 0.3, prop_mode = "constrOptimG", prop_tol = 1e-12, verbose = FALSE, BPPARAM = BPPARAM)
  
  common_disp <- common_dispersion(d)
  
  d <- dmFit(d, dispersion = "genewise_dispersion", BPPARAM = BPPARAM)
  d <- dmTest(d, BPPARAM = BPPARAM)
  res <- results(d)
  
  est[[paste0("moderation_none", j)]] <- data.frame(gene_id = genewise_dispersion(d)$gene_id, est = round(genewise_dispersion(d)$genewise_dispersion, 2), true = round(g0[keep_genes], 2), pvalue = res$pvalue, min_feature_expr = min_feature_expr[j], min_feature_prop = min_feature_prop[j], q = sapply(pi[keep_genes], length), nm = nm[keep_genes], disp_estimator = "moderation_none")
  
  fp[[paste0("moderation_none", j)]] <- data.frame(fp = mean(res$pvalue < 0.05, na.rm = TRUE), min_feature_expr = min_feature_expr[j], min_feature_prop = min_feature_prop[j], disp_estimator = "moderation_none")
  
  rm("d")
  
  ### Use common moderation for dispersion estimation
  
  d <- dmDispersion(d_tmp, mean_expression = FALSE, common_dispersion = FALSE, genewise_dispersion = TRUE, disp_adjust = TRUE, disp_mode = "grid", disp_interval = c(0, 1e+05), disp_tol = 1e-08, disp_init = common_disp, disp_init_weirMoM = TRUE, disp_grid_length = 21, disp_grid_range = c(-10, 10), disp_moderation = "common", disp_prior_df = 0.1, disp_span = 0.3, prop_mode = "constrOptimG", prop_tol = 1e-12, verbose = FALSE, BPPARAM = BPPARAM)
  
  
  d <- dmFit(d, dispersion = "genewise_dispersion", BPPARAM = BPPARAM)
  d <- dmTest(d, BPPARAM = BPPARAM)
  res <- results(d)
  
  
  est[[paste0("moderation_common", j)]] <- data.frame(gene_id = genewise_dispersion(d)$gene_id, est = round(genewise_dispersion(d)$genewise_dispersion, 2), true = round(g0[keep_genes], 2), pvalue = res$pvalue, min_feature_expr = min_feature_expr[j], min_feature_prop = min_feature_prop[j], q = sapply(pi[keep_genes], length), nm = nm[keep_genes], disp_estimator = "moderation_common")
  
  fp[[paste0("moderation_common", j)]] <- data.frame(fp = mean(res$pvalue < 0.05, na.rm = TRUE), min_feature_expr = min_feature_expr[j], min_feature_prop = min_feature_prop[j], disp_estimator = "moderation_common")
  

  ### Use true dispersion estimates
  genewise_dispersion(d) <- g0[keep_genes]
  
  d <- dmFit(d, dispersion = "genewise_dispersion", BPPARAM = BPPARAM)
  d <- dmTest(d, BPPARAM = BPPARAM)
  res <- results(d)
  
  
  est[[paste0("true", j)]] <- data.frame(gene_id = genewise_dispersion(d)$gene_id, est = round(g0[keep_genes], 2), true = round(g0[keep_genes], 2), pvalue = res$pvalue, min_feature_expr = min_feature_expr[j], min_feature_prop = min_feature_prop[j], q = sapply(pi[keep_genes], length), nm = nm[keep_genes], disp_estimator = "true")
  
  fp[[paste0("true", j)]] <- data.frame(fp = mean(res$pvalue < 0.05, na.rm = TRUE), min_feature_expr = min_feature_expr[j], min_feature_prop = min_feature_prop[j], disp_estimator = "true")
  
  rm("d")
  rm("d_tmp")
  
}

est <- rbind.fill(est)
fp <- rbind.fill(fp)



write.table(est, paste0(out_dir, out_name, "est_", out_suffix ,"_", run,".txt"), quote = FALSE, sep = "\t", row.names = FALSE)
write.table(fp, paste0(out_dir, out_name, "fp_", out_suffix ,"_", run,".txt"), quote = FALSE, sep = "\t", row.names = FALSE)


sessionInfo()
