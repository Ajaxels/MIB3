classdef MembranePixClassifier < handle
    % MEMBRANEPIXCLASSIFIER - Random forest membrane/pixel classifier controller.
    %
    % Uses Random Forest for Membrane Detection by Verena Kaynig.
    % See http://www.kaynig.de/demos.html
    %
    % Available from: Ribbon -> Tools -> Membrane detector
    %
    % Syntax:
    %   .. code-block:: matlab
    %
    %       obj = controllers.MembranePixClassifier(mibModel)
    %       obj = controllers.MembranePixClassifier(mibModel, extraController)
    %       obj = controllers.MembranePixClassifier(mibModel, [], BatchOpt)
    %
    % Input Arguments:
    %   - **mibModel** - handle to the MibModel instance
    %   - **extraController** - *(optional)* handle to a parent controller
    %   - **BatchOpt** - *(optional)* struct with batch options, or ``NaN`` to return defaults
    %

    properties
        mibModel
        % handle to MibModel
        view
        % handle to the view (core.ChildView); empty in headless batch mode
        listener
        % cell array of listener handles
        BatchOpt
        % batch processing options structure
        classFilename
        % full path to the .forest classifier file
        dirOut
        % directory for temporary .fm feature files
        maxNumberOfSamplesPerClass
        % maximum number of training samples per class
        forest
        % trained random forest classifier structure
    end

    events
        CloseEvent
        % fires when the dialog window is closed
    end

    methods (Static)
        function ViewListner_Callback2(obj, ~, evnt)
            if ~isvalid(obj) || isempty(obj.view) || ~isvalid(obj.view.gui)
                for i = 1:numel(obj.listener); delete(obj.listener{i}); end
                return;
            end
            switch evnt.EventName
                case {'UpdateGuiWidgets', 'NewDataset'}
                    obj.updateWidgets();
            end
        end
    end

    methods
        function obj = MembranePixClassifier(mibModel, varargin)
            obj.mibModel = mibModel;

            obj.maxNumberOfSamplesPerClass = 500;
            obj.forest = [];

            id = obj.mibModel.getActiveId();
            obj.dirOut = fullfile(obj.mibModel.currentDirectory, 'RF_Temp');
            [~, baseFilename] = fileparts(obj.mibModel.I{id}.image.filename);
            obj.classFilename = fullfile(obj.dirOut, [baseFilename '.forest']);

            %% BatchOpt defaults
            obj.BatchOpt.Mode           = {'trainClassifier', {'trainClassifier', 'predictDataset'}};
            obj.BatchOpt.ObjectMaterial         = {'', {''}};
            obj.BatchOpt.BackgroundMaterial     = {'', {''}};
            obj.BatchOpt.ContextSize{1}         = 29;
            obj.BatchOpt.ContextSize{2}         = [1 Inf];
            obj.BatchOpt.ContextSize{3}         = true;
            obj.BatchOpt.MembraneThickness{1}   = 3;
            obj.BatchOpt.MembraneThickness{2}   = [1 Inf];
            obj.BatchOpt.MembraneThickness{3}   = true;
            obj.BatchOpt.VotesThreshold{1}      = 0.5;
            obj.BatchOpt.VotesThreshold{2}      = [0 1];
            obj.BatchOpt.VotesThreshold{3}      = false;
            obj.BatchOpt.ExportVotes            = false;
            obj.BatchOpt.SkelClosed             = false;
            obj.BatchOpt.ClassifierFilename     = obj.classFilename;
            obj.BatchOpt.TempDir                = obj.dirOut;
            obj.BatchOpt.mibBatchSectionName    = 'Ribbon -> Tools';
            obj.BatchOpt.mibBatchActionName     = 'Membrane PixClassifier';
            obj.BatchOpt.mibBatchTooltip.Mode               = 'Operation mode: train a new classifier or predict using an existing one';
            obj.BatchOpt.mibBatchTooltip.ObjectMaterial     = 'Name of the material representing the object (membrane) used for training';
            obj.BatchOpt.mibBatchTooltip.BackgroundMaterial = 'Name of the material representing the background used for training';
            obj.BatchOpt.mibBatchTooltip.ContextSize        = 'Context size (pixels) for membrane feature extraction';
            obj.BatchOpt.mibBatchTooltip.MembraneThickness  = 'Expected membrane thickness in pixels';
            obj.BatchOpt.mibBatchTooltip.VotesThreshold     = 'Threshold applied to classifier votes to produce binary segmentation (0-1)';
            obj.BatchOpt.mibBatchTooltip.ExportVotes        = 'Export raw classifier votes to the MATLAB workspace as mibVotes variable';
            obj.BatchOpt.mibBatchTooltip.SkelClosed         = 'Apply skeletonize + dilate morphological closing to the prediction result';
            obj.BatchOpt.mibBatchTooltip.ClassifierFilename = 'Full path to the .forest classifier file for saving/loading';
            obj.BatchOpt.mibBatchTooltip.TempDir            = 'Directory for storing temporary membrane feature files (.fm)';

            %% batch dispatch
            if nargin == 3
                BatchOptInput = varargin{2};
                if ~isstruct(BatchOptInput)
                    if isnan(BatchOptInput)
                        obj.returnBatchOpt();
                    else
                        utils.dlgs.showErrorDialog([], 'A structure as the 3rd parameter is required!', 'BatchOpt Error');
                    end
                    return;
                end
                obj.BatchOpt = utils.updateBatchOptCombineFields_Shared(obj.BatchOpt, BatchOptInput);
                if ~isempty(obj.BatchOpt.ClassifierFilename)
                    obj.classFilename = obj.BatchOpt.ClassifierFilename;
                end
                if ~isempty(obj.BatchOpt.TempDir)
                    obj.dirOut = obj.BatchOpt.TempDir;
                end
                switch obj.BatchOpt.Mode{1}
                    case 'trainClassifier'; obj.trainClassifier();
                    case 'predictDataset';  obj.predictDataset();
                end
                return;
            end

            %% GUI mode
            obj.view = core.ChildView(obj, 'views.MembranePixClassifierGUI');
            obj.updateWidgets();
            utils.updateGUIFromBatchOpt_Shared(obj.view, obj.BatchOpt);
            obj.addCallbacks();

            Font = obj.mibModel.preferences.System.Font;
            if obj.view.handles.closeButton.FontSize ~= Font.FontSize ...
                    || ~strcmp(obj.view.handles.closeButton.FontName, Font.FontName)
                utils.fontSizeUpdate(obj.view.gui, Font);
            end
            obj.view.gui = utils.moveWindowOutside(obj.view.gui, obj.mibModel.mibGUI, 'left');

            obj.listener{1} = addlistener(obj.mibModel, 'UpdateGuiWidgets', @(src,evnt) obj.ViewListner_Callback2(obj, src, evnt));
            obj.listener{2} = addlistener(obj.mibModel, 'NewDataset',       @(src,evnt) obj.ViewListner_Callback2(obj, src, evnt));

            obj.view.gui.Visible = true;
        end
    end
end
