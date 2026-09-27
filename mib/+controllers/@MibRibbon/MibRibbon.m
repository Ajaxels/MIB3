classdef MibRibbon
% MIBRIBBON - controller for methods of the ribbon panels in MIB.
%

    properties
        mibController   % controllers.MibController
        view            % MibView (full app view)
        mibModel        % models.MibModel
        gui             % handle to the GUI of the ribbon panel (views.components.Roi)
        handles         % struct of ROI panel handles (panel, listbox, buttons, ...)
        listeners       % cell array of listeners
    end

    methods
        % % declaration of functions in the external files, keep empty line in between for the doc generator
        % 
        dataset_Callbacks(obj, hWidget, hData)        % callback on press of buttons in the Dataset tools section of the Dataset ribbon
        homeDevTest_Callback(obj, hWidget, hData)        % Reserved for MIB developmental purposes
        homeExamples_Callback(obj, BatchOptIn)   % callback on press of the Examples buttons in the Home ribbon
        homeImport_Callback(obj, hWidget, hData)        % callback on press of the import buttons in the Home ribbon
        home_Callbacks(obj, hWidget, hData)        % callback on press of the I/O tools buttons in the Home ribbon
        homeSelectRecentDir_Callback(obj, recentDir)        % callback on selection of the recent directory 
        homeUpdateRecentDirsList(obj)        % update the recent directories list
        image_Callbacks(obj, hWidget, hData)        % callback on press of buttons in the Image ribbon
        imageIntensityProfile(obj, mode)            % draw a line/freehand ROI and display the intensity profile in a figure
        mask_Callbacks(obj, hWidget, hData)        % callback on press of buttons in the Mask to Selection section of the Mask ribbon
        model_Callbacks(obj, hWidget, hData)        % callback on press of the convert model type buttons in the Model ribbon
        selection_Callbacks(obj, hWidget, hData)        % callback on press of buttons in the Selection to Mask section of the Selection ribbon
        selectionBuffer(obj, parameter)                 % Copy/Paste/Clear the selection layer to/from a buffer
        tools_Callbacks(obj, hWidget, hData)        % callback on press of buttons in the Tools ribbon
        result = updateVoxelSizes(obj, pixSize, BatchOptIn)        % Update the physical voxel sizes of the currently shown dataset


        function obj = MibRibbon(mainCtrl, view, ribbonHandles, ribbonWidgets, model)
            % MIBRIBBON - % Init properties.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj = MibRibbon(mainCtrl, view, ribbonHandles, ribbonWidgets, model)
            %
            obj.mibController = mainCtrl;       % handle to the main MIB controller
            obj.view = view;                    % handle to the main MIB view
            obj.gui = ribbonHandles;            % handle to the GUI of the ribbon (obj.view.handles.ribbon.global, obj.view.handles.ribbon.home, obj.view.handles.ribbon.dataset...)
            obj.handles = ribbonWidgets;        % handles of the ribbon widgets (equal to obj.view.handles.ribbonHome; obj.view.handles.ribbonDataset...)
            obj.mibModel = model;               % handle to the main MIB model

            %  Add CALLBACKS  ----------------------
            %% Add Callbacks for the HOME ribbon
            obj.handles.ribbonHome.loadFile.ButtonPushedFcn = @obj.homeImport_Callback;
            obj.homeUpdateRecentDirsList();  % update the list of the recent directories

            obj.handles.ribbonHome.import.ButtonPushedFcn = @obj.homeImport_Callback;
            obj.handles.ribbonHome.importFromMatlab.ItemPushedFcn = @obj.homeImport_Callback;
            obj.handles.ribbonHome.importFromClipboard.ItemPushedFcn = @obj.homeImport_Callback;
            obj.handles.ribbonHome.importFromImaris.ItemPushedFcn = @obj.homeImport_Callback;
            obj.handles.ribbonHome.importFromOmero.ItemPushedFcn = @obj.homeImport_Callback;
            obj.handles.ribbonHome.importFromURL.ItemPushedFcn = @obj.homeImport_Callback;

            %% Add Callbacks for the HOME ribbon -> Examples
            obj.handles.ribbonHome.deepmib2dLargeSpots.ItemPushedFcn = @(h,d) obj.homeExamples_Callback(struct('Dataset', {{'Synthetic 2D Large spots'}}));
            obj.handles.ribbonHome.deepmib2dSmallSpots.ItemPushedFcn = @(h,d) obj.homeExamples_Callback(struct('Dataset', {{'Synthetic 2D small spots'}}));
            obj.handles.ribbonHome.deepmib25dLargeSpots.ItemPushedFcn = @(h,d) obj.homeExamples_Callback(struct('Dataset', {{'Synthetic 2.5D large spots'}}));
            obj.handles.ribbonHome.deepmib2dPatchWise.ItemPushedFcn = @(h,d) obj.homeExamples_Callback(struct('Dataset', {{'Synthetic 2D patch-wise'}}));
            obj.handles.ribbonHome.deepmib2dMembranesEM.ItemPushedFcn = @(h,d) obj.homeExamples_Callback(struct('Dataset', {{'2D EM membranes'}}));
            obj.handles.ribbonHome.deepmib2dNucleiLM.ItemPushedFcn = @(h,d) obj.homeExamples_Callback(struct('Dataset', {{'2D LM nuclei'}}));
            obj.handles.ribbonHome.deepmib3dMitoEM.ItemPushedFcn = @(h,d) obj.homeExamples_Callback(struct('Dataset', {{'3D EM mitochondria'}}));
            obj.handles.ribbonHome.deepmib3dHairCellsLM.ItemPushedFcn = @(h,d) obj.homeExamples_Callback(struct('Dataset', {{'3D LM hair cells'}}));
            obj.handles.ribbonHome.lm3dsimER.ItemPushedFcn = @(h,d) obj.homeExamples_Callback(struct('Dataset', {{'LM 3D SIM ER'}}));
            obj.handles.ribbonHome.lm3dsted.ItemPushedFcn = @(h,d) obj.homeExamples_Callback(struct('Dataset', {{'LM 3D STED'}}));
            obj.handles.ribbonHome.lmWFbleaching.ItemPushedFcn = @(h,d) obj.homeExamples_Callback(struct('Dataset', {{'LM WF ER photobleaching'}}));
            obj.handles.ribbonHome.sbfsemHuh7.ItemPushedFcn = @(h,d) obj.homeExamples_Callback(struct('Dataset', {{'Huh7 and model'}}));
            obj.handles.ribbonHome.sbfsemTrypanosoma.ItemPushedFcn = @(h,d) obj.homeExamples_Callback(struct('Dataset', {{'Trypanosoma and model'}}));
            obj.handles.ribbonHome.mriBrain.ItemPushedFcn = @(h,d) obj.homeExamples_Callback(struct('Dataset', {{'MATLAB Brain and model'}}));

            %% Add Callbacks for the HOME ribbon -> Export section 
            obj.handles.ribbonHome.saveFileAs.ButtonPushedFcn = @obj.home_Callbacks;
            obj.handles.ribbonHome.export.ButtonPushedFcn = @obj.home_Callbacks;
            obj.handles.ribbonHome.exportToMatlab.ItemPushedFcn = @obj.home_Callbacks;
            obj.handles.ribbonHome.exportToImaris.ItemPushedFcn = @obj.home_Callbacks;
            obj.handles.ribbonHome.exportToZarr3.ItemPushedFcn = @obj.home_Callbacks;
            obj.handles.ribbonHome.snapshot.ButtonPushedFcn = @obj.home_Callbacks;
            obj.handles.ribbonHome.movie.ButtonPushedFcn = @obj.home_Callbacks;
            obj.handles.ribbonHome.render.ButtonPushedFcn = @obj.home_Callbacks;
            obj.handles.ribbonHome.renderMIB.ItemPushedFcn = @obj.home_Callbacks;
            obj.handles.ribbonHome.renderMatlab.ItemPushedFcn = @obj.home_Callbacks;
            obj.handles.ribbonHome.renderFiji.ItemPushedFcn = @obj.home_Callbacks;

            %% Add Callbacks for the HOME ribbon -> I/O Tools
            obj.handles.ribbonHome.batch.ButtonPushedFcn = @obj.home_Callbacks;
            obj.handles.ribbonHome.chunk.ItemPushedFcn = @obj.home_Callbacks;
            obj.handles.ribbonHome.stitch.ItemPushedFcn = @obj.home_Callbacks;
            obj.handles.ribbonHome.fuse.ItemPushedFcn = @obj.home_Callbacks;
            obj.handles.ribbonHome.shuffle.ItemPushedFcn = @obj.home_Callbacks;
            obj.handles.ribbonHome.reshuffle.ItemPushedFcn = @obj.home_Callbacks;

            %% Add Callbacks for the HOME ribbon -> Preferences
            obj.handles.ribbonHome.loadLayout.ButtonPushedFcn = @obj.home_Callbacks;
            obj.handles.ribbonHome.loadLayoutLocalDefault.ItemPushedFcn = @obj.home_Callbacks;
            obj.handles.ribbonHome.loadLayoutCustom.ItemPushedFcn = @obj.home_Callbacks;
            obj.handles.ribbonHome.loadLayoutMibDefault.ItemPushedFcn = @obj.home_Callbacks;
            obj.handles.ribbonHome.saveLayout.ButtonPushedFcn = @obj.home_Callbacks;
            obj.handles.ribbonHome.saveLayoutLocalDefault.ItemPushedFcn = @obj.home_Callbacks;
            obj.handles.ribbonHome.saveLayoutCustom.ItemPushedFcn = @obj.home_Callbacks;
            obj.handles.ribbonHome.saveLayoutMibDefault.ItemPushedFcn = @obj.home_Callbacks;
            obj.handles.ribbonHome.systemTheme.ItemPushedFcn = @obj.home_Callbacks;
            obj.handles.ribbonHome.lightTheme.ItemPushedFcn = @obj.home_Callbacks;
            obj.handles.ribbonHome.darkTheme.ItemPushedFcn = @obj.home_Callbacks;
            obj.handles.ribbonHome.preferences.ButtonPushedFcn = @obj.home_Callbacks;
            obj.handles.ribbonHome.preferencesMenu.ItemPushedFcn = @obj.home_Callbacks;
            obj.handles.ribbonHome.prefOverrideMenu.ItemPushedFcn = @obj.home_Callbacks;
            obj.handles.ribbonHome.help.ButtonPushedFcn = @obj.home_Callbacks;
            obj.handles.ribbonHome.helpMenu.ItemPushedFcn = @obj.home_Callbacks;
            obj.handles.ribbonHome.tipOfDay.ItemPushedFcn = @obj.home_Callbacks;
            obj.handles.ribbonHome.support.ItemPushedFcn = @obj.home_Callbacks;
            obj.handles.ribbonHome.call4help.ItemPushedFcn = @obj.home_Callbacks;
            obj.handles.ribbonHome.classReference.ItemPushedFcn = @obj.home_Callbacks;
            obj.handles.ribbonHome.checkUpdate.ItemPushedFcn = @obj.home_Callbacks;
            obj.handles.ribbonHome.personalStats.ItemPushedFcn = @obj.home_Callbacks;
            obj.handles.ribbonHome.licenses.ItemPushedFcn = @obj.home_Callbacks;
            obj.handles.ribbonHome.about.ItemPushedFcn = @obj.home_Callbacks;
            obj.handles.ribbonHome.devModeSplitBtn.ButtonPushedFcn = @obj.homeDevTest_Callback;
            obj.handles.ribbonHome.devModeEnabled.ValueChangedFcn = @obj.home_Callbacks;
            obj.handles.ribbonHome.devMode.ItemPushedFcn = @obj.homeDevTest_Callback;           
            %obj.handles.ribbonHome.devMode.ButtonPushedFcn = @obj.homeDevTest_Callback;

            % --------- update listeners
            % update list of recent directories
            obj.listeners{1} = addlistener(obj.mibModel, 'UpdateRecentDirsList', @(src, evnt)obj.homeUpdateRecentDirsList()); 

            % update checkboxes
            obj.handles.ribbonHome.devModeEnabled.Value = model.preferences.System.DeveloperMode;

        end

        function addCallbacksToDatasetRibbon(obj)
            % ADDCALLBACKSTODATASETRIBBON - add callbacks to the Dataset ribbon to allow lazy loading.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.addCallbacksToDatasetRibbon()
            %

            %% Add Callbacks for the DATASET ribbon -> Alignment
            obj.handles.ribbonDataset.alignment.ButtonPushedFcn = @obj.dataset_Callbacks;
            %% Add Callbacks for the DATASET ribbon -> Stitching
            obj.handles.ribbonDataset.stitch.ButtonPushedFcn = @obj.dataset_Callbacks;
            %% Add Callbacks for the DATASET ribbon -> Dataset tools
            obj.handles.ribbonDataset.crop.ButtonPushedFcn = @obj.dataset_Callbacks;
            obj.handles.ribbonDataset.resize.ButtonPushedFcn = @obj.dataset_Callbacks;
            %% Add Callbacks for the DATASET ribbon -> Dataset tools -> Transform
            obj.handles.ribbonDataset.addframeWidth.ItemPushedFcn = @obj.dataset_Callbacks;
            obj.handles.ribbonDataset.addframedX.ItemPushedFcn = @obj.dataset_Callbacks;
            obj.handles.ribbonDataset.flipH.ItemPushedFcn = @obj.dataset_Callbacks;
            obj.handles.ribbonDataset.flipV.ItemPushedFcn = @obj.dataset_Callbacks;
            obj.handles.ribbonDataset.flipZ.ItemPushedFcn = @obj.dataset_Callbacks;
            obj.handles.ribbonDataset.flipT.ItemPushedFcn = @obj.dataset_Callbacks;
            obj.handles.ribbonDataset.rotPos90.ItemPushedFcn = @obj.dataset_Callbacks;
            obj.handles.ribbonDataset.rotNeg90.ItemPushedFcn = @obj.dataset_Callbacks;
            obj.handles.ribbonDataset.transposeYX2YZ.ItemPushedFcn = @obj.dataset_Callbacks;
            obj.handles.ribbonDataset.transposeYX2XZ.ItemPushedFcn = @obj.dataset_Callbacks;
            obj.handles.ribbonDataset.transposeYX2XY.ItemPushedFcn = @obj.dataset_Callbacks;
            obj.handles.ribbonDataset.transposeZ2T.ItemPushedFcn = @obj.dataset_Callbacks;
            obj.handles.ribbonDataset.transposeZ2C.ItemPushedFcn = @obj.dataset_Callbacks;
            %% Add Callbacks for the DATASET ribbon -> Dataset tools -> Slices
            obj.handles.ribbonDataset.sliceCopy.ItemPushedFcn = @obj.dataset_Callbacks;
            obj.handles.ribbonDataset.sliceInsert.ItemPushedFcn = @obj.dataset_Callbacks;
            obj.handles.ribbonDataset.sliceInterval.ItemPushedFcn = @obj.dataset_Callbacks;
            obj.handles.ribbonDataset.sliceSwap.ItemPushedFcn = @obj.dataset_Callbacks;
            obj.handles.ribbonDataset.sliceDelete.ItemPushedFcn = @obj.dataset_Callbacks;
            obj.handles.ribbonDataset.sliceFrameDelete.ItemPushedFcn = @obj.dataset_Callbacks;
            %% Add Callbacks for the DATASET ribbon -> Calibration section
            obj.handles.ribbonDataset.scalebar.ButtonPushedFcn = @obj.dataset_Callbacks;
            obj.handles.ribbonDataset.boundingbox.ButtonPushedFcn = @obj.dataset_Callbacks;
            obj.handles.ribbonDataset.voxels.ButtonPushedFcn = @obj.dataset_Callbacks;
            %% Add Callbacks for the DATASET ribbon -> Metadata section
            obj.handles.ribbonDataset.log.ButtonPushedFcn = @obj.dataset_Callbacks;
            obj.handles.ribbonDataset.info.ButtonPushedFcn = @obj.dataset_Callbacks;

        end

        function addCallbacksToDatasetImage(obj)
            % ADDCALLBACKSTODATASETIMAGE - add callbacks to the Image ribbon to allow lazy loading.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.addCallbacksToDatasetImage()
            %
        
            %% Add Callbacks for the IMAGE ribbon -> Mode
            obj.handles.ribbonImage.grayscale.ValueChangedFcn = @obj.image_Callbacks;
            obj.handles.ribbonImage.multichannel.ValueChangedFcn = @obj.image_Callbacks;
            obj.handles.ribbonImage.hsv.ValueChangedFcn = @obj.image_Callbacks;
            obj.handles.ribbonImage.indexed.ValueChangedFcn = @obj.image_Callbacks;
            obj.handles.ribbonImage.bit8.ValueChangedFcn = @obj.image_Callbacks;
            obj.handles.ribbonImage.bit16.ValueChangedFcn = @obj.image_Callbacks;
            obj.handles.ribbonImage.bit32.ValueChangedFcn = @obj.image_Callbacks;

            %% Add Callbacks for the IMAGE ribbon -> Image Adjustments
            obj.handles.ribbonImage.display.ButtonPushedFcn = @obj.image_Callbacks;
            % colors
            obj.handles.ribbonImage.colorsInsert.ItemPushedFcn = @obj.image_Callbacks;
            obj.handles.ribbonImage.colorsCopy.ItemPushedFcn = @obj.image_Callbacks;
            obj.handles.ribbonImage.colorsInvert.ItemPushedFcn = @obj.image_Callbacks;
            obj.handles.ribbonImage.colorsRotate.ItemPushedFcn = @obj.image_Callbacks;
            obj.handles.ribbonImage.colorsShift.ItemPushedFcn = @obj.image_Callbacks;
            obj.handles.ribbonImage.colorsSwap.ItemPushedFcn = @obj.image_Callbacks;
            obj.handles.ribbonImage.colorsDelete.ItemPushedFcn = @obj.image_Callbacks;
            % contrast
            obj.handles.ribbonImage.contrastCLAHE.ItemPushedFcn = @obj.image_Callbacks;
            obj.handles.ribbonImage.contrastNorm.ItemPushedFcn = @obj.image_Callbacks;
            % invert
            obj.handles.ribbonImage.invert.ButtonPushedFcn = @obj.image_Callbacks;
            obj.handles.ribbonImage.invert2D.ItemPushedFcn = @obj.image_Callbacks;
            obj.handles.ribbonImage.invert3D.ItemPushedFcn = @obj.image_Callbacks;
            obj.handles.ribbonImage.invert4D.ItemPushedFcn = @obj.image_Callbacks;
            % visualization
            obj.handles.ribbonImage.visualization.ButtonPushedFcn = @obj.image_Callbacks;
            obj.handles.ribbonImage.visBicubic.ItemPushedFcn = @obj.image_Callbacks;
            obj.handles.ribbonImage.visNearest.ItemPushedFcn = @obj.image_Callbacks;
            obj.handles.ribbonImage.visAuto.ItemPushedFcn = @obj.image_Callbacks;

            %% Add Callbacks for the IMAGE ribbon -> Image Tools
            obj.handles.ribbonImage.filters.ButtonPushedFcn = @obj.image_Callbacks;
            % image tools
            obj.handles.ribbonImage.contentAware.ItemPushedFcn = @obj.image_Callbacks;
            obj.handles.ribbonImage.debrisRemoval.ItemPushedFcn = @obj.image_Callbacks;
            obj.handles.ribbonImage.imageMath.ItemPushedFcn = @obj.image_Callbacks;
            obj.handles.ribbonImage.intProjection.ItemPushedFcn = @obj.image_Callbacks;
            obj.handles.ribbonImage.imgFrame.ItemPushedFcn = @obj.image_Callbacks;
            obj.handles.ribbonImage.whiteBalance.ItemPushedFcn = @obj.image_Callbacks;
            % morph ops
            obj.handles.ribbonImage.botHat.ItemPushedFcn = @obj.image_Callbacks;
            obj.handles.ribbonImage.clearBorder.ItemPushedFcn = @obj.image_Callbacks;
            obj.handles.ribbonImage.morphClose.ItemPushedFcn = @obj.image_Callbacks;
            obj.handles.ribbonImage.dilate.ItemPushedFcn = @obj.image_Callbacks;
            obj.handles.ribbonImage.erode.ItemPushedFcn = @obj.image_Callbacks;
            obj.handles.ribbonImage.fill.ItemPushedFcn = @obj.image_Callbacks;
            obj.handles.ribbonImage.hMax.ItemPushedFcn = @obj.image_Callbacks;
            obj.handles.ribbonImage.hMin.ItemPushedFcn = @obj.image_Callbacks;
            obj.handles.ribbonImage.morphOpen.ItemPushedFcn = @obj.image_Callbacks;
            obj.handles.ribbonImage.topHat.ItemPushedFcn = @obj.image_Callbacks;
            % intensity profile
            obj.handles.ribbonImage.profileLine.ItemPushedFcn = @obj.image_Callbacks;
            obj.handles.ribbonImage.profileArbitrary.ItemPushedFcn = @obj.image_Callbacks;
        end

        function addCallbacksToDatasetModel(obj)
            % ADDCALLBACKSTODATASETMODEL - add callbacks to the Model ribbon to allow lazy loading.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.addCallbacksToDatasetModel()
            %

            %% Add Callbacks for the MODEL ribbon -> Convert type
            obj.handles.ribbonModel.mat63.ValueChangedFcn = @obj.model_Callbacks;
            obj.handles.ribbonModel.mat255.ValueChangedFcn = @obj.model_Callbacks;
            obj.handles.ribbonModel.mat65535.ValueChangedFcn = @obj.model_Callbacks;
            obj.handles.ribbonModel.mat4294967295.ValueChangedFcn = @obj.model_Callbacks;
            obj.handles.ribbonModel.indexed2dconn4.ItemPushedFcn = @obj.model_Callbacks;
            obj.handles.ribbonModel.indexed2dconn8.ItemPushedFcn = @obj.model_Callbacks;
            obj.handles.ribbonModel.indexed3dconn4.ItemPushedFcn = @obj.model_Callbacks;
            obj.handles.ribbonModel.indexed3dconn8.ItemPushedFcn = @obj.model_Callbacks;
            obj.handles.ribbonModel.stitchInstances2Dto3D.ItemPushedFcn = @obj.model_Callbacks;
            %% Add Callbacks for the MODEL ribbon -> Import section
            obj.handles.ribbonModel.new.ButtonPushedFcn = @obj.model_Callbacks;
            obj.handles.ribbonModel.load.ButtonPushedFcn = @obj.model_Callbacks;
            obj.handles.ribbonModel.import.ButtonPushedFcn = @obj.model_Callbacks;
            obj.handles.ribbonModel.importFromMatlab.ItemPushedFcn = @obj.model_Callbacks;
            obj.handles.ribbonModel.importFromMIB.ItemPushedFcn = @obj.model_Callbacks;
            obj.handles.ribbonModel.importFromZarr.ItemPushedFcn = @obj.model_Callbacks;
            %% Add Callbacks for the MODEL ribbon -> Export section
            obj.handles.ribbonModel.export.ButtonPushedFcn = @obj.model_Callbacks;
            obj.handles.ribbonModel.exportToMatlab.ItemPushedFcn = @obj.model_Callbacks;
            obj.handles.ribbonModel.exportToMIB.ItemPushedFcn = @obj.model_Callbacks;
            obj.handles.ribbonModel.exportToImaris.ItemPushedFcn = @obj.model_Callbacks;
            obj.handles.ribbonModel.exportToZarr3.ItemPushedFcn = @obj.model_Callbacks;
            obj.handles.ribbonModel.save.ButtonPushedFcn = @obj.model_Callbacks;
            obj.handles.ribbonModel.saveAs.ButtonPushedFcn = @obj.model_Callbacks;
            %% Add Callbacks for the MODEL ribbon -> Model tools section
            % Materials
            obj.handles.ribbonModel.matRename.ItemPushedFcn = @obj.model_Callbacks;
            obj.handles.ribbonModel.matAdd.ItemPushedFcn = @obj.model_Callbacks;
            obj.handles.ribbonModel.matInsert.ItemPushedFcn = @obj.model_Callbacks;
            obj.handles.ribbonModel.matSwap.ItemPushedFcn = @obj.model_Callbacks;
            obj.handles.ribbonModel.matReorder.ItemPushedFcn = @obj.model_Callbacks;
            obj.handles.ribbonModel.matImport.ItemPushedFcn = @obj.model_Callbacks;
            obj.handles.ribbonModel.matExport.ItemPushedFcn = @obj.model_Callbacks;
            obj.handles.ribbonModel.matSave.ItemPushedFcn = @obj.model_Callbacks;
            obj.handles.ribbonModel.matRemove.ItemPushedFcn = @obj.model_Callbacks;
            % List of annotations
            obj.handles.ribbonModel.annotations.ButtonPushedFcn = @obj.model_Callbacks;
            obj.handles.ribbonModel.annotationsList.ItemPushedFcn = @obj.model_Callbacks;
            obj.handles.ribbonModel.annotationsImaris.ItemPushedFcn = @obj.model_Callbacks;
            obj.handles.ribbonModel.annotationsRemove.ItemPushedFcn = @obj.model_Callbacks;
            % Render
            obj.handles.ribbonModel.render.ButtonPushedFcn = @obj.model_Callbacks;
            obj.handles.ribbonModel.renderMIB.ItemPushedFcn = @obj.model_Callbacks;
            obj.handles.ribbonModel.renderMatlab.ItemPushedFcn = @obj.model_Callbacks;
            obj.handles.ribbonModel.renderMatlabImaris.ItemPushedFcn = @obj.model_Callbacks;
            obj.handles.ribbonModel.renderMatlabVolView.ItemPushedFcn = @obj.model_Callbacks;
            obj.handles.ribbonModel.renderFiji.ItemPushedFcn = @obj.model_Callbacks;
            obj.handles.ribbonModel.renderImaris.ItemPushedFcn = @obj.model_Callbacks;
            % Instance editor
            obj.handles.ribbonModel.instanceEditor.ButtonPushedFcn = @obj.model_Callbacks;
            % Quantification
            obj.handles.ribbonModel.quantification.ButtonPushedFcn = @obj.model_Callbacks;            
        end

        function addCallbacksToDatasetMask(obj)
            % ADDCALLBACKSTODATASETMASK - add callbacks to the Mask ribbon to allow lazy loading.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.addCallbacksToDatasetMask()
            %

            %% Add Callbacks for the MASK ribbon -> Mask to Selection
            obj.handles.ribbonMask.maskToSelection2DAdd.ItemPushedFcn = @obj.mask_Callbacks;
            obj.handles.ribbonMask.maskToSelection2DRemove.ItemPushedFcn = @obj.mask_Callbacks;
            obj.handles.ribbonMask.maskToSelection2DReplace.ItemPushedFcn = @obj.mask_Callbacks;
            obj.handles.ribbonMask.maskToSelection3DAdd.ItemPushedFcn = @obj.mask_Callbacks;
            obj.handles.ribbonMask.maskToSelection3DRemove.ItemPushedFcn = @obj.mask_Callbacks;
            obj.handles.ribbonMask.maskToSelection3DReplace.ItemPushedFcn = @obj.mask_Callbacks;
            obj.handles.ribbonMask.maskToSelection4DAdd.ItemPushedFcn = @obj.mask_Callbacks;
            obj.handles.ribbonMask.maskToSelection4DRemove.ItemPushedFcn = @obj.mask_Callbacks;
            obj.handles.ribbonMask.maskToSelection4DReplace.ItemPushedFcn = @obj.mask_Callbacks;
            %% Add Callbacks for the MASK ribbon -> Import section
            obj.handles.ribbonMask.clear.ButtonPushedFcn = @obj.mask_Callbacks;
            obj.handles.ribbonMask.load.ButtonPushedFcn = @obj.mask_Callbacks;
            obj.handles.ribbonMask.import.ButtonPushedFcn = @obj.mask_Callbacks;
            obj.handles.ribbonMask.importFromMatlab.ItemPushedFcn = @obj.mask_Callbacks;
            obj.handles.ribbonMask.importFromMIB.ItemPushedFcn = @obj.mask_Callbacks;
            %% Add Callbacks for the MASK ribbon -> Export section
            obj.handles.ribbonMask.export.ButtonPushedFcn = @obj.mask_Callbacks;
            obj.handles.ribbonMask.exportToMatlab.ItemPushedFcn = @obj.mask_Callbacks;
            obj.handles.ribbonMask.exportToMIB.ItemPushedFcn = @obj.mask_Callbacks;
            obj.handles.ribbonMask.saveMask.ButtonPushedFcn = @obj.mask_Callbacks;
            %% Add Callbacks for the MASK ribbon -> Tools and Quantification section
            obj.handles.ribbonMask.invert.ButtonPushedFcn = @obj.mask_Callbacks;
            obj.handles.ribbonMask.invert2D.ItemPushedFcn = @obj.mask_Callbacks;
            obj.handles.ribbonMask.invert3D.ItemPushedFcn = @obj.mask_Callbacks;
            obj.handles.ribbonMask.invert4D.ItemPushedFcn = @obj.mask_Callbacks;
            obj.handles.ribbonMask.replaceImage.ButtonPushedFcn = @obj.mask_Callbacks;
            obj.handles.ribbonMask.smooth.ButtonPushedFcn = @obj.mask_Callbacks;
            obj.handles.ribbonMask.quantify.ButtonPushedFcn = @obj.mask_Callbacks;
    
        end

        function addCallbacksToDatasetSelection(obj)
            % ADDCALLBACKSTODATASETSELECTION - add callbacks to the Selection ribbon to allow lazy loading.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.addCallbacksToDatasetSelection()
            %

            %% Add Callbacks for the SELECTION ribbon -> Converts section
            % Selection to mask
            obj.handles.ribbonSelection.selectionToMask2DAdd.ItemPushedFcn = @obj.selection_Callbacks;
            obj.handles.ribbonSelection.selectionToMask2DRemove.ItemPushedFcn = @obj.selection_Callbacks;
            obj.handles.ribbonSelection.selectionToMask2DReplace.ItemPushedFcn = @obj.selection_Callbacks;
            obj.handles.ribbonSelection.selectionToMask3DAdd.ItemPushedFcn = @obj.selection_Callbacks;
            obj.handles.ribbonSelection.selectionToMask3DRemove.ItemPushedFcn = @obj.selection_Callbacks;
            obj.handles.ribbonSelection.selectionToMask3DReplace.ItemPushedFcn = @obj.selection_Callbacks;
            obj.handles.ribbonSelection.selectionToMask4DAdd.ItemPushedFcn = @obj.selection_Callbacks;
            obj.handles.ribbonSelection.selectionToMask4DRemove.ItemPushedFcn = @obj.selection_Callbacks;
            obj.handles.ribbonSelection.selectionToMask4DReplace.ItemPushedFcn = @obj.selection_Callbacks;
            % Selection to buffer
            obj.handles.ribbonSelection.copy.ItemPushedFcn = @obj.selection_Callbacks;
            obj.handles.ribbonSelection.paste.ItemPushedFcn = @obj.selection_Callbacks;
            obj.handles.ribbonSelection.pasteAll.ItemPushedFcn = @obj.selection_Callbacks;
            obj.handles.ribbonSelection.clear.ItemPushedFcn = @obj.selection_Callbacks;
            %% Add Callbacks for the SELECTION ribbon -> Tools section
            % MorphOps
            obj.handles.ribbonSelection.branch.ItemPushedFcn = @obj.selection_Callbacks;
            obj.handles.ribbonSelection.diag.ItemPushedFcn = @obj.selection_Callbacks;
            obj.handles.ribbonSelection.endpoints.ItemPushedFcn = @obj.selection_Callbacks;
            obj.handles.ribbonSelection.skeleton.ItemPushedFcn = @obj.selection_Callbacks;
            obj.handles.ribbonSelection.spur.ItemPushedFcn = @obj.selection_Callbacks;
            obj.handles.ribbonSelection.thin.ItemPushedFcn = @obj.selection_Callbacks;
            obj.handles.ribbonSelection.ultErosion.ItemPushedFcn = @obj.selection_Callbacks;
            % invert
            obj.handles.ribbonSelection.invert.ButtonPushedFcn = @obj.selection_Callbacks;
            obj.handles.ribbonSelection.invert2D.ItemPushedFcn = @obj.selection_Callbacks;
            obj.handles.ribbonSelection.invert3D.ItemPushedFcn = @obj.selection_Callbacks;
            obj.handles.ribbonSelection.invert4D.ItemPushedFcn = @obj.selection_Callbacks;
            % other tools
            obj.handles.ribbonSelection.expandToMask.ButtonPushedFcn = @obj.selection_Callbacks;
            obj.handles.ribbonSelection.interpolate.ButtonPushedFcn = @obj.selection_Callbacks;
            obj.handles.ribbonSelection.interpolateAsShape.ItemPushedFcn = @obj.selection_Callbacks;
            obj.handles.ribbonSelection.interpolateAsLine.ItemPushedFcn = @obj.selection_Callbacks;
            obj.handles.ribbonSelection.interpolationSettings.ItemPushedFcn = @obj.selection_Callbacks;
            obj.handles.ribbonSelection.replaceImage.ButtonPushedFcn = @obj.selection_Callbacks;
            obj.handles.ribbonSelection.smooth.ButtonPushedFcn = @obj.selection_Callbacks;
        end

        function addCallbacksToDatasetTools(obj)
            % ADDCALLBACKSTODATASETTOOLS - add callbacks to the Tools ribbon to allow lazy loading.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.addCallbacksToDatasetTools()
            %

            %% Add Callbacks for the SELECTION ribbon -> Segmentation section
            % DeepMIB
            obj.handles.ribbonTools.deepmib.ButtonPushedFcn = @obj.tools_Callbacks;
            % Classifiers
            obj.handles.ribbonTools.membrane.ItemPushedFcn = @obj.tools_Callbacks;
            obj.handles.ribbonTools.supervoxels.ItemPushedFcn = @obj.tools_Callbacks;
            % Semi-automatic
            obj.handles.ribbonTools.globalthres.ItemPushedFcn = @obj.tools_Callbacks;
            obj.handles.ribbonTools.graphcut.ItemPushedFcn = @obj.tools_Callbacks;
            obj.handles.ribbonTools.watershed.ItemPushedFcn = @obj.tools_Callbacks;
            %% Add Callbacks for the SELECTION ribbon -> Misc section
            % Measure length
            obj.handles.ribbonTools.measure.ButtonPushedFcn = @obj.tools_Callbacks;
            obj.handles.ribbonTools.measureTool.ItemPushedFcn = @obj.tools_Callbacks;
            obj.handles.ribbonTools.measureLine.ItemPushedFcn = @obj.tools_Callbacks;
            obj.handles.ribbonTools.measureFreehand.ItemPushedFcn = @obj.tools_Callbacks;
            % Object separator
            obj.handles.ribbonTools.objects.ButtonPushedFcn = @obj.tools_Callbacks;
            % Stereology
            obj.handles.ribbonTools.stereology.ButtonPushedFcn = @obj.tools_Callbacks;
            % Wound healing assay
            obj.handles.ribbonTools.wound.ButtonPushedFcn = @obj.tools_Callbacks;


        end

    end
end


