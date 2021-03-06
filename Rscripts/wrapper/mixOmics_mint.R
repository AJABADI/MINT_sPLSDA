## Wrapper for mixOmics' MINT method to integrate batches or protocols when cell types are known
## see the https://github.com/AJABADI/MINT_sPLSDA/tree/master/Rscripts/wrapper/quickstart for examples

######################### Wrapper output
## when   output = "sce": A SCE object with 1: MINT markers in rowData(sce)$mint_markers and 
##                                          2: MINT global components in reducedDim(sce)$mint_comps_global
##                                          3: MINT per-batch / protocol components in reducedDim(sce)$mint_comps_{name-of-batch}

## when   output = "both":  In addition to the above-mentioned SCE, the final mint.splsda object in the $mint slot as a list
## refer to quickstart for examples on how to visualise the mint.splsda object

#########################  Create a log file
# change to your own
# log_file =file.path("../Rscripts/wrapper/log", paste("mint.wrapper.run",format(Sys.time(), "%y_%m_%d"),"txt",sep = "."))
# file.create(log_file)
# cat(paste(format(Sys.time(), "%a %b %d %X %Y"), "start preprocessing...\n"), file = log_file, append = TRUE)

#########################  Wrapper
library(mixOmics)
library(SingleCellExperiment)
library(magrittr)

mixOmics_mint = function(
  sce = sce,                    ## sce object including batch information in sce$batch
  colData.batch = "batch",      ## name of the colData that inform known cell batch information
  colData.class = "mix",        ## name of the colData that inform known cell type information
  hvgs = NULL,                  ## one of rowData(sce) indicating whether to use highly variable genes. If NULL: use all genes, otherwise specify a string vector of hvgs
  ######### additional parameters for advanced users
  ncomp = 3,                    ## integer: number of components for dimension reduction (we advise nlevels(colData.class) - 1)
  keepX = c(50,50,50),          ## numeric vector of length ncomp indicating the number of genes to select on each component
  tune.keepX = NULL,            ## grid of number of genes to select and assess on each component during tuning (e.g. seq(10,100,10)), if NULL: tuning step not performed
  output = "sce",               ## c("sce", "both") If sce: returns sce with updated rowData and reducedDims. If both: returns a list of sce and mint.splsda object
  print.log = FALSE
){  
  tp = system.time({
    try_res = try({
      ######################### defaults
      dist = "mahalanobis.dist"  ## type of distance to use to calculate prediction, by default here set to  "mahalanobis.dist" but could use "max.distance", "centroids.dist", or "all"
      measure = "BER"            ## type of measure to calculate classification error rate. By default BER = Balanced error rate for unbalanced number of cells per cell type. 
      #########################  entry checks 
      ## return is valid
      if(inherits(try(output),"try-error" ))
        stop("output must be one of c('sce', 'both'")
      if(!output %in% c("sce", "both"))
        stop("output must be one of c('sce', 'both'")
      
      
      ## object is a sce
      if(!inherits(try(sce),"SingleCellExperiment"))
        stop("sce must be a SingleCellExperiment object")
      
      ## colData.batch is valid
      if(inherits(try(colData(sce)[[colData.batch]]), "try-error"))
        stop("colData.batch must be a string or number corresponding to one of colData(sce) ")
      ## colData.class is valid
      if(inherits(try(colData(sce)[[colData.class]]), "try-error"))
        stop("colData.class must be a string or number corresponding to one of colData(sce) ")
      
      ## hvgs valid
      if(inherits(try(hvgs), "try-error"))
        stop("invalid hvgs argument, please read the argument's description")
      
      if(!is.null(hvgs)){ ## if hvgs is not null, check and reduce sce
        if(!inherits(try(hvgs), "character"))
          stop("invalid hvgs input, please read the argument's descriptions")
        if(length(hvgs)>1 & !all(hvgs %in% rownames(sce))){ ## all given genes exist
          stop("some of the given hgvs do not exist in the sce")
        } else if (length(hvgs)==1) { ## if rowData given
          ## make sure it exists
          if(is.null(rowData(sce)[[hvgs]]))
            stop("hvgs does not correspond to a valid colData")
        }
        
        ## if hvgs is the name of rowData, get the string vector
        if (length(hvgs)==1){
          hvgs = rownames(sce)[rowData(sce)[[hvgs]]]
        }
        sce = sce[hvgs,]
      }
      
      batch = as.factor(colData(sce)[[colData.batch]])  ## factor for batches
      Y =     as.factor(colData(sce)[[colData.class]]) ## biological groups (e.g. cell types)
      
      {
        ## batch checks
        if(nlevels(batch)==0) ## if it's an invalid string
          stop("colData.batch does not correspond to a valid colData")
        if(nlevels(batch)==1) ## if there is one batch only
          stop("there must be more than one batch in the data to run MINT")
        
        ## Y (class) checks
        if(nlevels(Y)==0) ## if it's an invalid string
          stop("colData.class does not correspond to a valid colData")
        if(nlevels(Y)==1) ## if there is one cell type only
          stop("there must be more than one cell type in the data to run MINT")
      }
      
      
      {
        if (is.null(tune.keepX)){
          ## length of keepX is at least ncomp
          if (length(keepX)!=ncomp)
            stop ("The length of keepX should be ncomp")
        }
        
        ## ensure there are no duplicate cell names
        if(any(duplicated(colnames(sce)))){
          stop("There are duplicate cell names - change to make them unique")
        }
        
        ## ensure there are no duplicate gene names
        if(any(duplicated(rownames(sce)))){
          stop("There are duplicate gene names - change to make them unique")
        }
        
        ## get the log of counts if they already are not logged
        if (max(logcounts(sce))>100){
          logcounts(sce) = log2(logcounts(sce)+1)
        }
        
        ## MINT checker checks the rest
      }
      
      ###################################### MINT sPLSDA
      
      ## check if it needs to be tuned or optimised:
      if(!is.null(tune.keepX)){
        ## tune the number of markers
        mint.tune = tune.mint.splsda(
          X = t(logcounts(sce)),
          Y = Y,
          study =  batch,
          ## get the optimum for measure and dist
          ncomp=ncomp,
          ## assess tune.keepX number of features:
          test.keepX = tune.keepX,
          ## use dist to estimate the classification error rate
          dist = dist,
          measure=measure,
          progressBar = TRUE)
        
        ## change keepX to the tuned vector
        keepX = mint.tune$choice.keepX
      }
      
      
      ## Run mint.splsda
      mint.res = mint.splsda(
        X = t(logcounts(sce)),
        Y = Y,
        study = batch,
        ncomp=ncomp,
        keepX = keepX
      )
      
      ## get a vector of marker genes for output in rowData(sce)
      comp =1
      markers = NULL
      while(comp <= ncomp){
        markers = c(markers, selectVar(mint.res, comp = comp)$name)
        comp = comp+1
      }
      ## add a logical rowData as to whether the gene is a marker
      rowData(sce)$mint_marker <- rownames(sce) %in% markers
      ## add the global and per-study sPLSDA components for visualisation to reducedDim(sce)
      reducedDim(sce, "mint_comps_global") = mint.res$variates$X ## a matrix containing the global components
      
      ## add per-batch components in a loop
      for (i in levels(batch)){
        ## initialise it as the same dimensions and col/row names as global
        reducedDim(sce, paste0("mint_comps_",i)) = mint.res$variates$X
        ## make all NA
        reducedDim(sce, paste0("mint_comps_",i))[
          is.numeric(reducedDim(sce, paste0("mint_comps_",i)))] = NA
        
        ## replace the values for cells from batch i
        batch.cells = rownames(mint.res$variates.partial$X[[i]])
        reducedDim(sce, paste0("mint_comps_",i))[batch.cells,] = mint.res$variates.partial$X[[i]]
      }
      
    })
    ###################################### outputs
    
    if (class(try_res) == "try-error" & print.log) {
      cat(paste(format(Sys.time(), "%a %b %d %X %Y. ERROR: "), print(try_res),"\n"), file = log_file, append = TRUE)
    }
  })
  
  method_name = "mixOmics_mint"
  method_type = "visualisation"
  if (!is.null(metadata(sce)$running_time)){
    metadata(sce)$running_time = rbind(metadata(sce)$running_time, data.frame(method=method_name, method_type=method_type, time=unname(tp)[1]))
  }else{
    metadata(sce)$running_time = data.frame(method=method_name,method_type=method_type,time=unname(tp)[1])
  }
  
  out = sce
  if (output == "both" & !(class(try_res) == "try-error")){
    mint_out = list("splsda" = mint.res)
    if(!is.null(tune.keepX)){
      mint_out$tune = mint.tune
    }
    out = list("sce"=sce, "mint" = mint_out)
  }
  return(out)
}
