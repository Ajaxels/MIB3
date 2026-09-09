classdef MibDeepActivations < handle
% MIBDEEPACTIVATIONS - @type MibDeepActivations class is a template class for using with.
%
% GUI developed using appdesigner of Matlab
%
%
% .. code-block:: matlab
%
%   obj.startController('MibDeepActivations'); // as GUI tool
%
% or
%
% .. code-block:: matlab
%
%   // a code below was used for mibImageArithmeticController
%   BatchOpt.Parameter = 'test';  // fill edit boxes as strings
%   BatchOpt.Checkbox = true;     // fill checkboxes with logicals: true/false
%   BatchOpt.Popup = {'value'};        // value for the popups as a cell
%   BatchOpt.Radio = {'Radio1'};          // selection of radio buttons, as cell with the handle of the target radio button
%   BatchOpt.showWaitbar = true;  // show or not the waitbar
%   obj.startController('MibDeepActivations', [], BatchOpt); // start MibDeepActivations in the batch mode
%
% or
%
% .. code-block:: matlab
%
%   // trigger return of the possible Options using returnBatchOpt function
%   // using notify syncBatch event
%   obj.startController('MibDeepActivations', [], NaN);
    
	% Updates
	%     
    
    properties
        mibModel
        % handles to mibModel
        view
        % handle to the view / mibDeepActivationsGUI
        listener
        % a cell array with handles to listeners
        mibDeep
        % a handle to parent mibDeep controller
        BatchOpt
        % a structure compatible with batch operation
        % name of each field should be displayed in a tooltip of GUI
        % it is recommended that the Tags of widgets match the name of the
        % fields in this structure
        % .NetworkLayerName{1} - [dropdown],  cell string with the desired layer; NetworkLayerName{2} - [optional], an array with possible layers
        % .ImageFilename{1} - [dropdown],  cell string with the file name to show
        % .z1{1} - numeric, number of slice for 3D datasets to show
        % .x1{1} - numeric, image shift in x
        % .y1{1} - numeric, image shift in y
        % .patchZ{1} - numeric, position inside the activation block
        % .filterId{1} - numeric, filter id of the activation block
        imgDS
        % imageDatastore with images to be be explored
        imageOriginal
        % a cropped original image that will be used to get activations, [height, width, color, depth]
        imageActivation
        % returned activations for the imageOriginal
        deltaZ
        % difference between the Z of the image and the show patch patch Z
        patchNetworkDims
        % dimensions of network layer patch
        net
        % a structure with the loaded network file
        % .AugOpt2DStruct             1x1                 1690  struct
        % .AugOpt3DStruct             1x1                 1253  struct
        % .BatchOpt                   1x1                23881  struct
        % .InputLayerOpt              1x1                  928  struct
        % .TrainingOptionsStruct      1x1                 2060  struct
        % .classNames                 4x1                  492  cell
        % .inputPatchSize             1x4                   32  double
        % .net                        1x1             30905044  DAGNetwork
        % .outputPatchSize            1x4                   32  double
    end
    
    events
        %> Description of events
        CloseEvent
        % event firing when window is closed
    end
    
    methods (Static)
        function ViewListner_Callback(obj, src, evnt)
            switch evnt.EventName
                case {'UpdateGuiWidgets'}
                    %obj.updateWidgets();
            end
        end
    end
    
    methods
        function obj = MibDeepActivations(mibModel, varargin)
            obj.mibModel = mibModel;    % assign model
            obj.mibDeep = varargin{1};  % assign handle to mibDeepController
            
            if exist(obj.mibDeep.BatchOpt.NetworkFilename, 'file') ~= 2
                errorOpts.mibPath = obj.mibModel.mibPath;
                errorOpts.WindowHeight = 150;
                errorText = sprintf('The network file was not found!\n\n%s', obj.mibDeep.BatchOpt.NetworkFilename);
                utils.dlgs.showErrorDialog(obj.mibDeep.view.gui, errorText, 'Error', 'Error in controllers.MibDeepActivations', '', errorOpts);
                notify(obj, 'CloseEvent');      % notify mibController that this child window is closed
                return;
            end
            
            % loading the following fields
            obj.net = load(obj.mibDeep.BatchOpt.NetworkFilename, '-mat');
            obj.deltaZ = 0;     % difference between the Z of the image and the show patch patch Z
            
            % init the image store
            if strcmp(obj.mibDeep.BatchOpt.PreprocessingMode{1}, 'Preprocessing is not required') || strcmp(obj.mibDeep.BatchOpt.PreprocessingMode{1}, 'Split files for training/validation')
                % prepare options for loading images
                mibDeepStoreLoadImagesOpt.mibBioformatsCheck = obj.mibDeep.BatchOpt.Bioformats;
                mibDeepStoreLoadImagesOpt.BioFormatsIndices = obj.mibDeep.BatchOpt.BioformatsIndex{1};
                mibDeepStoreLoadImagesOpt.Workflow = obj.mibDeep.BatchOpt.Workflow{1};
                fnExtention = lower(['.' obj.mibDeep.BatchOpt.ImageFilenameExtension{1}]);
                imgPath = fullfile(obj.mibDeep.BatchOpt.OriginalPredictionImagesDir, 'Images');
                if exist(imgPath, 'dir') == 0
                    imgPath = obj.mibDeep.BatchOpt.OriginalPredictionImagesDir;
                end

                obj.imgDS = imageDatastore(imgPath, ...
                        'FileExtensions', fnExtention, ...
                        'IncludeSubfolders', false, ...
                        'ReadFcn', @(fn)deepmib.storeLoadImages(fn, mibDeepStoreLoadImagesOpt));
            else
                obj.imgDS = imageDatastore(fullfile(obj.mibDeep.BatchOpt.ResultingImagesDir, 'PredictionImages'), ...
                    'FileExtensions', '.mibImg', 'ReadFcn', @deepmib.storeLoadImages);
            end
            
            [~, fnames] = arrayfun(@(x) fileparts(cell2mat(x)), obj.imgDS.Files, 'UniformOutput', false);   % get filenames
            
            %% fill the BatchOpt structure with default values
            % fields of the structure should correspond to the starting
            % text in the each widget tooltip.
            % For example, this demo template has an edit box, where the
            % tooltip starts with "Parameter:...". Text Parameter
            % indicates field of the BatchOpt structure that defines value
            % for this widget
            
            obj.BatchOpt.ImageFilename = fnames(1);
            obj.BatchOpt.ImageFilename{2} = fnames;
            obj.BatchOpt.NetworkLayerName = {obj.net.net.Layers(1).Name};
            obj.BatchOpt.NetworkLayerName{2} = {obj.net.net.Layers.Name};
            obj.BatchOpt.z1{1} = 1;     % slice number
            obj.BatchOpt.z1{2} = [0.999 1.001]; % the limits should be different
            obj.BatchOpt.z1{3} = 'on';
            obj.BatchOpt.x1{1} = 1;     % image shift x
            obj.BatchOpt.x1{2} = [0.999 1.001]; % the limits should be different
            obj.BatchOpt.x1{3} = 'on';
            obj.BatchOpt.y1{1} = 1;     % image shift y
            obj.BatchOpt.y1{2} = [0.999 1.001]; % the limits should be different
            obj.BatchOpt.y1{3} = 'on';
            obj.BatchOpt.patchZ{1} = 1;     % z position inside the activation block
            obj.BatchOpt.patchZ{2} = [0.999 1.001]; % the limits should be different
            obj.BatchOpt.patchZ{3} = 'on';
            obj.BatchOpt.filterId{1} = 1;     % filter id of the activation block
            obj.BatchOpt.filterId{2} = [0.999 1.001]; % the limits should be different
            obj.BatchOpt.filterId{3} = 'on';
            
            % comment it if intended use not from the batch mode
            % obj.BatchOpt.mibBatchSectionName = 'Menu -> Plugins';    % section name for the Batch
            % obj.BatchOpt.mibBatchActionName = 'mibDeepActivations';           % name of the plugin
            obj.BatchOpt.mibBatchTooltip.ImageFilename = sprintf('Files in the prediction image store');
            obj.BatchOpt.mibBatchTooltip.NetworkLayerName = sprintf('Select the layer of the network to explore');
            obj.BatchOpt.mibBatchTooltip.z1 = sprintf('Slice number for 3D datasets');
            obj.BatchOpt.mibBatchTooltip.x1 = sprintf('Shift the input dataset in X; may be slow');
            obj.BatchOpt.mibBatchTooltip.y1 = sprintf('Shift the input dataset in Y; may be slow');
            obj.BatchOpt.mibBatchTooltip.patchZ = sprintf('z position inside the activation block');
            obj.BatchOpt.mibBatchTooltip.filterId = sprintf('filter id of the activation block');
            
            %% add here a code for the batch mode, for example
            % when the BatchOpt structure is provided the controller will
            % use it as the parameters, and performs the function in the
            % headless mode without GUI
            if nargin == 3
                BatchOptIn = varargin{2};
                if isstruct(BatchOptIn) == 0 
                    if isnan(BatchOptIn)     % when varargin{2} == NaN return possible settings
                        obj.returnBatchOpt();   % obtain Batch parameters
                    else
                        errorOpts.mibPath = obj.mibModel.mibPath;
                        errorOpts.WindowHeight = 150;
                        utils.dlgs.showErrorDialog(obj.mibDeep.view.gui, sprintf('A structure as the 3rd parameter is required!'), 'Error', 'Error in controllers.MibDeepActivations', '', errorOpts);
                    end
                    notify(obj, 'CloseEvent'); 
                    return
                end
                % add/update BatchOpt with the provided fields in BatchOptIn
                % combine fields from input and default structures
                obj.BatchOpt = utils.updateBatchOptCombineFields_Shared(obj.BatchOpt, BatchOptIn);
                
                %obj.Calculate();
                notify(obj, 'CloseEvent');
                return;
            end
            
            guiName = 'views.MibDeepActivationsGUI';
            obj.view = core.ChildView(obj, guiName); % initialize the view
            
            % update font and size
            Font = obj.mibModel.preferences.System.Font;
            if obj.view.handles.NumberFilersLabel.FontSize ~= Font.FontSize ...
                    || ~strcmp(obj.view.handles.NumberFilersLabel.FontName, Font.FontName)
                utils.fontSizeUpdate(obj.view.gui, Font);
            end

            % move the window to the left hand side of the main window
            obj.view.gui = utils.moveWindowOutside(obj.view.gui, obj.mibModel.mibGUI, 'right');
            
			% update widgets from the BatchOpt structure
            obj.view = utils.updateGUIFromBatchOpt_Shared(obj.view, obj.BatchOpt);
            
			% add listener to obj.mibModel and call controller function as a callback
            obj.listener{1} = addlistener(obj.mibModel, 'UpdateGuiWidgets', @(src,evnt) obj.ViewListner_Callback(obj, src, evnt));    % listen changes in number of ROIs
            
            status = obj.getNewImage();
            if status == 0; obj.closeWindow(); return; end
            obj.view.gui.Visible = 'on';

            obj.getActivations()
            obj.updateWidgets();
        end
        
        function closeWindow(obj)
            % CLOSEWINDOW - closing MibDeepActivations window.
            %
            % Syntax:
            %   function closeWindow(obj)
            %
            if isvalid(obj.view.gui)
                delete(obj.view.gui);   % delete childController window
            end
            
            % delete listeners, otherwise they stay after deleting of the
            % controller
            for i=1:numel(obj.listener)
                delete(obj.listener{i});
            end
            
            notify(obj, 'CloseEvent');      % notify mibController that this child window is closed
        end
        
        function updateWidgets(obj)
            % UPDATEWIDGETS - update widgets of this window.
            %
            % Syntax:
            %   function updateWidgets(obj)
            %
            
            % updateWidgets normally triggered during change of MIB
            % buffers, make sure that any widgets related changes are
            % correctly propagated into the BatchOpt structure
            if isfield(obj.BatchOpt, 'id'); obj.BatchOpt.id = obj.mibModel.Id; end
            
            % when elements GIU needs to be updated, update obj.BatchOpt
            % structure and after that update elements of GUI by the
            % following function
            obj.view = utils.updateGUIFromBatchOpt_Shared(obj.view, obj.BatchOpt);    %
            
            if strcmp(obj.net.BatchOpt.Workflow{1}(1:2), '2D')
                obj.view.Figure.z1.Enable = 'off';
                obj.view.Figure.patchZ.Enable = 'off';
                if ~isempty(obj.imageActivation)
                    obj.view.Figure.PatchSizeLabel.Text = sprintf('Patch size: %d x %d px', size(obj.imageActivation,1), size(obj.imageActivation,2));
                    obj.view.Figure.NumberFilersLabel.Text = sprintf('Number of filters: %d', size(obj.imageActivation,3));
                end
            else
                obj.view.Figure.z1.Enable = 'on';
                obj.view.Figure.z1.Limits = obj.BatchOpt.z1{2};
                obj.view.Figure.patchZ.Enable = 'on';
                obj.view.Figure.patchZ.Limits = obj.BatchOpt.patchZ{2};
                if ~isempty(obj.imageActivation)
                    obj.view.Figure.PatchSizeLabel.Text = sprintf('Patch size: %d x %d x %d px', size(obj.imageActivation,1), size(obj.imageActivation,2), size(obj.imageActivation,3));
                    obj.view.Figure.NumberFilersLabel.Text = sprintf('Number of filters: %d', size(obj.imageActivation,4));
                end
            end

        end
        
        function updateBatchOptFromGUI(obj, event)
            % UPDATEBATCHOPTFROMGUI - update obj.BatchOpt from widgets of GUI.
            %
            % Syntax:
            %   function updateBatchOptFromGUI(obj, event)
            %
            % use an external function (Tools\updateBatchOptFromGUI_Shared.m) that is common for all tools
            % compatible with the Batch mode
            %
            % Input Arguments:
            %   - **event** - event from the callback
            %
            obj.BatchOpt = utils.updateBatchOptFromGUI_Shared(obj.BatchOpt, event.Source);
        end
        
        function returnBatchOpt(obj, BatchOptOut)
            % RETURNBATCHOPT - return structure with Batch Options and possible configurations.
            %
            % Syntax:
            %   function returnBatchOpt(obj, BatchOptOut)
            %
            % via the notify 'syncBatch' event
            %
            % Input Arguments:
            %   - **BatchOptOut** - a local structure with Batch Options generated
            %     during Continue callback. It may contain more fields than
            %     obj.BatchOpt structure
            %
            if nargin < 2; BatchOptOut = obj.BatchOpt; end
            
            if isfield(BatchOptOut, 'id'); BatchOptOut = rmfield(BatchOptOut, 'id'); end  % remove id field
            % trigger syncBatch event to send BatchOptOut to mibBatchController 
            eventdata = ToggleEventData(BatchOptOut);
            notify(obj.mibModel, 'syncBatch', eventdata);
        end
        
        function status = getNewImage(obj, filename)
            % GETNEWIMAGE - load a new image from prediction image store.
            %
            % Syntax:
            %   function status = getNewImage(obj, filename)
            %
            % Input Arguments:
            %   - **filename** - short filename of the image to show
            %
            % Output Arguments:
            %   - **status** - logical switch, 1 - success
            %
            status = 0;
            if nargin < 2; filename = obj.view.Figure.ImageFilename.Value; end
            filenameIndex = find(ismember(obj.view.Figure.ImageFilename.Items, filename)==1);
            
            obj.imageOriginal = readimage(obj.imgDS, filenameIndex);    % [height width depth, color]
            
            % set available shifts
            obj.BatchOpt.x1{1} = min([obj.BatchOpt.x1{1} size(obj.imageOriginal,2)-obj.net.inputPatchSize(2)+1]);   % value for the spinner
            obj.BatchOpt.x1{2} = [1 size(obj.imageOriginal,2)-obj.net.inputPatchSize(2)+1];   % limits for the spinner
            %if  obj.BatchOpt.x1{2}(1) == obj.BatchOpt.x1{2}(2); obj.BatchOpt.x1{2}(1) = obj.BatchOpt.x1{2}(1)-.1; end
            obj.BatchOpt.y1{1} = min([obj.BatchOpt.y1{1} size(obj.imageOriginal,1)-obj.net.inputPatchSize(1)+1]);   % value for the spinner
            obj.BatchOpt.y1{2} = [1 size(obj.imageOriginal,1)-obj.net.inputPatchSize(1)+1];   % limits for the spinner
            %if  obj.BatchOpt.y1{2}(1) == obj.BatchOpt.y1{2}(2); obj.BatchOpt.y1{2}(1) = obj.BatchOpt.y1{2}(1)-.1; end
            obj.view.Figure.x1.Value = obj.BatchOpt.x1{1};
            obj.view.Figure.y1.Value = obj.BatchOpt.y1{1};
            
            if strcmp(obj.net.BatchOpt.Workflow{1}(1:2), '2D')
                if ndims(obj.imageOriginal) == 4
                    errordlg(sprintf('!!! Error !!!\n\nImage dimensions and the network type mismatch!\n\nNetwork: %s\nImage size: %d x %d x %d x %d', obj.net.BatchOpt.Architecture{1},...
                        size(obj.imageOriginal,1), size(obj.imageOriginal,2), size(obj.imageOriginal,3), size(obj.imageOriginal,4)),...
                        'Wrong image store');
                    return;
                end
                % crop image to match input size
                obj.imageOriginal = obj.imageOriginal(obj.BatchOpt.y1{1}:obj.BatchOpt.y1{1}+obj.net.inputPatchSize(1)-1, obj.BatchOpt.x1{1}:obj.BatchOpt.x1{1}+obj.net.inputPatchSize(2)-1, :);
            else
%                 % these can not be used because 3D datasets with 1 color channel have 3 dimensions                
%                 if ndims(obj.imageOriginal) == 3
%                     errordlg(sprintf('!!! Error !!!\n\nImage dimensions and the network type mismatch!\n\nNetwork: %s\nImage size: %d x %d x %d ', obj.net.BatchOpt.Architecture{1},...
%                         size(obj.imageOriginal,1), size(obj.imageOriginal,2), size(obj.imageOriginal,3)),...
%                         'Wrong image store');
%                     return;
%                 end
                % crop image to match input size
                obj.imageOriginal = obj.imageOriginal(obj.BatchOpt.y1{1}:obj.BatchOpt.y1{1}+obj.net.inputPatchSize(1)-1, obj.BatchOpt.x1{1}:obj.BatchOpt.x1{1}+obj.net.inputPatchSize(2)-1, :, :);
                % permute dimensions to [height, width, color, depth]
                obj.imageOriginal = permute(obj.imageOriginal, [1 2 4 3]);
                obj.BatchOpt.z1{2} = [1 size(obj.imageOriginal, 4)];
            end
            obj.updatePreviewImage();   % update the original image preview
            status = 1;
        end
        
        function updatePreviewImage(obj)
            % UPDATEPREVIEWIMAGE - update preview of the original image.
            %
            % Syntax:
            %   function updatePreviewImage(obj)
            %
            
            if size(obj.imageOriginal, 3) == 1  % grayscale image
                imgToPrev = repmat(squeeze(obj.imageOriginal(:, :, 1, obj.BatchOpt.z1{1})), [1 1 3]);
            else
                imgToPrev = zeros([size(obj.imageOriginal, 1) size(obj.imageOriginal, 2) 3], class(obj.imageOriginal));    
                for colCh=1:min([3 size(obj.imageOriginal, 3)])
                    imgToPrev(:,:,colCh) = squeeze(obj.imageOriginal(:, :, colCh, obj.BatchOpt.z1{1}));
                end
            end
            imgToPrev = imadjust(imgToPrev,stretchlim(imgToPrev),[]);   % stretch contrast
            obj.view.Figure.ImageOriginal.ImageSource = imgToPrev;
        end
        
        function ShiftImage(obj, event)
            % SHIFTIMAGE - callback for change of x1, y1, z1 coordinates to shift the.
            %
            % Syntax:
            %   function ShiftImage(obj, event)
            %
            % patch
            
            % make true to generate snapshots of all patche
            generateSnapshots = false; 
            if generateSnapshots
                silentMode = true;
                for i = 1:numel(obj.BatchOpt.NetworkLayerName{2})
                    obj.BatchOpt.NetworkLayerName(1) = obj.BatchOpt.NetworkLayerName{2}(i);
                    obj.getActivations();
                    obj.makeCollage(silentMode);
                end
                return;
            end

            switch event.Source.Tag
                case 'z1'      % change slice number
                    obj.updatePreviewImage();   % 3D preview for the cropped area cached
                    if strcmp(obj.net.BatchOpt.Workflow{1}(1:2), '3D')
                        value = obj.BatchOpt.z1{1} + obj.deltaZ;
                        value = max([1 value]);
                        value = min([value obj.view.Figure.patchZ.Limits(2)]);
                        obj.BatchOpt.patchZ{1} = value;
                        obj.view.Figure.patchZ.Value = obj.BatchOpt.patchZ{1};
                        obj.showActivations();
                    end
                case {'x1', 'y1'}
                    obj.getNewImage();          % x/y shifts require loading of a new subset
            end
        end
        
        function getActivations(obj)
            % GETACTIVATIONS - from the selected image area generate activations.
            %
            % Syntax:
            %   function getActivations(obj)
            %
            wb = uiprogressdlg(obj.view.gui, 'Value', 0, 'Message', sprintf('Generating previews\nPlease wait...'), 'Title', 'Get activations');
            
            switch obj.net.BatchOpt.Workflow{1}(1:2)
                case '3D'
                    blockDepth = obj.net.inputPatchSize(3);
                    maxZ = size(obj.imageOriginal, 4);
                    dz1 = obj.net.inputPatchSize(3)/2+1;    % patch shift to down
                    dz2 = obj.net.inputPatchSize(3)/2;  % z patch shift to up
                    z1 = obj.BatchOpt.z1{1} - dz1;
                    if z1 < 1
                        obj.BatchOpt.patchZ{1} = dz1 + z1;
                        z1 = 1;
                        z2 = blockDepth;
                    else
                        z2 = obj.BatchOpt.z1{1} + dz2;
                        if z2 > maxZ
                            obj.BatchOpt.patchZ{1} = obj.BatchOpt.z1{1} - (maxZ - blockDepth);
                            z2 = maxZ;
                            z1 = maxZ - blockDepth + 1;
                        else
                            z2 = z1 + blockDepth - 1;
                            obj.BatchOpt.patchZ{1} = dz1 + 1;
                        end
                    end
                    
                    %z2 = min([z2 size(obj.imageOriginal, 4)]);  % tweak to show input image
                    imgBlock = permute(obj.imageOriginal(:,:,:,z1:z2), [1 2 4 3]);
                    if obj.mibDeep.mibController.matlabVersion >= 24 && isa(obj.net.net, 'dlnetwork')
                        obj.imageActivation = minibatchpredict(obj.net.net, imgBlock, Outputs=obj.BatchOpt.NetworkLayerName{1});
                    else
                        obj.imageActivation = activations(obj.net.net, imgBlock, obj.BatchOpt.NetworkLayerName{1});
                    end
                    obj.patchNetworkDims = size(obj.imageActivation);
                    
                    obj.imageActivation = padarray(obj.imageActivation, ...
                        [(obj.net.inputPatchSize(1)-obj.patchNetworkDims(1))/2, ...
                         (obj.net.inputPatchSize(2) - obj.patchNetworkDims(2))/2, ...
                         (obj.net.inputPatchSize(3) - obj.patchNetworkDims(3))/2, ...
                          0], 0, 'both');
                    
                    obj.BatchOpt.patchZ{2} = [1 size(obj.imageActivation,3)];
                    obj.BatchOpt.filterId{1} = min([obj.BatchOpt.filterId{1} size(obj.imageActivation,4)]);
                    obj.BatchOpt.filterId{2} = [1 size(obj.imageActivation,4)];
                    obj.deltaZ = obj.BatchOpt.patchZ{1} - obj.BatchOpt.z1{1};
                case '2.' % 2.5D
                    blockDepth = obj.net.inputPatchSize(3);
                    maxZ = size(obj.imageOriginal, 4);
                    dz1 = floor(obj.net.inputPatchSize(3)/2);    % patch shift to down
                    dz2 = floor(obj.net.inputPatchSize(3)/2);  % z patch shift to up
                    z1 = obj.BatchOpt.z1{1} - dz1;
                    if z1 < 1
                        obj.BatchOpt.patchZ{1} = dz1 + z1;
                        z1 = 1;
                        z2 = blockDepth;
                    else
                        z2 = obj.BatchOpt.z1{1} + dz2;
                        if z2 > maxZ
                            obj.BatchOpt.patchZ{1} = obj.BatchOpt.z1{1} - (maxZ - blockDepth);
                            z2 = maxZ;
                            z1 = maxZ - blockDepth + 1;
                        else
                            z2 = z1 + blockDepth - 1;
                            obj.BatchOpt.patchZ{1} = dz1 + 1;
                        end
                    end
                    
                    %z2 = min([z2 size(obj.imageOriginal, 4)]);  % tweak to show input image
                    imgBlock = permute(obj.imageOriginal(:,:,:,z1:z2), [1 2 4 3]);
                    if obj.mibDeep.mibController.matlabVersion >= 24 && isa(obj.net.net, 'dlnetwork')
                        obj.imageActivation = minibatchpredict(obj.net.net, imgBlock, Outputs=obj.BatchOpt.NetworkLayerName{1});
                    else
                        obj.imageActivation = activations(obj.net.net, imgBlock, obj.BatchOpt.NetworkLayerName{1});
                    end
                    obj.patchNetworkDims = size(obj.imageActivation);
                    
                    % code adapted for 2.5 but it might be that the first
                    % part will also work fine with 3D, need to check
                    if obj.net.BatchOpt.Workflow{1}(1) == '2'
                        if numel(obj.patchNetworkDims) > 2
                            % obj.imageActivation = padarray(obj.imageActivation, ...
                            %     [0, ...
                            %     0, ...
                            %     (obj.net.inputPatchSize(3) - obj.patchNetworkDims(3))/2, ...
                            %     0], 0, 'both');
                            obj.imageActivation = permute(obj.imageActivation, [1 2 4 3]);
                        end
                    else
                        obj.imageActivation = padarray(obj.imageActivation, ...
                            [(obj.net.inputPatchSize(1) - obj.patchNetworkDims(1))/2, ...
                            (obj.net.inputPatchSize(2) - obj.patchNetworkDims(2))/2, ...
                            (obj.net.inputPatchSize(3) - obj.patchNetworkDims(3))/2, ...
                            0], 0, 'both');
                    end

                    obj.BatchOpt.patchZ{2} = [1 size(obj.imageActivation,3)+.0001];
                    if obj.BatchOpt.patchZ{1} > obj.BatchOpt.patchZ{2}
                        obj.BatchOpt.patchZ{1} = obj.BatchOpt.patchZ{2}(1);
                    end
                    obj.BatchOpt.filterId{1} = min([obj.BatchOpt.filterId{1} size(obj.imageActivation,4)]);
                    obj.BatchOpt.filterId{2} = [1 size(obj.imageActivation,4)];
                    obj.deltaZ = obj.BatchOpt.patchZ{1} - obj.BatchOpt.z1{1};
                case '2D'
                    if size(obj.imageOriginal, 3) == obj.net.inputPatchSize(4)   % 2D dataset
                        if obj.mibDeep.mibController.matlabVersion >= 24 && isa(obj.net.net, 'dlnetwork') 
                            obj.imageActivation = minibatchpredict(obj.net.net, obj.imageOriginal, Outputs=obj.BatchOpt.NetworkLayerName{1});
                        else
                            obj.imageActivation = activations(obj.net.net, obj.imageOriginal, obj.BatchOpt.NetworkLayerName{1});
                        end
                    else    % 3D dataset to predict using 2D network
                        z1 = obj.BatchOpt.z1{1};
                        if obj.mibDeep.mibController.matlabVersion >= 24 && isa(obj.net.net, 'dlnetwork')
                            obj.imageActivation = minibatchpredict(obj.net.net, obj.imageOriginal(:,:,z1), Outputs=obj.BatchOpt.NetworkLayerName{1});
                        else
                            obj.imageActivation = activations(obj.net.net, obj.imageOriginal(:,:,z1), obj.BatchOpt.NetworkLayerName{1});
                        end
                    end
                    obj.patchNetworkDims = size(obj.imageActivation);
                    obj.BatchOpt.filterId{1} = min([obj.BatchOpt.filterId{1} size(obj.imageActivation,3)]);
                    obj.BatchOpt.filterId{2} = [1 size(obj.imageActivation,3)];
            end
            wb.Value = 0.99;
            obj.updateWidgets();
            obj.showActivations();
            wb.Value = 1;
            delete(wb);
        end
        
        function showActivations(obj)
            % SHOWACTIVATIONS - show activations for the current image.
            %
            % Syntax:
            %   function showActivations(obj)
            %
            
            switch obj.net.BatchOpt.Workflow{1}(1:2)
                case '3D'
                    imgToPrev = squeeze(obj.imageActivation(:, :, obj.BatchOpt.patchZ{1}, round(obj.BatchOpt.filterId{1})));
                    minVal = min(imgToPrev(:));
                    maxVal = max(imgToPrev(:));
                    imgToPrev = mat2gray(imgToPrev);
                    imgToPrev = repmat(uint8(imgToPrev*255), [1 1 3]);
                case '2.'
                    %imgToPrev = squeeze(obj.imageActivation(:, :, ceil(size(obj.imageActivation,3)/2), round(obj.BatchOpt.filterId{1})));
                    imgToPrev = squeeze(obj.imageActivation(:, :, round(obj.BatchOpt.patchZ{1}), round(obj.BatchOpt.filterId{1})));
                    minVal = min(imgToPrev(:));
                    maxVal = max(imgToPrev(:));
                    imgToPrev = mat2gray(imgToPrev);
                    imgToPrev = repmat(uint8(imgToPrev*255), [1 1 3]);
                case '2D'
                    imgToPrev = obj.imageActivation(:, :, round(obj.BatchOpt.filterId{1}));
                    minVal = min(imgToPrev(:));
                    maxVal = max(imgToPrev(:));
                    imgToPrev = mat2gray(imgToPrev);
                    imgToPrev = repmat(uint8(imgToPrev*255), [1 1 3]);
            end
            obj.view.Figure.MinLabelValue.Text = num2str(minVal);
            obj.view.Figure.MaxLabelValue.Text = num2str(maxVal);
            newWidth = size(obj.view.Figure.ImageOriginal.ImageSource, 2);
            newHeight = size(obj.view.Figure.ImageOriginal.ImageSource, 1);
            imgToPrev = padarray(imgToPrev, [floor((newHeight-size(imgToPrev,1))/2) floor((newWidth-size(imgToPrev,2))/2)], 0, 'both');
            obj.view.Figure.ImageActivation.ImageSource = imgToPrev;
            try
                networkLayerId = obj.view.handles.NetworkLayerNumber.Value;
                if isprop(obj.net.net.Layers(networkLayerId), 'Weights')
                    selectedWeight = obj.net.net.Layers(networkLayerId).Weights(:,:,1,round(obj.BatchOpt.filterId{1}));
                    % Stretch values to [0, 255] range
                    minVal = min(selectedWeight(:));
                    maxVal = max(selectedWeight(:));
                    obj.view.handles.weightsMinValue.Text = sprintf('Min: %.3f', minVal);
                    obj.view.handles.weightsMaxValue.Text = sprintf('Max: %.3f', maxVal);
                    selectedWeight = (selectedWeight - minVal) / (maxVal - minVal) * 255;
                    selectedWeight = uint8(selectedWeight);
                    % resize to match the image container
                    selectedWeight = imresize(selectedWeight, [obj.view.handles.WeightsImage.Position(3) obj.view.handles.WeightsImage.Position(4)], 'nearest');
                    % convert to colors
                    selectedWeight = repmat(selectedWeight, [1,1,3]);
                    obj.view.handles.WeightsImage.ImageSource = selectedWeight;
                else
                    selectedWeight = zeros([obj.view.handles.WeightsImage.Position(3) obj.view.handles.WeightsImage.Position(4) 3], 'uint8');
                    obj.view.handles.WeightsImage.ImageSource = selectedWeight;
                    obj.view.handles.weightsMinValue.Text = 'Min: NaN';
                    obj.view.handles.weightsMaxValue.Text = 'Max: NaN';
                end
                parameterList = {'Bias', 'Offset', 'Scale', 'TrainedMean', 'TrainedVariance'};
                for paramId = 1:numel(parameterList)
                    propName = parameterList{paramId};
                    propValue = NaN;
                    if isprop(obj.net.net.Layers(networkLayerId), propName)
                        propValue = obj.net.net.Layers(networkLayerId).(propName)(1,1,round(obj.BatchOpt.filterId{1}));
                    end
                    fieldName = sprintf('weights%sValue', propName);
                    % rename properties for visualization
                    propName = strrep(propName, 'Trained', '');
                    propName = strrep(propName, 'Variance', 'Var');
                    obj.view.handles.(fieldName).Text = sprintf('%s: %.3f', propName, propValue);
                end
            catch err
                utils.dlgs.showErrorDialog(obj.view.gui, err, 'Error to show weights image');
                return;
            end
        end
        
        function changeImage(obj, event)
            % CHANGEIMAGE - callback for change image buttons.
            %
            % Syntax:
            %   function changeImage(obj, event)
            %
            % Input Arguments:
            %   - **event** - an event structure of appdesigner
            %
            
            filenameIndex = find(ismember(obj.view.Figure.ImageFilename.Items, obj.view.Figure.ImageFilename.Value)==1);
            switch event.Source.Tag
                case 'PreviousImageButton'
                    filenameIndex = max([filenameIndex - 1 1]);
                case 'NextImageButton'
                    filenameIndex = min([filenameIndex + 1 numel(obj.view.Figure.ImageFilename.Items)]);
            end
            obj.view.Figure.ImageFilename.Value = obj.view.Figure.ImageFilename.Items{filenameIndex};
            obj.BatchOpt.ImageFilename{1} = obj.view.Figure.ImageFilename.Value;
            obj.getNewImage();
        end
        
        function makeCollage(obj, silentMode)
            % MAKECOLLAGE - make collage image from activations.
            %
            % Syntax:
            %   function makeCollage(obj, silentMode)
            %
            % Input Arguments:
            %   - **silentMode** - logical ask or not for FigName and resize, see
            %     "generateSnapshots = false;" in the ShiftImage function
            %
            
            if nargin < 2; silentMode = []; end

            if ndims(obj.imageActivation) == 2
                noFilters = 1;
            else
                noFilters = size(obj.imageActivation, ndims(obj.imageActivation));
            end
            sz = size(obj.imageActivation);

            if isempty(silentMode)
                figId = find(ismember(obj.view.Figure.NetworkLayerName.Items, obj.view.Figure.NetworkLayerName.Value)==1); % fig id matches number of the layer

                dlgTitle = 'Collage options';
                header = sprintf('Select number of tiles for collage\nThe current layer has %d filters each %d x %d pixels', noFilters, sz(2), sz(1));
                prompts = {'Figure Id'; 'Number of X tiles:'; 'Number of Y tiles:'; 'Resize, width:'};
                defAns = {struct('Spinner', true, 'Value', figId, 'Limits', [1 Inf], 'Step', 1, 'Round', true);
                    struct('Spinner', true, 'Value', ceil(sqrt(noFilters)), 'Limits', [1 Inf], 'Step', 1, 'Round', true);
                    struct('Spinner', true, 'Value', ceil(sqrt(noFilters)), 'Limits', [1 Inf], 'Step', 1, 'Round', true);
                    struct('Spinner', true, 'Value', sz(2), 'Limits', [1 Inf], 'Step', 1, 'Round', true);
                    };
                options.headerLines = 2;
                options.WindowHeight = 220;
                options.LabelPosition = 'left';
                answer = utils.dlgs.inputUniversalDlg(obj.view.gui, header, prompts, defAns, dlgTitle, options);
                if isempty(answer); return; end
            
                figId = answer{1};
                noCols = answer{2};
                noRows = answer{3};
                width = answer{4};
            else
                figId = 101;
                width = size(obj.imageActivation, 1);
                noCols = ceil(sqrt(noFilters));
                noRows = ceil(sqrt(noFilters));
            end
            
            switch obj.net.BatchOpt.Workflow{1}(1)
                case '2'  % 2D or 2.5D
                    if ndims(obj.imageActivation) == 2 %#ok<ISMAT>
                        img = obj.imageActivation;
                    elseif ndims(obj.imageActivation) == 3
                        img = reshape(obj.imageActivation,[sz(1) sz(2) 1 sz(3)]);
                    elseif ndims(obj.imageActivation) == 4 % 2.5D
                        img = obj.imageActivation;
                    end
                    for i=1:size(img, 4)  % z
                        img(:,:,i) = mat2gray(img(:,:,i))*255;
                    end
                    I = imtile(imresize(uint8(img), [width, width]), 'GridSize', [noRows, noCols]);
                case '3' % 3D
                    img = squeeze(obj.imageActivation(:,:,obj.BatchOpt.patchZ{1},:));
                    img = permute(img, [1 2 4 3]);
                    I = imtile(imresize(uint8(mat2gray(img)*255), [width, width]), 'GridSize', [noRows, noCols]);
            end

            if isempty(silentMode)
                hFig = figure(figId);
                image(I);
                colormap(gray(256));
                ax = gca;
                ax.DataAspectRatio = [1 1 1];
                hFig.Name = obj.view.Figure.NetworkLayerName.Value;
            else
                % save to a file
                fn = sprintf('d:\\cnn_layers\\%.4d_%s.jpg', find(ismember(obj.BatchOpt.NetworkLayerName{2}, obj.BatchOpt.NetworkLayerName{1})), obj.BatchOpt.NetworkLayerName{1});
                imwrite(I, fn, 'jpg', 'Quality', 95);
            end
        end
    end
end
