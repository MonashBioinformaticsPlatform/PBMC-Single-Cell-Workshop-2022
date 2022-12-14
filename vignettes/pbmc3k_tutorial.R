
# This content is the [Seurat PBMC tutorial](https://satijalab.org/seurat/articles/pbmc3k_tutorial.html) with an additional sections on SingleR for cell type classification and Harmony for dataset integration.

# Please go to the [installation page](https://monashbioinformaticsplatform.github.io/Single-Cell-Workshop/installation.html) for instructions on how to install the libraries used for this workshop. There are also instructions for downloading the [raw data](http://cf.10xgenomics.com/samples/cell/pbmc3k/pbmc3k_filtered_gene_bc_matrices.tar.gz) there as well.

# [The workshop homepage is here](index.html)


# Setup the Seurat Object --------

# For this tutorial, we will be analyzing the a dataset of Peripheral Blood Mononuclear Cells (PBMC) freely available from 10X Genomics. There are 2,700 single cells that were sequenced on the Illumina NextSeq 500. The raw data can be found [here](https://cf.10xgenomics.com/samples/cell/pbmc3k/pbmc3k_filtered_gene_bc_matrices.tar.gz). In this example, the raw data has already been processed through the cellranger pipeline and we are working with the pipeline output.

# Cellranger produces three files:

# * barcodes.tsv - a text file containing the list of cell barcodes for the sample
# * features.tsv - a text file containing information about the features in the dataset. For this specific dataset, this file instead is called genes.tsv as it has been produced by an older version of cellranger. It contains the list of gene annotations the data was counted against. Now since cellranger can be used with different types of experiment (e.g ATAC, hashtag oligos, cell surface proteins) - the word 'feature' is used instead as you might have the hashtag oligo names listed here or peak names
# * matrix.mtx - this sparse matrix encodes the count data. It only includes non-zero data and the first two columns maps to the information contain in the features.tsv and the barcodes.tsv files. The first three rows in the file contains information about the file type - the type of file it is and the dimensions of data ie the number of features, the number of cells and then the total number of rows containing data in the matrix file (excluding the first rows).

# The first column contains the row number of the feature in the features.tsv file whereas the second column contains the row number for the cell barcode in the barcodes.tsv file. It's the third column that contains the UMI count.

32709 1 4
32707 1 1
32706 1 10
32704 1 1
32703 1 5

# The count data is stored in this sparse format with the column and row information stored in separate files and only the non-zero counts kept. This representation of the data is an efficient way to store the data and most single cell analysis packages will have a way to read such data in and represent it as a matrix.

# We start by reading in the data. The Read10X() function reads in the output of the [cellranger](https://support.10xgenomics.com/single-cell-gene-expression/software/pipelines/latest/what-is-cell-ranger) pipeline from 10X, returning a unique molecular identified (UMI) count matrix. The values in this matrix represent the number of molecules for each feature (i.e. gene; row) that are detected in each cell (column).

# We next use the count matrix to create a Seurat object. The object serves as a container that contains both data (like the count matrix) and analysis (like PCA, or clustering results) for a single-cell dataset. For a technical discussion of the Seurat object structure, check out the [GitHub Wiki](https://github.com/satijalab/seurat/wiki/Seurat). For example, the count matrix is stored in pbmc@assays$RNA@counts.

library(dplyr)
library(ggplot2)
library(Seurat)
library(patchwork)
library(clustree)
library(RColorBrewer)

# Load the PBMC dataset
pbmc.data <- Read10X(data.dir = "filtered_gene_bc_matrices/hg19/") # This creates a sparse matrix

# Initialize the Seurat object with the raw (non-normalized data).
pbmc <- CreateSeuratObject(counts = pbmc.data, project = "pbmc3k", min.cells = 3, min.features = 200)
pbmc

#   **What does data in a count matrix look like?**

# Lets examine a few genes in the first thirty cells
pbmc.data[c("CD3D","TCL1A","MS4A1"), 1:30]

# The . values in the matrix represent 0s (no molecules detected). Since most values in an scRNA-seq matrix are 0,  Seurat uses a sparse-matrix representation whenever possible. This results in significant memory and speed savings for Drop-seq/inDrop/10x data.

dense.size <- object.size(as.matrix(pbmc.data))
dense.size
sparse.size <- object.size(pbmc.data)
sparse.size
dense.size / sparse.size


#### Discussion: The Seurat Object in R --------

# Lets take a look at the seurat object we have just created in R, pbmc.

# To accomodate the complexity of data arising from a single cell RNA seq experiment, the seurat object keeps this as a container of multiple data tables that are linked.

# The functions in Seurat can access parts of the data object for analysis and visualisation, we will cover this later on.

# There are a couple of concepts to discuss here.

# **Class**

# These are essentially data containers in R as a class, and can accessed as a variable in the R environment.

# Classes are pre-defined and can contain multiple data tables and metadata. For Seurat, there are several types.

# * Seurat - the main data class, contains all the data.
# * Assay - found within the Seurat object. Depending on the experiment a cell could have data on RNA, ATAC etc measured
# * DimReduc - for PCA and UMAP

# **Slots**

# Slots are parts within a class that contain specific data. These can be lists, data tables and vectors and can be accessed with conventional R methods.

# **Data Access**

# Many of the functions in Seurat operate on the data class and slots within them seamlessly. There maybe occasion to access these separately to hack them, however this is an advanced analysis method.

# The ways to access the slots can be through methods for the class (functions) or with standard R accessor nomenclature.

# **Examples of accessing a Seurat object**

# The assays slot in pbmc can be accessed with GetAssay(pbmc) or pbmc@assays.

# The RNA assay can be accessed from this with GetAssay(pbmc, assay = "RNA) or pbmc@assays$RNA.

# We can also use the GetAssayData function and specify which slot we'd like to extract data.

GetAssayData(object = pbmc, slot = "data")[1:5, 1:5]

# We often want to access assays, so Seurat gives us a shortcut pbmc$RNA. You may sometimes see an alternative notation pbmc[["RNA"]].

# In general, slots that are always in an object are accessed with @ and things that may be different in different data sets are accessed with $. However, it generally is safer to access data using the provided functions - if the way the Seurat object is structured changes in a future update, the functions should remain useable whereas code that directly references the Seurat structure with @ and $ may no longer run.

# **Have a go**

# Use str to look at the structure of the Seurat object pbmc.

# What is in the meta.data slot within your Seurat object currently? What type of data is contained here?

# Where is our count data within the Seurat object?

# The PBMC dataset is a gene-expression dataset and is stored in an assay called RNA. What other types of assays could we have stored in a Seurat object if we had a different type of dataset?


# Standard pre-processing workflow --------

# The steps below encompass the standard pre-processing workflow for scRNA-seq data in Seurat. These represent the selection and filtration of cells based on QC metrics, data normalization and scaling, and the detection of highly variable features.


## QC and selecting cells for further analysis --------


### Why do we need to do this? --------

# Low quality cells can add noise to your results leading you to the wrong biological conclusions. Using only good quality cells helps you to avoid this.
# Reduce noise in the data by filtering out low quality cells such as dying or stressed cells (high mitochondrial expression) and cells with few features that can reflect empty droplets.

# ###

# Seurat allows you to easily explore QC metrics and filter cells based on any user-defined criteria. A few QC metrics [commonly used](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC4758103/) by the community include

# * The number of unique genes detected in each cell.
#     + Low-quality cells or empty droplets will often have very few genes
#     + Cell doublets or multiplets may exhibit an aberrantly high gene count
# * Similarly, the total number of molecules detected within a cell (correlates strongly with unique genes)
# * The percentage of reads that map to the mitochondrial genome
#     + Low-quality / dying cells often exhibit high numbers of mitochondrial transcripts. Be aware that different cell types have different mitochondrial expression, adjust this parameter accordently.
#     + We calculate mitochondrial QC metrics with the PercentageFeatureSet() function, which calculates the percentage of counts originating from a set of features
#     + We use the set of all genes starting with MT- as a set of mitochondrial genes

# The $ operator can add columns to object metadata. This is a great place to stash QC stats
pbmc$percent.mt <- PercentageFeatureSet(pbmc, pattern = "^MT-")


#### Challenge: The meta.data slot in the Seurat object --------

# Where are QC metrics stored in Seurat?

# * The number of unique genes and total molecules are automatically calculated during CreateSeuratObject()
#     + You can find them stored in the object meta data

# What do you notice has changed within the meta.data table now that we have calculated mitochondrial gene proportion?

# Could we add more data into the meta.data table?

# ###

# In the example below, we visualize QC metrics, and use these to filter cells.

# * We filter cells that have unique feature counts less than 200
# * We filter cells that have >5% mitochondrial counts


#Visualize QC metrics as a violin plot
VlnPlot(pbmc, features = c("nFeature_RNA", "nCount_RNA", "percent.mt"), ncol = 3)

# FeatureScatter is typically used to visualize feature-feature relationships, but can be used for anything calculated by the object, i.e. columns in object metadata, PC scores etc.

plot1 <- FeatureScatter(pbmc, feature1 = "nCount_RNA", feature2 = "percent.mt")
plot2 <- FeatureScatter(pbmc, feature1 = "nCount_RNA", feature2 = "nFeature_RNA")
plot1 + plot2

# Lets look at the number of features (genes) to the percent mitochondrial genes plot.

plot3 <- FeatureScatter(pbmc, feature1 = "nFeature_RNA", feature2 = "percent.mt")
plot3


#### Challenge: Ribosomal gene expression as a QC metric --------

# Ribosomal gene expression could be another factor to look into your cells within your experiment.

# Create more columns of metadata using PercentageFeatureSet function, this time search for ribosomal genes. We can  calculate the percentage for the large subunit (RPL) and small subunit (RPS) ribosomal genes.

# Use FeatureScatter to plot combinations of metrics available in metadata. How is the mitochondrial gene percentage related to the ribosomal gene percentage? What can you see? Discuss in break out.

# **Code for challenge**
# Create new meta.data columns to contain percentages of the large and small ribosomal genes.

# Then plot a scatter plot with this new data. You should find that the large and small ribosomal subunit genes are correlated within cell.

# What about with mitochondria and gene, feature counts?

# These are the cells you may want to exclude.

# **Advanced Challenge**
# Highlight cells with very low percentage of ribosomal genes, create a new column in the meta.data table and with FeatureScatter make a plot of the RNA count and mitochondrial percentage with the cells with very low ribosomal gene perentage.

# ###

# Okay we are happy with our thresholds for mitochondrial percentage in cells, lets apply them and subset our data. This will remove the cells we think are of poor quality.

pbmc <- subset(pbmc, subset = nFeature_RNA > 200 & percent.mt < 5)

# Lets replot the feature scatters and see what they look like.

plot5 <- FeatureScatter(pbmc, feature1 = "nCount_RNA", feature2 = "percent.mt")
plot6 <- FeatureScatter(pbmc, feature1 = "nCount_RNA", feature2 = "nFeature_RNA")

plot5 + plot6


# Normalizing the data --------


### Why do we need to do this? --------

# The sequencing depth can be different per cell. This can bias the counts of expression showing higher numbers for more sequenced cells leading to the wrong biological conclusions. To correct this the feature counts are normalized.

# ###

# After removing unwanted cells from the dataset, the next step is to normalize the data. By default, we employ a global-scaling normalization method "LogNormalize" that normalizes the feature expression measurements for each cell by the total expression, multiplies this by a scale factor (10,000 by default), and log-transforms the result. Normalized values are stored in pbmc$RNA@data.

pbmc <- NormalizeData(pbmc, normalization.method = "LogNormalize", scale.factor = 1e4)

# For clarity, in this previous line of code (and in future commands), we provide the default values for certain parameters in the function call. However, this isn't required and the same behavior can be achieved with:

pbmc <- NormalizeData(pbmc)


# Identification of highly variable features (feature selection) --------


### Why do we need to do this? --------

# Identifying the most variable features allows retaining the real biological variability of the data and reduce noise in the data.

# ###

# We next calculate a subset of features that exhibit high cell-to-cell variation in the dataset (i.e, they are highly expressed in some cells, and lowly expressed in others). The Seurat developers and [others](https://www.nature.com/articles/nmeth.2645) have found that focusing on these genes in downstream analysis helps to highlight biological signal in single-cell datasets.

# The procedure in Seurat is described in detail [here](https://doi.org/10.1016/j.cell.2019.05.031), and improves on previous versions by directly modeling the mean-variance relationship inherent in single-cell data, and is implemented in the FindVariableFeatures() function. By default, we return 2,000 features per dataset. These will be used in downstream analysis, like PCA.

pbmc <- FindVariableFeatures(pbmc, selection.method = 'vst', nfeatures = 2000)

# Identify the 10 most highly variable genes
top10 <- head(VariableFeatures(pbmc), 10)

# plot variable features with and without labels
plot1 <- VariableFeaturePlot(pbmc)
plot2 <- LabelPoints(plot = plot1, points = top10, repel = TRUE)
plot1 + plot2


#### Challenge: Labelling Genes of Interest --------

# What if we wanted to look at genes we are specifically interested in? We can create a character vector of gene names and apply that to this plot.

# Make a plot with labels for the genes IL8, IDH2 and CXCL3.


## Scaling the data --------

# Next, we apply a linear transformation ('scaling') that is a standard pre-processing step prior to dimensional reduction techniques like PCA. The ScaleData() function:

# * Shifts the expression of each gene, so that the mean expression across cells is 0
# * Scales the expression of each gene, so that the variance across cells is 1
#     + This step gives equal weight in downstream analyses, so that highly-expressed genes do not dominate
# * The results of this are stored in pbmc$RNA@scale.data

all.genes <- rownames(pbmc)
pbmc <- ScaleData(pbmc, features = all.genes)

#   **This step takes too long! Can I make it faster?**

# Scaling is an essential step in the Seurat workflow, but only on genes that will be used as input to PCA. Therefore, the default in ScaleData() is only to perform scaling on the previously identified variable features (2,000 by default). To do this, omit the features argument in the previous function call, i.e.

# pbmc <- ScaleData(pbmc)

# Your PCA and clustering results will be unaffected. However, Seurat heatmaps (produced as shown below with DoHeatmap()) require genes in the heatmap to be scaled, to make sure highly-expressed genes don't dominate the heatmap. To make sure we don't leave any genes out of the heatmap later, we are scaling all genes in this tutorial.

#   **How can I remove unwanted sources of variation, as in Seurat v2?**

# In Seurat v2 we can also use the ScaleData() function to remove unwanted sources of variation from a single-cell dataset. For example, we could 'regress out' heterogeneity associated with (for example) cell cycle stage, or mitochondrial contamination. These features are still supported in ScaleData() in Seurat v3, i.e.:

# pbmc <- ScaleData(pbmc, vars.to.regress = 'percent.mt')

# However, particularly for advanced users who would like to use this functionality, the Seurat developers recommend their new normalization workflow, SCTransform(). The method is described in their [paper](https://genomebiology.biomedcentral.com/articles/10.1186/s13059-019-1874-1), with a separate vignette using Seurat v3 [here](sctransform_vignette.html). As with ScaleData(), the function SCTransform() also includes a vars.to.regress parameter.


# Dimensionality reduction --------


### Why do we need to do this? --------

# Imagine each gene represents a dimension - or an axis on a plot. We could plot the expression of two genes with a simple scatterplot. But a genome has thousands of genes - how do you collate all the information from each of those genes in a way that allows you to visualise it in a 2 dimensional image. This is where dimensionality reduction comes in, we calculate meta-features that contains combinations of the variation of different genes. From thousands of genes, we end up with 10s of meta-features

# ###


## Perform linear dimensional reduction --------

# Next we perform PCA on the scaled data. By default, only the previously determined variable features are used as input, but can be defined using features argument if you wish to choose a different subset.

pbmc <- RunPCA(pbmc, features = VariableFeatures(object = pbmc))

# Seurat provides several useful ways of visualizing both cells and features that define the PCA, including VizDimReduction(), DimPlot(), and DimHeatmap()

# Examine and visualize PCA results a few different ways
print(pbmc$pca, dims = 1:5, nfeatures = 5)
VizDimLoadings(pbmc, dims = 1:2, reduction = 'pca')
DimPlot(pbmc, reduction = 'pca')

# In particular DimHeatmap() allows for easy exploration of the primary sources of heterogeneity in a dataset, and can be useful when trying to decide which PCs to include for further downstream analyses. Both cells and features are ordered according to their PCA scores. Setting cells to a number plots the 'extreme' cells on both ends of the spectrum, which dramatically speeds plotting for large datasets. Though clearly a supervised analysis, we find this to be a valuable tool for exploring correlated feature sets.

DimHeatmap(pbmc, dims = 1, cells = 500, balanced = TRUE)

DimHeatmap(pbmc, dims = 1:15, cells = 500, balanced = TRUE)


## Determine the 'dimensionality' of the dataset --------

# To overcome the extensive technical noise in any single feature for scRNA-seq data, Seurat clusters cells based on their PCA scores, with each PC essentially representing a 'metafeature' that combines information across a correlated feature set. The top principal components therefore represent a robust compression of the dataset. However, how many components should we choose to include? 10? 20? 100?

# One heuristic method that can be used is an 'Elbow plot': a ranking of principle components based on the percentage of variance explained by each one (ElbowPlot() function). In this example, we can observe an 'elbow' around PC9-10, suggesting that the majority of true signal is captured in the first 10 PCs.

ElbowPlot(pbmc)

# Identifying the true dimensionality of a dataset -- can be challenging/uncertain for the user. The Seurat developers suggest these three approaches to consider. The first is more supervised, exploring PCs to determine relevant sources of heterogeneity, and could be used in conjunction with GSEA for example. The second implements a statistical test based on a random null model, but is time-consuming for large datasets, and may not return a clear PC cutoff. The third is a heuristic that is commonly used, and can be calculated instantly. In this example, all three approaches yielded similar results, but we might have been justified in choosing anything between PC 7-12 as a cutoff.

# We use 10 here, but encourage users to consider the following:

# * Dendritic cell and NK aficionados may recognize that genes strongly associated with PCs 12 and 13 define rare immune subsets (i.e. MZB1 is a marker for plasmacytoid DCs). However, these groups are so rare, they are difficult to distinguish from background noise for a dataset of this size without prior knowledge.
# * We encourage users to repeat downstream analyses with a different number of PCs (10, 15, or even 50!). As you will observe, the results often do not differ dramatically.
# * We advise users to err on the higher side when choosing this parameter. For example, performing downstream analyses with only 5 PCs does significantly and adversely affect results.


## Run non-linear dimensional reduction (UMAP/tSNE) --------

# Seurat offers several non-linear dimensional reduction techniques, such as tSNE and UMAP, to visualize and explore these datasets. The goal of these algorithms is to learn the underlying manifold of the data in order to place similar cells together in low-dimensional space. Cells within the graph-based clusters determined above should co-localize on these dimension reduction plots. As input to the UMAP and tSNE, we suggest using the same PCs as input to the clustering analysis.

# If you haven't installed UMAP, you can do so via reticulate::py_install(packages = "umap-learn")
pbmc <- RunUMAP(pbmc, dims = 1:10)

# note that you can set `label = TRUE` or use the LabelClusters function to help label individual clusters
DimPlot(pbmc, reduction = 'umap')


#### Challenge: Try different cluster settings --------

# Run FindNeighbours and FindClusters again, with a different number of dimensions or with a different resolution. Examine the resulting clusters using DimPlot.

# To maintain the flow of this tutorial, please put the output of this exploration in a different variable, such as pbmc2!


# Cluster the cells --------


### Why do we need to do this? --------

# Clustering the cells will allow you to visualise the variability of your data, can help to segregate cells into cell types.

# ###

# Seurat v3 applies a graph-based clustering approach, building upon initial strategies in ([Macosko *et al*](http://www.cell.com/abstract/S0092-8674(15)00549-8)). Importantly, the *distance metric* which drives the clustering analysis (based on previously identified PCs) remains the same. However, the Seurat approach to partitioning the cellular distance matrix into clusters has dramatically improved. The Seurat approach was heavily inspired by recent manuscripts which applied graph-based clustering approaches to scRNA-seq data [[SNN-Cliq, Xu and Su, Bioinformatics, 2015]](http://bioinformatics.oxfordjournals.org/content/early/2015/02/10/bioinformatics.btv088.abstract) and CyTOF data [[PhenoGraph, Levine *et al*., Cell, 2015]](http://www.ncbi.nlm.nih.gov/pubmed/26095251). Briefly, these methods embed cells in a graph structure - for example a K-nearest neighbor (KNN) graph, with edges drawn between cells with similar feature expression patterns, and then attempt to partition this graph into highly interconnected 'quasi-cliques' or 'communities'.

# As in PhenoGraph, Seurat first constructs a KNN graph based on the euclidean distance in PCA space, and then refines the edge weights between any two cells based on the shared overlap in their local neighborhoods (Jaccard similarity). This step is performed using the FindNeighbors() function, and takes as input the previously defined dimensionality of the dataset (first 10 PCs).

# To cluster the cells, Seurat next applies modularity optimization techniques such as the Louvain algorithm (default) or SLM [[SLM, Blondel *et al*., Journal of Statistical Mechanics]](http://dx.doi.org/10.1088/1742-5468/2008/10/P10008), to iteratively group cells together, with the goal of optimizing the standard modularity function. The FindClusters() function implements this procedure, and contains a resolution parameter that sets the 'granularity' of the downstream clustering, with increased values leading to a greater number of clusters. We find that setting this parameter between 0.4-1.2 typically returns good results for single-cell datasets of around 3K cells. Optimal resolution often increases for larger datasets. The clusters can be found using the Idents() function.

pbmc <- FindNeighbors(pbmc, dims = 1:10)


# Try different resolutions when clustering to identify the varibility of your data. The function [FindClusters](https://satijalab.org/seurat/reference/findclusters) is used to cluster the data

resolution= 2

pbmc <- FindClusters(
  object = pbmc,
  reduction.type = "umap",
  resolution = seq(0.1,resolution,0.1),
  dims.use = 1:10,
  save.SNN = TRUE
)

# the different clustering created
names(pbmc@meta.data)

# Look at cluster IDs of the first 5 cells
head(Idents(pbmc), 5)

# Plot a [clustree](https://cran.r-project.org/web/packages/clustree/vignettes/clustree.html) to decide how many clusters you have and what resolution capture them.

clustree(pbmc, prefix = "RNA_snn_res.")+theme(legend.key.size = unit(0.05, 'cm'))

# Name cells with the corresponding cluster name at the resolution you pick. This case we are happy with 0.5.

#The name of the cluster is prefixed with "RNA_snn_res" and the number of the resolution
Idents(pbmc)<-pbmc$RNA_snn_res.0.5

# Plot the UMAP with colored clusters with [Dimplot](https://satijalab.org/seurat/reference/dimplot)

DimPlot(pbmc,label = TRUE, repel = TRUE,label.box=TRUE)+ NoLegend()

# You can save the object at this point so that it can easily be loaded back in without having to rerun the computationally intensive steps performed above, or easily shared with collaborators.

saveRDS(pbmc, file = "pbmc_tutorial.rds")


# Cell type annotation --------


## Finding differentially expressed features (cluster biomarkers) --------


### Why do we need to do this? --------

# Single cell data helps to segragate cell types. Use markers to identify cell types. warning: In this example the cell types/markers are well known and making this step easy, but in reality this step needs the experts curation.

# ###

# Seurat can help you find markers that define clusters via differential expression. By default, it identifies positive and negative markers of a single cluster (specified in ident.1), compared to all other cells.  FindAllMarkers() automates this process for all clusters, but you can also test groups of clusters vs. each other, or against all cells.

# The min.pct argument requires a feature to be detected at a minimum percentage in either of the two groups of cells, and the thresh.test argument requires a feature to be differentially expressed (on average) by some amount between the two groups. You can set both of these to 0, but with a dramatic increase in time - since this will test a large number of features that are unlikely to be highly discriminatory. As another option to speed up these computations, max.cells.per.ident can be set. This will downsample each identity class to have no more cells than whatever this is set to. While there is generally going to be a loss in power, the speed increases can be significant and the most highly differentially expressed features will likely still rise to the top.

# find all markers of cluster 2
cluster2.markers <- FindMarkers(pbmc, ident.1 = 2, min.pct = 0.25)
head(cluster2.markers, n = 5)
# find all markers distinguishing cluster 5 from clusters 0 and 3
cluster5.markers <- FindMarkers(pbmc, ident.1 = 5, ident.2 = c(0, 3), min.pct = 0.25)
head(cluster5.markers, n = 5)
# find markers for every cluster compared to all remaining cells, report only the positive ones
pbmc.markers <- FindAllMarkers(pbmc, only.pos = TRUE, min.pct = 0.25, logfc.threshold = 0.25)
pbmc.markers %>% group_by(cluster) %>% slice_max(n = 2, order_by = avg_log2FC)

# Seurat has several tests for differential expression which can be set with the test.use parameter (see the Seurat [differential expression vignette](https://satijalab.org/seurat/articles/de_vignette.html) for details). For example, the ROC test returns the 'classification power' abs(AUC-0.5)*2 for any individual marker, ranging from 0 = random to 1 = perfect.

cluster0.markers <- FindMarkers(pbmc, ident.1 = 0, logfc.threshold = 0.25, test.use = "roc", only.pos = TRUE)

# Seurat includes several tools for visualizing marker expression. VlnPlot() (shows expression probability distributions across clusters), and FeaturePlot() (visualizes feature expression on a tSNE or PCA plot) are some of the most commonly used visualizations. Additional ways to explore your dataset include RidgePlot(), CellScatter(), and DotPlot().

VlnPlot(pbmc, features = c("MS4A1", "CD79A"))
# you can plot raw counts as well
VlnPlot(pbmc, features = c("NKG7", "PF4"), slot = 'counts', log = TRUE)
FeaturePlot(pbmc, features = c("MS4A1", "GNLY", "CD3E", "CD14", "FCER1A", "FCGR3A", "LYZ", "PPBP", "CD8A"))

#   **Other useful plots**
# These are ridgeplots, cell scatter plots and dotplots. Replace FeaturePlot with the other functions.

RidgePlot(pbmc, features = c("MS4A1", "GNLY", "CD3E", "CD14", "FCER1A", "FCGR3A", "LYZ", "PPBP", "CD8A"))

# For CellScatter plots, will need the cell id of the cells you want to look at. You can get this from the cell metadata (pbmc@meta.data).

head( pbmc@meta.data )
CellScatter(pbmc, cell1 = "AAACATACAACCAC-1", cell2 = "AAACATTGAGCTAC-1")

# DotPlots

DotPlot(pbmc, features = c("MS4A1", "GNLY", "CD3E", "CD14", "FCER1A", "FCGR3A", "LYZ", "PPBP", "CD8A"))

# Which plots do you prefer? Discuss.

# DoHeatmap() generates an expression heatmap for given cells and features. In this case, we are plotting the top 20 markers (or all markers if less than 20) for each cluster.

top10 <- pbmc.markers %>% group_by(cluster) %>% top_n(n = 10, wt = avg_log2FC)
DoHeatmap(pbmc, features = top10$gene) + NoLegend() + theme(axis.text.x =element_text(size = 5),text =element_text(size = 5) ,axis.text.y =element_text(size = 5))


## Use makers to label or find a cluster --------

# If you know markers for your cell types, use [AddModuleScore](https://satijalab.org/seurat/reference/addmodulescore) to label them.


genes_markers <- list(Naive_CD4_T=c("IL7R", "CCR7"))

pbmc<- AddModuleScore( object =pbmc,features = genes_markers,ctrl = 5,name = "Naive_CD4_T", search=TRUE)

#color scale for better visualization
plotCol = rev(brewer.pal(n = 7, name = "RdYlBu"))

#notice the name of the cluster has a 1 at the end
names(pbmc@meta.data)

# label that cell type
pbmc$cell_label=NA
pbmc$cell_label[pbmc$Naive_CD4_T1>1]="Naive_CD4_T"
Idents(pbmc)=pbmc$cell_label

#plot
FeaturePlot(pbmc,
                  features = "Naive_CD4_T1", label=TRUE , repel = TRUE, ) +
  scale_color_gradientn(colors = plotCol)



## Assigning cell type identity to clusters --------

# Fortunately in the case of this dataset, we can use canonical markers to easily match the unbiased clustering to known cell types:

# Cluster ID | Markers       | Cell Type
# -----------|---------------|----------
# 0          | IL7R, CCR7    | Naive CD4+ T
# 1          | CD14, LYZ     | CD14+ Mono
# 2          | IL7R, S100A4  | Memory CD4+
# 3          | MS4A1         | B
# 4          | CD8A          | CD8+ T
# 5          | FCGR3A, MS4A7 | FCGR3A+ Mono
# 6          | GNLY, NKG7    | NK
# 7          | FCER1A, CST3  | DC
# 8          | PPBP          | Platelet

Idents(pbmc)<-pbmc$RNA_snn_res.0.5
new.cluster.ids <- c("Naive CD4 T", "CD14+ Mono", "Memory CD4 T", "B", "CD8 T", "FCGR3A+ Mono", "NK", "DC", "Platelet")
names(new.cluster.ids) <- levels(pbmc)
pbmc <- RenameIdents(pbmc, new.cluster.ids)
DimPlot(pbmc, reduction = 'umap', label = TRUE, pt.size = 0.5) + NoLegend()

saveRDS(pbmc, file = "pbmc3k_final.rds")

write.csv(x = t(as.data.frame(all_times)), file = "pbmc3k_tutorial_times.csv")


## SingleR --------

#install.packages("BiocManager")
#BiocManager::install(c("SingleCellExperiment","SingleR","celldex"),ask=F)
library(SingleCellExperiment)
library(SingleR)
library(celldex)

# In this workshop we have focused on the Seurat package.  However, there is another whole ecosystem of R packages for single cell analysis within Bioconductor.  We won't go into any detail on these packages in this workshop, but there is good material describing the object type online : [OSCA](https://robertamezquita.github.io/orchestratingSingleCellAnalysis/data-infrastructure.html).

# For now, we'll just convert our Seurat object into an object called SingleCellExperiment.  Some popular packages from Bioconductor that work with this type are Slingshot, Scran, Scater.

sce <- as.SingleCellExperiment(pbmc)

# We will now use a package called SingleR to label each cell.  SingleR uses a reference data set of cell types with expression data to infer the best label for each cell.  A convenient collection of cell type reference is in the celldex package which currently contains the follow sets:

ls('package:celldex')

# In this example, we'll use the HumanPrimaryCellAtlasData set, which contains high-level, and fine-grained label types. Lets download the reference dataset

ref.set <- celldex::HumanPrimaryCellAtlasData()
head(unique(ref.set$label.main))

# An example of the types of "fine" labels.

head(unique(ref.set$label.fine))

# Now we'll label our cells using the SingleCellExperiment object, with the above reference set.

pred.cnts <- SingleR::SingleR(test = sce, ref = ref.set, labels = ref.set$label.main)

# Keep any types that have more than 10 cells to the label, and put those labels back on our Seurat object and plot our on our umap.

lbls.keep <- table(pred.cnts$labels)>10
pbmc$SingleR.labels <- ifelse(lbls.keep[pred.cnts$labels], pred.cnts$labels, 'Other')
DimPlot(pbmc, reduction='umap', group.by='SingleR.labels')

# It is nice to see that SingleR does not use the clusters we computed earlier, but the labels do seem to match those clusters reasonably well.


#### Challenge: Reference Based Annotation --------

# See if you can annotate the data with the fine labels from the Monoco reference dataset and whether it improves the cell type annotation resolution. Do you lose any groups?

# Remember you can view the list of references with ls('package:celldex')


# Data set integration with Harmony --------


### Why do we need to do this? --------

# You can have data coming from different samples, batches or experiments and you will need to combine them.

# ###

# When data is collected from multiple samples, multiple runs of the single cell sequencing library preparation, or multiple conditions, cells of the same type may become separated in the UMAP and be put into several different clusters.

# For the purpose of clustering and cell identification, we would like to remove such effects.

# We will now look at [GSE96583](https://www.ncbi.nlm.nih.gov/geo/query/acc.cgi?acc=GSE96583), another PBMC dataset. For speed, we will be looking at a subset of 5000 cells from this data. The cells in this dataset were pooled from eight individual donors. A nice feature is that genetic differences allow some of the cell doublets to be identified. This data contains two batches of single cell sequencing. One of the batches was stimulated with IFN-beta.

# The data has already been processed as we have done with the first PBMC dataset, and can be loaded from kang2018.rds.

kang <- readRDS("kang2018.rds")

head(kang@meta.data)

# * ind identifies a cell as coming from one of 8 individuals.
# * stim identifies a cell as control or stimulated with IFN-beta.
# * cell contains the cell types identified by the creators of this data set.
# * multiplets classifies cells as singlet or doublet.

DimPlot(kang, reduction="umap", group.by="ind")
DimPlot(kang, reduction="umap", group.by="stim")
DimPlot(kang, reduction="pca", group.by="stim")

kang <- FindNeighbors(kang, reduction="pca", dims=1:10)
kang <- FindClusters(kang, resolution=0.25)
kang$pca_clusters <- kang$seurat_clusters

DimPlot(kang, reduction="umap", group.by="pca_clusters")

# There is a big difference between unstimulated and stimulated cells. This has split cells of the same type into pairs of clusters. If the difference was simply uniform, we could regress it out (e.g. using ScaleData(..., vars.to.regress="stim")). However, as can be seen in the PCA plot, the difference is not uniform and we need to do something cleverer.

# We will use [Harmony](https://github.com/immunogenomics/harmony), which can remove non-uniform effects. We will try to remove both the small differences between individuals and the large difference between the unstimulated and stimulated cells.

# Harmony operates only on the PCA scores. The original gene expression levels remain unaltered.

library(harmony)

kang <- RunHarmony(kang, c("stim", "ind"), reduction="pca")

# This has added a new set of reduced dimensions to the Seurat object, kang$harmony which is a modified version of the existing kang$pca reduced dimensions.

DimPlot(kang, reduction="harmony", group.by="stim")

# We can use harmony the same way we used the pca reduction to compute a UMAP layout or to find clusters.

kang <- RunUMAP(kang, reduction="harmony", dims=1:10, reduction.name="umap_harmony")

DimPlot(kang, reduction="umap_harmony", group.by="stim")

kang <- FindNeighbors(kang, reduction="harmony", dims=1:10)
kang <- FindClusters(kang, resolution=0.25)
kang$harmony_clusters <- kang$seurat_clusters

DimPlot(kang, reduction="umap_harmony", group.by="harmony_clusters")
DimPlot(kang, reduction="umap", group.by="harmony_clusters")

# Having found a good set of clusters, we would usually perform differential expression analysis on the original data and include batches/runs/individuals as predictors in the linear model. In this example we could now compare un-stimulated and stimulated cells within each cluster. A particularly nice statistical approach that is possible here would be to convert the counts to pseudo-bulk data for the eight individuals, and then apply a bulk RNA-Seq differential expression analysis method. However there is still the problem that unstimulated and stimulated cells were processed in separate batches.

#   **Session Info**

sessionInfo()
