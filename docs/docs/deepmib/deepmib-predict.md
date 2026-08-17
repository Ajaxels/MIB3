# Deep MIB - Predict Tab

Settings for efficient prediction (inference) and semantic segmentation model generation in Microscopy Image Browser.

---

## How to start the prediction (inference) process

![Predict tab interface](images/DeepLearningPredict.png){.on-glb width="440"}

Prediction (inference) requires a pretrained network. if you lack one, [train it first](deepmib-train.md). pretrained networks can 
be loaded into Deep MIB for segmenting new datasets.

### Steps to start prediction

1. Select the pretrained network file in <span class="widget widget-edit">Network filename...</span> in the *Network* panel. 
This updates the *Train* panel with training settings. Alternatively, load a config file via **Options tab → Config files → Load>**  
2. Verify the prediction images directory in **Directories and Preprocessing tab → Directory with images for prediction**  
3. Confirm the output directory in **Directories and Preprocessing tab → Directory with resulting images**  
4. If needed (usually not), preprocess (convert) files:  
    - Set <span class="widget widget-dropdown">Preprocess for: Prediction</span> in the **Directories and Preprocessing** tab  
    - Click <span class="widget widget-button">Preprocess</span>  
5. Switch to the *Predict* tab and press <span class="widget widget-button">Predict</span>

---

## Settings section

![Settings section](images/DeepLearningPredictSettings.png){.on-glb align=left width="440"}

The *Settings* section configures prediction parameters.

<div class="clear-float"></div>

<span class="widget widget-dropdown">Prediction engine</span>: selects the tiling engine:

* **Legacy** used until MIB 2.83  
* **Blocked-image** recommended for later versions (supports *Dynamic masking* and *2D Patch-wise*)

<label class="widget widget-checkbox">Overlapping tiles</label>: (for *Padding: same*) tiles the patches with overlap to 
minimize edge artefacts and improve segmentation. Define overlap percentage in <span class="widget widget-edit">%%...</span>  
??? abstract "Overlapping vs non-overlapping mode"
      ![Overlapping tiles comparison](images/DeepLearning_OverlappingTiles.jpg){.on-glb}  
      *Same* padding without overlap may show edge artifacts, reduced with overlapping mode.  

<label class="widget widget-checkbox">Dynamic masking</label>: skips prediction on certain tiles using on-the-fly masking, configured via the ![Settings button](images/DeepLearningTrainSettingsBtn.png){.inline-image} button
<br><span class="widget widget-button">Eye</span> previews masking on the current *Image View* panel image
??? abstract "Dynamic masking settings and preview"
      ![Dynamic masking settings](images/DeepLearningPredictDynMasking.png){.on-glb width="370" align=left}  
      <span class="widget widget-dropdown">Masking method</span> keeps blocks above or below the <span class="widget widget-edit">Intensity threshold value...</span>  
      <br><span class="widget widget-edit">Intensity threshold value...</span> sets the intensity threshold for prediction  
      <br><span class="widget widget-edit">inclusion threshold (0-1)...</span> fraction of pixels above/below threshold to keep a tile  
      
      <div class="clear-float"></div>
      
      ![Masking preview](images/DeepLearningPredictSettingsDynMaskPreview.png){.on-glb align=left}  
      Masking preview
      <div class="clear-float"></div>

    ??? abstract "Example of patch-wise segmentation with dynamic masking"

          - Green: predicted nuclei  
          - Red: predicted background  
          - Uncolored: skipped patches  
          ![Patch-wise with masking](images/DeepLearningPredictDynMaskingResults.png){.on-glb}  

<span class="widget widget-edit">Padding, %%</span> pads images symmetrically to reduce edge artifacts  
<span class="widget widget-edit">Downsample factor for images</span> downsamples prediction images to match training 
(if applicable), upsampling results to original size and in case of networks with 2 classes are also smoothed  
<span class="widget widget-edit">Batch size for prediction...</span> sets the number of patches processed by GPU simultaneously, limited by GPU memory  
<span class="widget widget-dropdown">Model files</span> selects output format for models (CSV for patch-wise)  
??? abstract "list of available image formats for the model files"

      - **MIB Model format**: `.model` files, loadable in MIB or MATLAB (`model = load('filename.model', '-mat');`)  
      - **TIF compressed format**: LZW-compressed TIF, pixels encode classes (1, 2, 3, etc.)  
      - **TIF uncompressed format**: uncompressed TIF, pixels encode classes  
<span class="widget widget-dropdown">Score files</span> selects output format for prediction score maps, configured via the ![Settings button](images/DeepLearningTrainSettingsBtn.png){.inline-image} button  
??? abstract "list of available image formats for the score files"

      - **Do not generate** skips score files for better performance  
      - **Use AM format** AmiraMesh, compatible with MIB, Fiji, or Amira  
      - **Use Matlab non-compressed format** `.mibImg`, loadable in MIB or MATLAB (`model = load('filename.mibImg', '-mat');`)  
      - **Use Matlab compressed format** compressed `.mibImg`, loadable in MIB or MATLAB  
      - **Use Matlab non-compressed format (range 0-1)** `.mibImg` with 0-1 range, MATLAB-only (`model = load('filename.mat');`)  
- <label class="widget widget-checkbox">upsample predictions</label>: (*2D patch-wise only*) upsamples downsampled patch-wise predictions to match original image size

### Instance segmentation subpanel

Settings of the *Instance segmentation* subpanel are only available for the
[*2D Instance* workflow](deepmib-instance.md#prediction).

<span class="widget widget-dropdown">Overlap mode</span>: selects how object instances are stitched across tiles during prediction:

* **Centroid in core** — each object is emitted by the tile owning its centroid; the tile overlap must exceed the largest object  
* **IoU merge** — detections of neighbouring tiles are merged when their masks agree in the overlap band; works for objects larger than the overlap  

The ![Settings button](images/DeepLearningTrainSettingsBtn.png){.inline-image} button configures the stitching parameters:

* <span class="widget widget-edit">Detection confidence threshold (0-1)</span> — minimal confidence score for a detected instance to be kept (both overlap modes); decrease to detect more (weaker) objects, increase to keep only confident detections (default: `0.5`)  
* <span class="widget widget-edit">Merge IoU threshold (0-1)</span> — (*IoU merge* only) merge detections of neighbouring tiles when the intersection-over-union of their masks within the shared overlap band exceeds this value; decrease when objects get split at tile seams, increase when distinct touching objects get merged (default: `0.5`)  
* <span class="widget widget-edit">Merge IoA threshold (0-1)</span> — (*IoU merge* only) additionally merge when the intersection over the smaller in-band mask area exceeds this value, catching a truncated fragment fully contained in the neighbouring tile's complete mask (default: `0.8`)  

<span class="widget widget-button">Merge 2D to 3D</span> stitches the predicted instance models in
`3_Results/PredictionImages/ResultsModels` into 3D instance models, linking objects that overlap
between neighbouring slices into 3D instances with a consistent index. The layout is detected
automatically: **2D** models are the Z-slices of one stack (taken in alphabetical order as the
Z-order) and give a single merged model, while **3D** models (predicted from z-stack images) are
each stitched independently into one merged model per file. A dialog asks for the stitching
settings, then for the destination and file format; the result can be saved as a single 3D file or
as a sequence of 2D files. See the
[2D Instance workflow](deepmib-instance.md#merging-2d-predictions-into-a-3d-model) for details.


---

## Explore activations

![Activations explorer](images/DeepLearningPredictActivationsExplorer.png){.on-glb align=left width="380"}

The *Activations explorer* evaluates network performance in detail. It is possible to see details of weights and activation images
for all layers and filters.

<div class="clear-float"></div>

- <span class="widget widget-dropdown">Image</span> lists preprocessed prediction images. select one to load a patch matching the network’s input size. use arrows to navigate  
- <span class="widget widget-dropdown">Layer</span> lists network layers. selecting a layer triggers prediction and activation image generation  
- <span class="widget widget-edit">Z1...</span>, <span class="widget widget-edit">X1...</span>, <span class="widget widget-edit">Y1...</span>
shifts the patch across the image. Update activations with <span class="widget widget-button">Update</span>  
- <span class="widget widget-edit">Patch Z...</span> adjusts Z within 3D network activation patches  
- <span class="widget widget-edit">Filter Id...</span> cycles through activation layers  
- <span class="widget widget-button">Update</span> recalculates activations for the current patch  
- <span class="widget widget-button">Collage</span> creates a collage of current layer activations  
??? abstract "Snapshot with the generated collage of activation images"

      ![Collage of activation images](images/DeepLearningPredictActivationImages.png){.on-glb}


---

## Preview results section

![Preview results section](images/DeepLearningPredictPreviewResults.png){.on-glb width="500"}

<span class="widget widget-button">Load images and models</span> loads original images and segmentations 
into MIB’s active buffer post-prediction  
<br><span class="widget widget-button">Load models</span> loads segmentations over the current MIB image. Requires that the image is already preloaded. 
<br><span class="widget widget-button">Load prediction scores</span> loads score images (probabilities) into the active buffer  
<br><span class="widget widget-button">Evaluate segmentation</span> calculates precision metrics if 
ground truth labels exist in `Labels` under `PredictionImages`. Material names must match training data  
??? abstract "Details of the Evaluate segmentation operation"
      Select metrics to compute:  
      ![Evaluation metrics settings dialog](images/DeepLearning_Evaluation.png){.on-glb}  
      Results show a confusion matrix (0-100 scale), class metrics (Accuracy, IoU, MeanBFScore), and global metrics:  
      ![Evaluation results](images/DeepLearning_Evaluation2.png){.on-glb width="420"}  
      Additional metrics (label occurrence, Sørensen-Dice coefficient) are available via the dropdown:  
      ![Evaluation options](images/DeepLearning_Evaluation3.png){.on-glb width="460"}  
      Export results to MATLAB, Excel, or CSV in `3_Results/PredictionImages/ResultsModels` 
      (see [Directories and Preprocessing](deepmib-dirs.md)). Details of the evaluation procedure are in 
      [MATLAB evaluatesemanticsegmentation](https://se.mathworks.com/help/vision/ref/evaluatesemanticsegmentation.html)

<div class="clear-float"></div>

---

*Back to [MIB](../index.md) | [DeepMIB](index.md)*