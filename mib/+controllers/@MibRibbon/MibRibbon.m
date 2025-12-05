classdef MibRibbon
    % classdef MibRibbon
    % controller for methods of the ribbon panels in MIB

    properties
        mibController   % controllers.MibController
        view            % MibView (full app view)
        mibModel        % models.MibModel
        gui             % handle to the GUI of the ribbon panel (views.components.Roi)
        handles         % struct of ROI panel handles (panel, listbox, buttons, ...)
        listeners       % cell array of listeners
    end

    methods
        % declaration of functions in the external files, keep empty line in between for the doc generator
    
        datasetAlignment_Callback(obj, hWidget, hData)        % callback on press of buttons in the Alignment section of the Dataset ribbon

        datasetCalibration_Callback(obj, hWidget, hData)        % callback on press of buttons in the Calibration section of the Dataset ribbon

        datasetMetadata_Callback(obj, hWidget, hData)        % callback on press of buttons in the Metadata section of the Dataset ribbon
        
        datasetToolsSlices_Callback(obj, hWidget, hData)        % callback on press of buttons in the Slices button of the Dataset ribbon
        
        datasetTools_Callback(obj, hWidget, hData)        % callback on press of buttons in the Dataset tools section of the Dataset ribbon

        datasetToolsTransform_Callback(obj, hWidget, hData)        % callback on press of buttons in the Transform button of the Dataset ribbon
        
        homeExamples_Callback(obj, hWidget, hData)   % callback on press of the Examples buttons in the Home ribbon

        homeExport_Callback(obj, hWidget, hData)        % callback on press of buttons in the Export section of the Home ribbon

        homeLoad_Callback(obj, hWidget, hData)        % callback on press of the load button in the Home ribbon

        homeImport_Callback(obj, hWidget, hData)        % callback on press of the import buttons in the Home ribbon

        homeIOtools_Callback(obj, hWidget, hData)        % callback on press of the I/O tools buttons in the Home ribbon

        homePreferences_Callback(obj, hWidget, hData)        % callback on press of the preferences section buttons in the Home ribbon

        image_Callbacks(obj, hWidget, hData)        % callback on press of buttons in the Image ribbon

        imageColors_Callbacks(obj, hWidget, hData)        % callback on press of the color channel buttons in the Image ribbon

        imageContrast_Callbacks(obj, hWidget, hData)        % callback on press of the contrast buttons in the Image ribbon

        imageInvert_Callbacks(obj, hWidget, hData)        % callback on press of the Invert buttons in the Image ribbon
        
        imageMode_Callback(obj, hWidget, hData)        % callback on press of buttons in the Mode section of the Image ribbon

        imageMorphOps_Callbacks(obj, hWidget, hData)        % callback on press of morph-ops buttons in the Image ribbon

        imageTools_Callbacks(obj, hWidget, hData)        % callback on press of Image tools buttons in the Image ribbon

        maskExportSection_Callbacks(obj, hWidget, hData)        % callback on press of buttons in the Export section of the Mask ribbon
        
        maskImportSection_Callbacks(obj, hWidget, hData)        % callback on press of buttons in the Import section of the Mask ribbon
        
        maskToolsQuantifySection_Callbacks(obj, hWidget, hData)        % callback on press of buttons in the Tools and Quantification sections of the Mask ribbon
        
        maskToSelection_Callback(obj, hWidget, hData)        % callback on press of buttons in the Mask to Selection section of the Mask ribbon

        modelAnnotations_Callback(obj, hWidget, hData)        % callback on press of buttons in the List of annotations button of the Model ribbon
        
        modelConvertType_Callback(obj, hWidget, hData)        % callback on press of the convert model type buttons in the Model ribbon

        modelExport_Callback(obj, hWidget, hData)        % callback on press of buttons in the Export section of the Model ribbon

        modelImport_Callback(obj, hWidget, hData)        % callback on press of buttons in the Import section of the Model ribbon

        modelMaterials_Callback(obj, hWidget, hData)        % callback on press of buttons in the Materials button of the Model ribbon

        modelQuantification_Callback(obj, hWidget, hData)        % callback on press of the Quantification button in the Model ribbon
        
        modelRender_Callback(obj, hWidget, hData)        % callback on press of buttons in the Render button of the Model ribbon

        selectionConverts_Callbacks(obj, hWidget, hData)        % callback on press of buttons in the Selection to Mask section of the Selection ribbon

        selectionTools_Callbacks(obj, hWidget, hData)        % callback on press of buttons in the Tools section of the Selection ribbon

        toolsMisc_Callbacks(obj, hWidget, hData)        % callback on press of buttons in the Misc section of the Tools ribbon
        
        toolsSegmentation_Callbacks(obj, hWidget, hData)        % callback on press of buttons in the Segmentation section of the Tools ribbon

        function obj = MibRibbon(mainCtrl, view, ribbonHandles, ribbonWidgets, model)
            %% Init properties
            obj.mibController = mainCtrl;       % handle to the main MIB controller
            obj.view = view;                    % handle to the main MIB view
            obj.gui = ribbonHandles;            % handle to the GUI of the ribbon (obj.view.handles.ribbon.global, obj.view.handles.ribbon.home, obj.view.handles.ribbon.dataset...)
            obj.handles = ribbonWidgets;        % handles of the ribbon widgets (equal to obj.view.handles.ribbonHome; obj.view.handles.ribbonDataset...)
            obj.mibModel = model;               % handle to the main MIB model

            %  Add CALLBACKS  ----------------------
            %% Add Callbacks for the HOME ribbon
            obj.handles.ribbonHome.loadFile.ButtonPushedFcn = @obj.homeLoad_Callback;
            obj.handles.ribbonHome.import.ButtonPushedFcn = @obj.homeImport_Callback;
            obj.handles.ribbonHome.importFromMatlab.ItemPushedFcn = @obj.homeImport_Callback;
            obj.handles.ribbonHome.importFromClipboard.ItemPushedFcn = @obj.homeImport_Callback;
            obj.handles.ribbonHome.importFromImaris.ItemPushedFcn = @obj.homeImport_Callback;
            obj.handles.ribbonHome.importFromOmero.ItemPushedFcn = @obj.homeImport_Callback;
            obj.handles.ribbonHome.importFromURL.ItemPushedFcn = @obj.homeImport_Callback;
            %% Add Callbacks for the HOME ribbon -> Examples
            obj.handles.ribbonHome.deepmib2dLargeSpots.ItemPushedFcn = @obj.homeExamples_Callback;
            obj.handles.ribbonHome.deepmib2dSmallSpots.ItemPushedFcn = @obj.homeExamples_Callback;
            obj.handles.ribbonHome.deepmib25dLargeSpots.ItemPushedFcn = @obj.homeExamples_Callback;
            obj.handles.ribbonHome.deepmib2dPatchWise.ItemPushedFcn = @obj.homeExamples_Callback;
            obj.handles.ribbonHome.deepmib2dMembranesEM.ItemPushedFcn = @obj.homeExamples_Callback;
            obj.handles.ribbonHome.deepmib2dNucleiLM.ItemPushedFcn = @obj.homeExamples_Callback;
            obj.handles.ribbonHome.deepmib3dMitoEM.ItemPushedFcn = @obj.homeExamples_Callback;
            obj.handles.ribbonHome.deepmib3dHairCellsLM.ItemPushedFcn = @obj.homeExamples_Callback;
            obj.handles.ribbonHome.lm3dsimER.ItemPushedFcn = @obj.homeExamples_Callback;
            obj.handles.ribbonHome.lm3dsted.ItemPushedFcn = @obj.homeExamples_Callback;
            obj.handles.ribbonHome.lmWFbleaching.ItemPushedFcn = @obj.homeExamples_Callback;
            obj.handles.ribbonHome.sbfsemHuh7.ItemPushedFcn = @obj.homeExamples_Callback;
            obj.handles.ribbonHome.sbfsemTrypanosoma.ItemPushedFcn = @obj.homeExamples_Callback;
            obj.handles.ribbonHome.mriBrain.ItemPushedFcn = @obj.homeExamples_Callback;
            %% Add Callbacks for the HOME ribbon -> Export section 
            obj.handles.ribbonHome.saveFileAs.ButtonPushedFcn = @obj.homeExport_Callback;
            obj.handles.ribbonHome.saveFile.ItemPushedFcn = @obj.homeExport_Callback;
            obj.handles.ribbonHome.saveFileAs2.ItemPushedFcn = @obj.homeExport_Callback;
            obj.handles.ribbonHome.export.ButtonPushedFcn = @obj.homeExport_Callback;
            obj.handles.ribbonHome.exportToMatlab.ItemPushedFcn = @obj.homeExport_Callback;
            obj.handles.ribbonHome.exportToImaris.ItemPushedFcn = @obj.homeExport_Callback;
            obj.handles.ribbonHome.snapshot.ButtonPushedFcn = @obj.homeExport_Callback;
            obj.handles.ribbonHome.movie.ButtonPushedFcn = @obj.homeExport_Callback;
            obj.handles.ribbonHome.render.ButtonPushedFcn = @obj.homeExport_Callback;
            obj.handles.ribbonHome.renderMIB.ItemPushedFcn = @obj.homeExport_Callback;
            obj.handles.ribbonHome.renderMatlab.ItemPushedFcn = @obj.homeExport_Callback;
            obj.handles.ribbonHome.renderFiji.ItemPushedFcn = @obj.homeExport_Callback;
            %% Add Callbacks for the HOME ribbon -> I/O Tools
            obj.handles.ribbonHome.batch.ButtonPushedFcn = @obj.homeIOtools_Callback;
            obj.handles.ribbonHome.chunk.ItemPushedFcn = @obj.homeIOtools_Callback;
            obj.handles.ribbonHome.stitch.ItemPushedFcn = @obj.homeIOtools_Callback;
            obj.handles.ribbonHome.shuffle.ItemPushedFcn = @obj.homeIOtools_Callback;
            obj.handles.ribbonHome.reshuffle.ItemPushedFcn = @obj.homeIOtools_Callback;
            %% Add Callbacks for the HOME ribbon -> Preferences
            obj.handles.ribbonHome.loadLayout.ButtonPushedFcn = @obj.homePreferences_Callback;
            obj.handles.ribbonHome.loadLayoutLocalDefault.ItemPushedFcn = @obj.homePreferences_Callback;
            obj.handles.ribbonHome.loadLayoutCustom.ItemPushedFcn = @obj.homePreferences_Callback;
            obj.handles.ribbonHome.loadLayoutMibDefault.ItemPushedFcn = @obj.homePreferences_Callback;
            obj.handles.ribbonHome.saveLayout.ButtonPushedFcn = @obj.homePreferences_Callback;
            obj.handles.ribbonHome.saveLayoutLocalDefault.ItemPushedFcn = @obj.homePreferences_Callback;
            obj.handles.ribbonHome.saveLayoutCustom.ItemPushedFcn = @obj.homePreferences_Callback;
            obj.handles.ribbonHome.saveLayoutMibDefault.ItemPushedFcn = @obj.homePreferences_Callback;
            obj.handles.ribbonHome.preferences.ButtonPushedFcn = @obj.homePreferences_Callback;
            obj.handles.ribbonHome.help.ButtonPushedFcn = @obj.homePreferences_Callback;
            obj.handles.ribbonHome.helpMenu.ItemPushedFcn = @obj.homePreferences_Callback;
            obj.handles.ribbonHome.tipOfDay.ItemPushedFcn = @obj.homePreferences_Callback;
            obj.handles.ribbonHome.support.ItemPushedFcn = @obj.homePreferences_Callback;
            obj.handles.ribbonHome.call4help.ItemPushedFcn = @obj.homePreferences_Callback;
            obj.handles.ribbonHome.classReference.ItemPushedFcn = @obj.homePreferences_Callback;
            obj.handles.ribbonHome.checkUpdate.ItemPushedFcn = @obj.homePreferences_Callback;
            obj.handles.ribbonHome.personalStats.ItemPushedFcn = @obj.homePreferences_Callback;
            obj.handles.ribbonHome.licenses.ItemPushedFcn = @obj.homePreferences_Callback;
            obj.handles.ribbonHome.about.ItemPushedFcn = @obj.homePreferences_Callback;

        end

        function addCallbacksToDatasetRibbon(obj)
            % function addCallbacksToDatasetRibbon(obj)
            % add callbacks to the Dataset ribbon to allow lazy loading

            %% Add Callbacks for the DATASET ribbon -> Alignment
            obj.handles.ribbonDataset.alignment.ButtonPushedFcn = @obj.datasetAlignment_Callback;
            %% Add Callbacks for the DATASET ribbon -> Dataset tools
            obj.handles.ribbonDataset.crop.ButtonPushedFcn = @obj.datasetTools_Callback;
            obj.handles.ribbonDataset.resize.ButtonPushedFcn = @obj.datasetTools_Callback;
            %% Add Callbacks for the DATASET ribbon -> Dataset tools -> Transform
            obj.handles.ribbonDataset.addframeWidth.ItemPushedFcn = @obj.datasetToolsTransform_Callback;
            obj.handles.ribbonDataset.addframedX.ItemPushedFcn = @obj.datasetToolsTransform_Callback;
            obj.handles.ribbonDataset.flipH.ItemPushedFcn = @obj.datasetToolsTransform_Callback;
            obj.handles.ribbonDataset.flipV.ItemPushedFcn = @obj.datasetToolsTransform_Callback;
            obj.handles.ribbonDataset.flipZ.ItemPushedFcn = @obj.datasetToolsTransform_Callback;
            obj.handles.ribbonDataset.flipT.ItemPushedFcn = @obj.datasetToolsTransform_Callback;
            obj.handles.ribbonDataset.rotPos90.ItemPushedFcn = @obj.datasetToolsTransform_Callback;
            obj.handles.ribbonDataset.rotNeg90.ItemPushedFcn = @obj.datasetToolsTransform_Callback;
            obj.handles.ribbonDataset.transposeYX2YZ.ItemPushedFcn = @obj.datasetToolsTransform_Callback;
            obj.handles.ribbonDataset.transposeYX2XZ.ItemPushedFcn = @obj.datasetToolsTransform_Callback;
            obj.handles.ribbonDataset.transposeYX2XY.ItemPushedFcn = @obj.datasetToolsTransform_Callback;
            obj.handles.ribbonDataset.transposeZ2T.ItemPushedFcn = @obj.datasetToolsTransform_Callback;
            obj.handles.ribbonDataset.transposeZ2C.ItemPushedFcn = @obj.datasetToolsTransform_Callback;
            %% Add Callbacks for the DATASET ribbon -> Dataset tools -> Slices
            obj.handles.ribbonDataset.sliceCopy.ItemPushedFcn = @obj.datasetToolsSlices_Callback;
            obj.handles.ribbonDataset.sliceInsert.ItemPushedFcn = @obj.datasetToolsSlices_Callback;
            obj.handles.ribbonDataset.sliceInterval.ItemPushedFcn = @obj.datasetToolsSlices_Callback;
            obj.handles.ribbonDataset.sliceSwap.ItemPushedFcn = @obj.datasetToolsSlices_Callback;
            obj.handles.ribbonDataset.sliceDelete.ItemPushedFcn = @obj.datasetToolsSlices_Callback;
            obj.handles.ribbonDataset.sliceFrameDelete.ItemPushedFcn = @obj.datasetToolsSlices_Callback;
            %% Add Callbacks for the DATASET ribbon -> Calibration section
            obj.handles.ribbonDataset.scalebar.ButtonPushedFcn = @obj.datasetCalibration_Callback;
            obj.handles.ribbonDataset.boundingbox.ButtonPushedFcn = @obj.datasetCalibration_Callback;
            obj.handles.ribbonDataset.voxels.ButtonPushedFcn = @obj.datasetCalibration_Callback;
            %% Add Callbacks for the DATASET ribbon -> Metadata section
            obj.handles.ribbonDataset.log.ButtonPushedFcn = @obj.datasetMetadata_Callback;
            obj.handles.ribbonDataset.info.ButtonPushedFcn = @obj.datasetMetadata_Callback;

        end

        function addCallbacksToDatasetImage(obj)
            % function addCallbacksToDatasetImage(obj)
            % add callbacks to the Image ribbon to allow lazy loading
        
            %% Add Callbacks for the IMAGE ribbon -> Mode
            obj.handles.ribbonImage.grayscale.ValueChangedFcn = @obj.imageMode_Callback;
            obj.handles.ribbonImage.multicolor.ValueChangedFcn = @obj.imageMode_Callback;
            obj.handles.ribbonImage.hsv.ValueChangedFcn = @obj.imageMode_Callback;
            obj.handles.ribbonImage.indexed.ValueChangedFcn = @obj.imageMode_Callback;
            obj.handles.ribbonImage.bit8.ValueChangedFcn = @obj.imageMode_Callback;
            obj.handles.ribbonImage.bit16.ValueChangedFcn = @obj.imageMode_Callback;
            obj.handles.ribbonImage.bit32.ValueChangedFcn = @obj.imageMode_Callback;

            %% Add Callbacks for the IMAGE ribbon -> Image Adjustments
            obj.handles.ribbonImage.display.ButtonPushedFcn = @obj.image_Callbacks;
            % colors
            obj.handles.ribbonImage.colorsInsert.ItemPushedFcn = @obj.imageColors_Callbacks;
            obj.handles.ribbonImage.colorsCopy.ItemPushedFcn = @obj.imageColors_Callbacks;
            obj.handles.ribbonImage.colorsInvert.ItemPushedFcn = @obj.imageColors_Callbacks;
            obj.handles.ribbonImage.colorsRotate.ItemPushedFcn = @obj.imageColors_Callbacks;
            obj.handles.ribbonImage.colorsShift.ItemPushedFcn = @obj.imageColors_Callbacks;
            obj.handles.ribbonImage.colorsSwap.ItemPushedFcn = @obj.imageColors_Callbacks;
            obj.handles.ribbonImage.colorsDelete.ItemPushedFcn = @obj.imageColors_Callbacks;
            % contrast
            obj.handles.ribbonImage.contrastCLAHE.ItemPushedFcn = @obj.imageContrast_Callbacks;
            obj.handles.ribbonImage.contrastNormZ.ItemPushedFcn = @obj.imageContrast_Callbacks;
            obj.handles.ribbonImage.contrastNormZmask.ItemPushedFcn = @obj.imageContrast_Callbacks;
            obj.handles.ribbonImage.contrastNormZmaskBg.ItemPushedFcn = @obj.imageContrast_Callbacks;
            obj.handles.ribbonImage.contrastNormT.ItemPushedFcn = @obj.imageContrast_Callbacks;
            % invert
            obj.handles.ribbonImage.invert2D.ItemPushedFcn = @obj.imageInvert_Callbacks;
            obj.handles.ribbonImage.invert3D.ItemPushedFcn = @obj.imageInvert_Callbacks;
            obj.handles.ribbonImage.invert4D.ItemPushedFcn = @obj.imageInvert_Callbacks;

            %% Add Callbacks for the IMAGE ribbon -> Image Tools
            obj.handles.ribbonImage.filters.ButtonPushedFcn = @obj.image_Callbacks;
            % image tools
            obj.handles.ribbonImage.contentAware.ItemPushedFcn = @obj.imageTools_Callbacks;
            obj.handles.ribbonImage.debrisRemoval.ItemPushedFcn = @obj.imageTools_Callbacks;
            obj.handles.ribbonImage.imageMath.ItemPushedFcn = @obj.imageTools_Callbacks;
            obj.handles.ribbonImage.intProjection.ItemPushedFcn = @obj.imageTools_Callbacks;
            obj.handles.ribbonImage.imgFrame.ItemPushedFcn = @obj.imageTools_Callbacks;
            obj.handles.ribbonImage.whiteBalance.ItemPushedFcn = @obj.imageTools_Callbacks;
            % morph ops
            obj.handles.ribbonImage.botHat.ItemPushedFcn = @obj.imageMorphOps_Callbacks;
            obj.handles.ribbonImage.clearBorder.ItemPushedFcn = @obj.imageMorphOps_Callbacks;
            obj.handles.ribbonImage.morphClose.ItemPushedFcn = @obj.imageMorphOps_Callbacks;
            obj.handles.ribbonImage.dilate.ItemPushedFcn = @obj.imageMorphOps_Callbacks;
            obj.handles.ribbonImage.erode.ItemPushedFcn = @obj.imageMorphOps_Callbacks;
            obj.handles.ribbonImage.fill.ItemPushedFcn = @obj.imageMorphOps_Callbacks;
            obj.handles.ribbonImage.hMax.ItemPushedFcn = @obj.imageMorphOps_Callbacks;
            obj.handles.ribbonImage.hMin.ItemPushedFcn = @obj.imageMorphOps_Callbacks;
            obj.handles.ribbonImage.morphOpen.ItemPushedFcn = @obj.imageMorphOps_Callbacks;
            obj.handles.ribbonImage.topHat.ItemPushedFcn = @obj.imageMorphOps_Callbacks;
            % intensity profile
            obj.handles.ribbonImage.profileLine.ItemPushedFcn = @obj.image_Callbacks;
            obj.handles.ribbonImage.profileArbitrary.ItemPushedFcn = @obj.image_Callbacks;
        end

        function addCallbacksToDatasetModel(obj)
            % function addCallbacksToDatasetModel(obj)
            % add callbacks to the Model ribbon to allow lazy loading

            %% Add Callbacks for the MODEL ribbon -> Convert type
            obj.handles.ribbonModel.mat63.ValueChangedFcn = @obj.modelConvertType_Callback;
            obj.handles.ribbonModel.mat255.ValueChangedFcn = @obj.modelConvertType_Callback;
            obj.handles.ribbonModel.mat65535.ValueChangedFcn = @obj.modelConvertType_Callback;
            obj.handles.ribbonModel.mat4294967295.ValueChangedFcn = @obj.modelConvertType_Callback;
            obj.handles.ribbonModel.indexed2dconn4.ItemPushedFcn = @obj.modelConvertType_Callback;
            obj.handles.ribbonModel.indexed2dconn8.ItemPushedFcn = @obj.modelConvertType_Callback;
            obj.handles.ribbonModel.indexed3dconn4.ItemPushedFcn = @obj.modelConvertType_Callback;
            obj.handles.ribbonModel.indexed3dconn8.ItemPushedFcn = @obj.modelConvertType_Callback;
            %% Add Callbacks for the MODEL ribbon -> Import section
            obj.handles.ribbonModel.new.ButtonPushedFcn = @obj.modelImport_Callback;
            obj.handles.ribbonModel.load.ButtonPushedFcn = @obj.modelImport_Callback;
            obj.handles.ribbonModel.import.ButtonPushedFcn = @obj.modelImport_Callback;
            %% Add Callbacks for the MODEL ribbon -> Export section
            obj.handles.ribbonModel.export.ButtonPushedFcn = @obj.modelExport_Callback;
            obj.handles.ribbonModel.exportToMatlab.ItemPushedFcn = @obj.modelExport_Callback;
            obj.handles.ribbonModel.exportToImaris.ItemPushedFcn = @obj.modelExport_Callback;
            obj.handles.ribbonModel.save.ButtonPushedFcn = @obj.modelExport_Callback;
            obj.handles.ribbonModel.saveAs.ButtonPushedFcn = @obj.modelExport_Callback;
            %% Add Callbacks for the MODEL ribbon -> Model tools section
            % Materials
            obj.handles.ribbonModel.matRename.ItemPushedFcn = @obj.modelMaterials_Callback;
            obj.handles.ribbonModel.matAdd.ItemPushedFcn = @obj.modelMaterials_Callback;
            obj.handles.ribbonModel.matInsert.ItemPushedFcn = @obj.modelMaterials_Callback;
            obj.handles.ribbonModel.matSwap.ItemPushedFcn = @obj.modelMaterials_Callback;
            obj.handles.ribbonModel.matReorder.ItemPushedFcn = @obj.modelMaterials_Callback;
            obj.handles.ribbonModel.matExport.ItemPushedFcn = @obj.modelMaterials_Callback;
            obj.handles.ribbonModel.matSave.ItemPushedFcn = @obj.modelMaterials_Callback;
            obj.handles.ribbonModel.matRemove.ItemPushedFcn = @obj.modelMaterials_Callback;
            % List of annotations
            obj.handles.ribbonModel.annotations.ButtonPushedFcn = @obj.modelAnnotations_Callback;
            obj.handles.ribbonModel.annotationsList.ItemPushedFcn = @obj.modelAnnotations_Callback;
            obj.handles.ribbonModel.annotationsImaris.ItemPushedFcn = @obj.modelAnnotations_Callback;
            obj.handles.ribbonModel.annotationsRemove.ItemPushedFcn = @obj.modelAnnotations_Callback;
            % Render
            obj.handles.ribbonModel.render.ButtonPushedFcn = @obj.modelRender_Callback;
            obj.handles.ribbonModel.renderMIB.ItemPushedFcn = @obj.modelRender_Callback;
            obj.handles.ribbonModel.renderMatlab.ItemPushedFcn = @obj.modelRender_Callback;
            obj.handles.ribbonModel.renderMatlabImaris.ItemPushedFcn = @obj.modelRender_Callback;
            obj.handles.ribbonModel.renderMatlabVolView.ItemPushedFcn = @obj.modelRender_Callback;
            obj.handles.ribbonModel.renderFiji.ItemPushedFcn = @obj.modelRender_Callback;
            obj.handles.ribbonModel.renderImaris.ItemPushedFcn = @obj.modelRender_Callback;
            % Quantification
            obj.handles.ribbonModel.quantification.ButtonPushedFcn = @obj.modelQuantification_Callback;

        end

        function addCallbacksToDatasetMask(obj)
            % function addCallbacksToDatasetMask(obj)
            % add callbacks to the Mask ribbon to allow lazy loading

            %% Add Callbacks for the MASK ribbon -> Mask to Selection
            obj.handles.ribbonMask.maskToSelection2DAdd.ItemPushedFcn = @obj.maskToSelection_Callback;
            obj.handles.ribbonMask.maskToSelection2DRemove.ItemPushedFcn = @obj.maskToSelection_Callback;
            obj.handles.ribbonMask.maskToSelection2DReplace.ItemPushedFcn = @obj.maskToSelection_Callback;
            obj.handles.ribbonMask.maskToSelection3DAdd.ItemPushedFcn = @obj.maskToSelection_Callback;
            obj.handles.ribbonMask.maskToSelection3DRemove.ItemPushedFcn = @obj.maskToSelection_Callback;
            obj.handles.ribbonMask.maskToSelection3DReplace.ItemPushedFcn = @obj.maskToSelection_Callback;
            obj.handles.ribbonMask.maskToSelection4DAdd.ItemPushedFcn = @obj.maskToSelection_Callback;
            obj.handles.ribbonMask.maskToSelection4DRemove.ItemPushedFcn = @obj.maskToSelection_Callback;
            obj.handles.ribbonMask.maskToSelection4DReplace.ItemPushedFcn = @obj.maskToSelection_Callback;
            %% Add Callbacks for the MASK ribbon -> Import section
            obj.handles.ribbonMask.clear.ButtonPushedFcn = @obj.maskImportSection_Callbacks;
            obj.handles.ribbonMask.load.ButtonPushedFcn = @obj.maskImportSection_Callbacks;
            obj.handles.ribbonMask.import.ButtonPushedFcn = @obj.maskImportSection_Callbacks;
            obj.handles.ribbonMask.importFromMatlab.ItemPushedFcn = @obj.maskImportSection_Callbacks;
            obj.handles.ribbonMask.importFromMIB.ItemPushedFcn = @obj.maskImportSection_Callbacks;
            %% Add Callbacks for the MASK ribbon -> Export section
            obj.handles.ribbonMask.export.ButtonPushedFcn = @obj.maskExportSection_Callbacks;
            obj.handles.ribbonMask.exportToMatlab.ItemPushedFcn = @obj.maskExportSection_Callbacks;
            obj.handles.ribbonMask.exportToMIB.ItemPushedFcn = @obj.maskExportSection_Callbacks;
            obj.handles.ribbonMask.save.ButtonPushedFcn = @obj.maskExportSection_Callbacks;
            %% Add Callbacks for the MASK ribbon -> Tools and Quantification section
            obj.handles.ribbonMask.invert.ButtonPushedFcn = @obj.maskToolsQuantifySection_Callbacks;
            obj.handles.ribbonMask.invert2D.ItemPushedFcn = @obj.maskToolsQuantifySection_Callbacks;
            obj.handles.ribbonMask.invert3D.ItemPushedFcn = @obj.maskToolsQuantifySection_Callbacks;
            obj.handles.ribbonMask.invert4D.ItemPushedFcn = @obj.maskToolsQuantifySection_Callbacks;
            obj.handles.ribbonMask.replaceImage.ButtonPushedFcn = @obj.maskToolsQuantifySection_Callbacks;
            obj.handles.ribbonMask.smooth.ButtonPushedFcn = @obj.maskToolsQuantifySection_Callbacks;
            obj.handles.ribbonMask.quantify.ButtonPushedFcn = @obj.maskToolsQuantifySection_Callbacks;
    
        end

        function addCallbacksToDatasetSelection(obj)
            % function addCallbacksToDatasetSelection(obj)
            % add callbacks to the Selection ribbon to allow lazy loading

            %% Add Callbacks for the SELECTION ribbon -> Converts section
            % Selection to mask
            obj.handles.ribbonSelection.selectionToMask2DAdd.ItemPushedFcn = @obj.selectionConverts_Callbacks;
            obj.handles.ribbonSelection.selectionToMask2DRemove.ItemPushedFcn = @obj.selectionConverts_Callbacks;
            obj.handles.ribbonSelection.selectionToMask2DReplace.ItemPushedFcn = @obj.selectionConverts_Callbacks;
            obj.handles.ribbonSelection.selectionToMask3DAdd.ItemPushedFcn = @obj.selectionConverts_Callbacks;
            obj.handles.ribbonSelection.selectionToMask3DRemove.ItemPushedFcn = @obj.selectionConverts_Callbacks;
            obj.handles.ribbonSelection.selectionToMask3DReplace.ItemPushedFcn = @obj.selectionConverts_Callbacks;
            obj.handles.ribbonSelection.selectionToMask4DAdd.ItemPushedFcn = @obj.selectionConverts_Callbacks;
            obj.handles.ribbonSelection.selectionToMask4DRemove.ItemPushedFcn = @obj.selectionConverts_Callbacks;
            obj.handles.ribbonSelection.selectionToMask4DReplace.ItemPushedFcn = @obj.selectionConverts_Callbacks;
            % Selection to buffer
            obj.handles.ribbonSelection.copy.ItemPushedFcn = @obj.selectionConverts_Callbacks;
            obj.handles.ribbonSelection.paste.ItemPushedFcn = @obj.selectionConverts_Callbacks;
            obj.handles.ribbonSelection.pasteAll.ItemPushedFcn = @obj.selectionConverts_Callbacks;
            obj.handles.ribbonSelection.clear.ItemPushedFcn = @obj.selectionConverts_Callbacks;
            %% Add Callbacks for the SELECTION ribbon -> Tools section
            % MorphOps
            obj.handles.ribbonSelection.branch.ItemPushedFcn = @obj.selectionTools_Callbacks;
            obj.handles.ribbonSelection.diag.ItemPushedFcn = @obj.selectionTools_Callbacks;
            obj.handles.ribbonSelection.endpoints.ItemPushedFcn = @obj.selectionTools_Callbacks;
            obj.handles.ribbonSelection.skeleton.ItemPushedFcn = @obj.selectionTools_Callbacks;
            obj.handles.ribbonSelection.spur.ItemPushedFcn = @obj.selectionTools_Callbacks;
            obj.handles.ribbonSelection.thin.ItemPushedFcn = @obj.selectionTools_Callbacks;
            obj.handles.ribbonSelection.ultErosion.ItemPushedFcn = @obj.selectionTools_Callbacks;
            % invert
            obj.handles.ribbonSelection.invert.ButtonPushedFcn = @obj.selectionTools_Callbacks;
            obj.handles.ribbonSelection.invert2D.ItemPushedFcn = @obj.selectionTools_Callbacks;
            obj.handles.ribbonSelection.invert3D.ItemPushedFcn = @obj.selectionTools_Callbacks;
            obj.handles.ribbonSelection.invert4D.ItemPushedFcn = @obj.selectionTools_Callbacks;
            % other tools
            obj.handles.ribbonSelection.expandToMask.ButtonPushedFcn = @obj.selectionTools_Callbacks;
            obj.handles.ribbonSelection.interpolate.ValueChangedFcn = @obj.selectionTools_Callbacks;
            obj.handles.ribbonSelection.replaceImage.ButtonPushedFcn = @obj.selectionTools_Callbacks;
            obj.handles.ribbonSelection.smooth.ButtonPushedFcn = @obj.selectionTools_Callbacks;
        end

        function addCallbacksToDatasetTools(obj)
            % function addCallbacksToDatasetTools(obj)
            % add callbacks to the Tools ribbon to allow lazy loading

            %% Add Callbacks for the SELECTION ribbon -> Segmentation section
            % DeepMIB
            obj.handles.ribbonTools.deepmib.ButtonPushedFcn = @obj.toolsSegmentation_Callbacks;
            % Classifiers
            obj.handles.ribbonTools.membrane.ItemPushedFcn = @obj.toolsSegmentation_Callbacks;
            obj.handles.ribbonTools.supervoxels.ItemPushedFcn = @obj.toolsSegmentation_Callbacks;
            % Semi-automatic
            obj.handles.ribbonTools.globalthres.ItemPushedFcn = @obj.toolsSegmentation_Callbacks;
            obj.handles.ribbonTools.graphcut.ItemPushedFcn = @obj.toolsSegmentation_Callbacks;
            obj.handles.ribbonTools.watershed.ItemPushedFcn = @obj.toolsSegmentation_Callbacks;
            %% Add Callbacks for the SELECTION ribbon -> Misc section
            % Measure length
            obj.handles.ribbonTools.measure.ButtonPushedFcn = @obj.toolsMisc_Callbacks;
            obj.handles.ribbonTools.measureTool.ItemPushedFcn = @obj.toolsMisc_Callbacks;
            obj.handles.ribbonTools.measureLine.ItemPushedFcn = @obj.toolsMisc_Callbacks;
            obj.handles.ribbonTools.measureFreehand.ItemPushedFcn = @obj.toolsMisc_Callbacks;
            % Object separator
            obj.handles.ribbonTools.objects.ButtonPushedFcn = @obj.toolsMisc_Callbacks;
            % Stereology
            obj.handles.ribbonTools.stereology.ButtonPushedFcn = @obj.toolsMisc_Callbacks;
            % Wound healing assay
            obj.handles.ribbonTools.wound.ButtonPushedFcn = @obj.toolsMisc_Callbacks;


        end

    end
end


