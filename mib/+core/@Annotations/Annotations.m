classdef Annotations < matlab.mixin.Copyable
    % ANNOTATIONS - :class:`Annotations` class is responsible for keeping annotations of the model.
    %
    
	% Updates
	% 

    properties
        labelText
        % a cell array with labels
        labelValue
        % an array with values for labels
        labelPosition
        % a matrix with coordinates of the labels [pointIndex, z  x  y  t]
        defaultAnnotationText
        % default text for the annotations
        defaultAnnotationValue
        % default value for the annotations
    end
    
    methods
        function obj = Annotations()
            % ANNOTATIONS - Constructor for the :class:`Annotations` class.
            %
            % Syntax:
            %   function obj = Annotations()
            %
            % Constructor for the Annotations class. Create a new instance of
            % the class with default parameters
            %
            % Input Arguments:
            %
            % Output Arguments:
            %   obj - instance of the :class:`Annotations` class.
            %
            
            obj.clearContents();
        end
        
        function clearContents(obj)
            % CLEARCONTENTS - Set all elements of the class to default values.
            %
            % Syntax:
            %   function clearContents(obj)
            %
            % Input Arguments:
            %
            % Output Arguments:
            %
            % Usage:
            %   **Example 1**
            %
            %   .. code-block:: matlab
            %
            %
            %     obj.mibModel.I{obj.mibModel.id}.annotations.clearContents();
            %
            %   **Example 2**
            %
            %   .. code-block:: matlab
            %
            %
            %     clearContents(obj);% Call within the class
            %
            
            obj.labelText = {};   %  a cell array with labels
            obj.labelValue = [];    % an array with values for the labels
            obj.labelPosition = [];  % a matrix with coordinates of the labels [pointIndex, z, x, y  t]
            obj.defaultAnnotationText = 'Feature';
            obj.defaultAnnotationValue = 1;
        end
        
        function addLabels(obj, labels, positions, values)
            % ADDLABELS - Add labels with positions to the class.
            %
            % Syntax:
            %   function addLabels(obj, labels, positions, values)
            %
            % Input Arguments:
            %   - **labels** — a cell array with labels
            %   - **positions** — a matrix with coordinates of the labels [pointIndex, z  x  y  t]
            %   - **values** — an array of numbers with values for the labels [@em
            %     optional], default = 1
            %
            % Output Arguments:
            %
            % Usage:
            %   **Example 1**
            %
            %   .. code-block:: matlab
            %
            %
            %     labels{1} = 'my label 1';
            %     labels{2} = 'my label 2';
            %     positions(1,:) = [50, 75, 1, 3];% position 1: z=1, x=50, y=75, t=3;
            %     positions(2,:) = [50, 75, 2, 5];% position 1: z=2, x=50, y=75, t=5;
            %
            %   **Example 2**
            %
            %   .. code-block:: matlab
            %
            %
            %     obj.mibModel.I{obj.mibModel.id}.annotations.addLabel(labels, positions);% add a labels to the list, call from mibController
            %
            %   **Example 3**
            %
            %   .. code-block:: matlab
            %
            %
            %     addLabel(obj, labels, positions);% Call within the class;  add a labels to the list
            %
            
            if ~iscell(labels); labels = cellstr(labels); end
            if numel(labels) ~= size(positions, 1); error('Annotations.addLabels: error, number of labels and coordinates mismatch!'); end
            if nargin < 4
                values = zeros([numel(labels), 1]) + 1;
            end
            
            % trim the blanks from the strings
            for i=1:numel(labels)
                labels{i} = strtrim(labels{i});
            end
            
            % transpose if needed
            if size(labels,1) < size(labels,2)
                labels = labels';
            end
            
            if size(values,1) < size(values,2)
                values = values';
            end
            obj.labelText = [obj.labelText; labels];
            obj.labelValue = [obj.labelValue; values];
            
            if size(positions,2) == 3   % fix for old position lists with z,x,y coordinates only
                positions = [positions ones([size(positions,1),1])];
            end
            obj.labelPosition = [obj.labelPosition; positions];
        end
        
        function crop(obj, cropF)
            % CROP - Recalculation of annotation positions during image crop.
            %
            % Syntax:
            %   function crop(obj, cropF)
            %
            % Input Arguments:
            %   - **cropF** — a vector [x1, y1, dx, dy, z1, dz, t1, dt] with
            %     parameters of the crop. **Note!** The units are pixels! Parameters t1 and
            %     dt are optional!
            %
            % Usage:
            %   **Example 1**
            %
            %   .. code-block:: matlab
            %
            %
            %     cropF = [100 512 200 512 5 20 7 15];% define parameters of the crop
            %
            %   **Example 2**
            %
            %   .. code-block:: matlab
            %
            %
            %     cropF2 = [100 512 NaN NaN 5 NaN 7 NaN];% alternative definition of parameters for the crop
            %
            %   **Example 3**
            %
            %   .. code-block:: matlab
            %
            %
            %     obj.mibModel.I{obj.mibModel.id}.annotations.crop(cropF);% adjust coordinates due to cropping
            %
            %
            %   **Attention:** parameters dx, dy, dz, dt are not used, so they can be replaced with NaNs
            %

            if obj.getLabelsNumber > 0
                obj.labelPosition(:,1) = obj.labelPosition(:,1) - cropF(5) + 1;
                obj.labelPosition(:,2) = obj.labelPosition(:,2) - cropF(1) + 1;
                obj.labelPosition(:,3) = obj.labelPosition(:,3) - cropF(2) + 1;
                if numel(cropF) > 6
                    obj.labelPosition(:,4) = obj.labelPosition(:,4) - cropF(7) + 1;
                end
            end
            
        end
        
        
        function [labelsList, labelValues, labelPositions, indices] = getCurrentSliceLabels(obj)
            % GETCURRENTSLICELABELS - [labelsList, labelValues, labelPositions, indices] = getCurrentSliceLabels(obj).
            %
            % Syntax:
            %   function [labelsList, labelValues, labelPositions, indices] = getCurrentSliceLabels(obj)
            %
            % Get list of labels shown at the current slice
            %
            %
            % **Note:** replaced with mibImage.getSliceLabels
            %
            % Input Arguments:
            %
            % Output Arguments:
            %   - **labelsList** — a cell array with labels
            %   - **labelPositions** — a matrix with coordinates of the labels [labelIndex, z x y t]
            %   - **indices** — indices of the labels
            %
            % Usage:
            %   **Example 1**
            %
            %   .. code-block:: matlab
            %
            %
            %     [labelsList, labelPositions, indices] = LabelsInstance.getCurrentSliceLabels();% get all labels from the currently shown slice
            %
            %   **Example 2**
            %
            %   .. code-block:: matlab
            %
            %
            %     [labelsList, labelPositions, indices] = getCurrentSliceLabels(obj);% Call within the class;  get all labels from the currently shown slice
            %
            
            error('replaced with mibImage.getSliceLabels(), use without parameters!');
            
%             rangeT = [handles.Img{handles.Id}.I.slices{5}(1) handles.Img{handles.Id}.I.slices{5}(2)];
%             
%             if handles.Img{handles.Id}.I.orientation == 4   % xy
%                 [labelsList, labelPositions, indices] = obj.getLabels(handles.Img{handles.Id}.I.slices{4}(1), NaN, NaN, rangeT);
%             elseif handles.Img{handles.Id}.I.orientation == 1   % zx
%                 [labelsList, labelPositions, indices] = obj.getLabels(NaN, NaN, handles.Img{handles.Id}.I.slices{1}(1), rangeT);
%             elseif handles.Img{handles.Id}.I.orientation == 2   % zy
%                 [labelsList, labelPositions, indices] = obj.getLabels(NaN, handles.Img{handles.Id}.I.slices{2}(1), NaN, rangeT);
%             end
        end
        
        function [labelsList, labelValues, labelPositions, indices] = getLabels(obj, rangeZ, rangeX, rangeY, rangeT)
            % GETLABELS - Get list of labels.
            %
            % Syntax:
            %   function [labelsList, labelValues, labelPositions, indices] = getLabels(obj, rangeZ, rangeX, rangeY, rangeT)
            %
            % Input Arguments:
            %   - **rangeZ** — *(optional)* define range of labels to retrieve for
            %     Z [minZ maxZ], can be **NaN**
            %   - **rangeX** — *(optional)* define range of labels to retrieve for X [minX maxX], can be **NaN**
            %   - **rangeY** — *(optional)* define range of labels to retrieve for Y [minY maxY], can be **NaN**
            %   - **rangeT** — *(optional)* define range of labels to retrieve for T [minT maxT], can be **NaN**
            %
            % Output Arguments:
            %   - **labelsList** — a cell array with labels
            %   - **labelValues** — an array of numbers with values
            %   - **labelPositions** — a matrix with coordinates of the labels [labelIndex, z x y t]
            %   - **indices** — indices of the labels
            %
            % Usage:
            %   **Example 1**
            %
            %   .. code-block:: matlab
            %
            %
            %     [labelsList, labelValues, labelPositions, indices] = obj.mibModel.I{obj.mibModel.id}.annotations.getLabels();% get all labels
            %
            %   **Example 2**
            %
            %   .. code-block:: matlab
            %
            %
            %     [labelsList, labelValues, labelPositions, indices] = obj.mibModel.I{obj.mibModel.id}.annotations.getLabels(50);% get all labels from slice 50
            %
            %   **Example 3**
            %
            %   .. code-block:: matlab
            %
            %
            %     [labelsList, labelValues, labelPositions, indices] = obj.mibModel.I{obj.mibModel.id}.annotations.getLabels(obj, 50);% Call within the class;  get all labels from slice 50
            %
            
            if nargin < 5; rangeT = NaN; end
            if nargin < 4; rangeY = NaN; end
            if nargin < 3; rangeX = NaN; end
            if nargin < 2; rangeZ = NaN; end
            % fetch Z
            labelsList = obj.labelText;
            labelValues = obj.labelValue;
            labelPositions = obj.labelPosition;
            indices = 1:numel(labelsList);
            
            if isempty(labelsList); return; end

            if ~isnan(rangeZ(1))   % sort with Z
                if numel(rangeZ) == 1
                    selIndices = find(round(labelPositions(:,1))==rangeZ);
                else
                    selIndices = find(round(labelPositions(:,1)) >= rangeZ(1) & round(labelPositions(:,1)) <= rangeZ(2));
                end
                labelsList = labelsList(selIndices);
                labelValues = labelValues(selIndices);
                labelPositions = labelPositions(selIndices,:);
                indices = indices(selIndices);  
            end
            if ~isnan(rangeX(1))   % sort with X
                if numel(rangeX) == 1
                    selIndices = find(round(labelPositions(:,2))==rangeX);
                else
                    selIndices = find(round(labelPositions(:,2)) >= rangeX(1) & round(labelPositions(:,2)) <= rangeX(2));
                end
                labelsList = labelsList(selIndices);
                labelValues = labelValues(selIndices);
                labelPositions = labelPositions(selIndices,:);
                indices = indices(selIndices);  
            end
            if ~isnan(rangeY(1))   % sort with Y
                if numel(rangeY) == 1
                    selIndices = find(round(labelPositions(:,3))==rangeY);
                else
                    selIndices = find(round(labelPositions(:,3)) >= rangeY(1) & round(labelPositions(:,3)) <= rangeY(2));
                end
                labelsList = labelsList(selIndices);
                labelValues = labelValues(selIndices);
                labelPositions = labelPositions(selIndices,:);
                indices = indices(selIndices);  
            end
            if ~isnan(rangeT(1))   % sort with Y
                if numel(rangeT) == 1
                    selIndices = find(round(labelPositions(:, 4))==rangeT);
                else
                    selIndices = find(round(labelPositions(:,4)) >= rangeT(1) & round(labelPositions(:,4)) <= rangeT(2));
                end
                labelsList = labelsList(selIndices);
                labelValues = labelValues(selIndices);
                labelPositions = labelPositions(selIndices,:);
                indices = indices(selIndices);  
            end
            if size(indices, 1) < size(indices, 2)
                indices = indices'; 
            end
        end
        
        function [labels, values, positions, indices] = getLabelsById(obj, labelId)
            % GETLABELSBYID - Get labels using labelId.
            %
            % Syntax:
            %   function [labels, values, positions, indices] = getLabelsById(obj, labelId)
            %
            % Input Arguments:
            %   - **labelId** — a variable or a vector with a label to retrieve:
            %
            %     - **a single number or a column of numbers** — get label that has index equal to the number
            %     - **a matrix** — get all labels that have coordinates specified in the matrix ``[labelIndex, z x y t]``
            %     - **a cell array** — get all labels that have text specified in the cell array
            %
            % Output Arguments:
            %   - **labels** — - cell array with labels of annotations
            %   - **values** — - array with values of annotations
            %   - **positions** — - a matrix with coordinates (index; z,x,y,t)
            %   - **indices** — - array with indices of annotations
            %
            % Usage:
            %   **Example 1**
            %
            %   .. code-block:: matlab
            %
            %
            %     labelIds = [5, 7, 10]';
            %     [labels, values, positions, id] = obj.mibModel.I{obj.mibModel.id}.annotations.getLabelsById(labelIds);% call from mibController, get labels with indices 5, 7, 10
            %
            
            if nargin < 2     % check parameters
                error('Annotations.getLabelsById: not enough arguments!');
            end
            labels = [];
            values = [];
            positions = [];
            
            if ischar(labelId); labelId = cellstr(labelId); end    
            
            if iscell(labelId)   % get specified with labelText label
                indices = strcmp(labelId, obj.labelText);
                labels = obj.labelText(indices);
                values = obj.labelValue(indices);
                positions = obj.labelPosition(indices,:);
                return;
            end
            
            if size(labelId, 2) == 1 % a get number update specified index
                labels = obj.labelText(labelId);
                values = obj.labelValue(labelId);
                positions = obj.labelPosition(labelId,:);
                indices = labelId;
                return;
            else    % find and update the specified point
                indices = ismember(obj.labelPosition, labelId, 'rows');
                if sum(indices) ~= 1; return; end % no matches were found
                
                labels = obj.labelText(indices);
                values = obj.labelValue(indices);
                positions = obj.labelPosition(indices,:);
                return;
            end
        end
        
        function labelsNumber = getLabelsNumber(obj)
            % GETLABELSNUMBER - Get total number of labels.
            %
            % Syntax:
            %   function labelsNumber = getLabelsNumber(obj)
            %
            % Input Arguments:
            %
            % Output Arguments:
            %   - **labelsNumber** — a number of labels
            %
            % Usage:
            %   **Example 1**
            %
            %   .. code-block:: matlab
            %
            %
            %     labelsNumber = obj.mibModel.I{obj.mibModel.id}.annotations.getLabelsNumber();% get number of labels
            %
            %   **Example 2**
            %
            %   .. code-block:: matlab
            %
            %
            %     labelsNumber = getLabelsNumber(obj);% Call within the class;  get number of labels
            %
            labelsNumber = numel(obj.labelText);
        end
        
        function [labelsList, labelValues, labelPositions, indices] = getSliceLabels(obj, handles, sliceNumber, timePoint)
            % GETSLICELABELS - [labelsList, labelValues, labelPositions, indices] = getSliceLabels(obj, handles, sliceNumber, timePoint).
            %
            % Syntax:
            %   function [labelsList, labelValues, labelPositions, indices] = getSliceLabels(obj, handles, sliceNumber, timePoint)
            %
            % Get list of labels shown at the specified slice
            %
            % Input Arguments:
            %   - **handles** — a handles structure of im_browser
            %   - **sliceNumber** — *(optional)*, a slice number to get labels
            %   - **timePoint** — *(optional)*, a time point to get the labels
            %
            % Output Arguments:
            %   - **labelsList** — a cell array with labels
            %   - **labelPositions** — a matrix with coordinates of the labels [labelIndex, z x y]
            %   - **indices** — indices of the labels
            %
            % Usage:
            %   **Example 1**
            %
            %   .. code-block:: matlab
            %
            %
            %     [labelsList, labelPositions, indices] = obj.mibModel.I{obj.mibModel.id}.annotations.getSliceLabels(handles, 15);% get all labels from the slice 15
            %
            %   **Example 2**
            %
            %   .. code-block:: matlab
            %
            %
            %     [labelsList, labelPositions, indices] = getSliceLabels(obj, handles);% Call within the class;  get all labels from the currently shown slice
            %
            error('moved to mibImage.getSliceLabels');
            
            if nargin < 4
                timePnt = handles.Img{handles.Id}.I.slices{5}(1);
            end
            if nargin < 3
                [labelsList, labelValues, labelPositions, indices] = getCurrentSliceLabels(obj, handles);
                return;
            end
            
            if handles.Img{handles.Id}.I.orientation == 4   % xy
                [labelsList, labelValues, labelPositions, indices] = obj.getLabels(sliceNumber, NaN, NaN, timePnt);
            elseif handles.Img{handles.Id}.I.orientation == 1   % zx
                [labelsList, labelValues, labelPositions, indices] = obj.getLabels(NaN, NaN, sliceNumber, timePnt);
            elseif handles.Img{handles.Id}.I.orientation == 2   % zy
                [labelsList, labelValues, labelPositions, indices] = obj.getLabels(NaN, sliceNumber, NaN, timePnt);
            end
        end
        
        function [minZ, labelIds] = getMinValueZ(obj)
            % GETMINVALUEZ - Find and return the minimum Z value for all annotations, as well as their indices.
            %
            % Input Arguments:
            %
            % Output Arguments:
            %   - **minZ** — value of min Z for all annotations
            %   - **labelIds** — indices of those annotations
            %

            minZ = min(obj.labelPosition(:,1));
            labelIds = find(obj.labelPosition(:,1) == minZ); 
        end

        function [maxZ, labelIds] = getMaxValueZ(obj)
            % GETMAXVALUEZ - Find and return the maximum Z value for all annotations, as well as their indices.
            %
            % Input Arguments:
            %
            % Output Arguments:
            %   - **maxZ** — value of max Z for all annotations
            %   - **labelIds** — indices of those annotations
            %
            
            maxZ = max(obj.labelPosition(:,1));
            labelIds = find(obj.labelPosition(:,1) == maxZ); 
        
        end

        function removeLabels(obj, labels)
            % REMOVELABELS - removeLabels(obj, labels).
            %
            % Syntax:
            %   function removeLabels(obj, labels)
            %
            % Remove specified labels
            %
            % Input Arguments:
            %   - **labels** — *(optional)* a variable or a vector with a label to remove:
            %
            %     - omitted — remove all labels
            %     - **a single number or a column of numbers** — remove label that has index equal to the number
            %     - **a matrix** — remove all labels that have coordinates specified in the matrix ``[labelIndex, z x y t]``
            %     - **a cell array** — remove all labels that have text specified in the cell array
            %
            % Usage:
            %   **Example 1**
            %
            %   .. code-block:: matlab
            %
            %
            %     labels{1} = 'my label 1';
            %
            %   **Example 2**
            %
            %   .. code-block:: matlab
            %
            %
            %     obj.mibModel.I{obj.mibModel.id}.annotations.removeLabels(labels);% remove annotations that match labels
            %
            %   **Example 3**
            %
            %   .. code-block:: matlab
            %
            %
            %     removeLabels(obj, labels);% Call within the class; remove annotations that match labels
            %
            
            if isempty(obj.labelPosition); return; end  % nothing to remove
            
            if nargin < 2      % remove all labels
                choice = utils.dlgs.inputQuestDlg([], 'Delete all annotations from the model?', 'Remove annotations', 'Delete', 'Cancel','Cancel');
                if strcmp(choice, 'Cancel'); return; end
                obj.clearContents();
                return;
            end
            
            if iscell(labels)   % remove specified label
                for i=1:numel(labels)
                    indices = strcmp(labels(i),obj.labelText);
                    obj.labelText(indices) = [];
                    obj.labelValue(indices) = [];
                    obj.labelPosition(indices,:) = [];
                end
                return;
            end
            
            if size(labels, 2) == 1 % a single number or a column, remove specified indices
                    obj.labelText(labels) = [];
                    obj.labelValue(labels) = [];
                    obj.labelPosition(labels,:) = [];
                return;
            else    % find and remove specified points
                for i = 1:size(labels,1)
                    indices = ismember(obj.labelPosition, labels(i,:), 'rows');
                    obj.labelText(indices) = [];
                    obj.labelValue(indices) = [];
                    obj.labelPosition(indices,:) = [];
                end
                return;
            end
        end
        
        function result = renameLabels(obj, oldLabel, newLabelText)
            % RENAMELABELS - Rename specified labels with new text.
            %
            % Syntax:
            %   function result = renameLabels(obj, oldLabel, newLabelText)
            %
            % Input Arguments:
            %   - **oldLabel** — a variable or a vector with an old label to be renamed:
            %
            %     - **a single number or a column of numbers** — rename the label with this index
            %     - **a matrix** — rename all labels that have coordinates specified in the matrix ``[labelIndex, z x y t]``
            %     - **a cell array** — rename all labels that have text specified in the cell array
            %
            %   - **newLabelText** — a cell or a char string with new text for the label
            %
            % Output Arguments:
            %   - **result** — result of the function work: ``1`` = success, ``0`` = failure
            %
            % Usage:
            %   **Example 1**
            %
            %   .. code-block:: matlab
            %
            %
            %     oldLabelId = [5, 7, 10]';
            %     label{1} = 'my label 1';
            %
            %   **Example 2**
            %
            %   .. code-block:: matlab
            %
            %
            %     obj.mibModel.I{obj.mibModel.id}.annotations.renameLabels(oldLabelId, label);% call from mibController, rename labels with indices 5, 7, 10
            %
            
            
            result = 0;
            if nargin < 3     % check parameters
                error('Annotations.updateLabels: not enough arguments!');
            end
            
            if ischar(oldLabel); oldLabel = cellstr(oldLabel); end    
            if ischar(newLabelText); newLabelText = cellstr(newLabelText); end    
            
            if iscell(oldLabel)   % rename specified with oldLabel label
                indices = strcmp(oldLabel, obj.labelText);
                obj.labelText(indices) = newLabelText;
                result = 1;
                return;
            end
            
            if size(oldLabel, 2) == 1 % a single number update specified index
                obj.labelText(oldLabel) = newLabelText;
                result = 1;
                return;
            else    % find and update the specified point
                indices = ismember(obj.labelPosition, oldLabel, 'rows');
                if sum(indices) ~= 1; return; end % no matches were found
                obj.labelText(indices) = newLabelText;
                result = 1;
                return;
            end
        end
        
        function replaceLabels(obj, labels, positions, values)
            % REPLACELABELS - replaceLabels(obj, labels, positions, values).
            %
            % Syntax:
            %   function replaceLabels(obj, labels, positions, values)
            %
            % Replace existing labels with a new list of labels and their
            % values
            %
            % Input Arguments:
            %   - **labels** — a cell array with labels
            %   - **positions** — a matrix with coordinates of the labels [pointIndex, z  x  y  t]
            %   - **values** — an array of numbers with values of the labels, *(optional)* default = 1
            %
            % Usage:
            %   **Example 1**
            %
            %   .. code-block:: matlab
            %
            %
            %     labels{1} = 'my label 1';
            %     labels{2} = 'my label 2';
            %     positions(1,:) = [1, 50, 75, 5];% position 1: x=50, y=75, z=1,t=5;
            %     positions(2,:) = [2, 50, 75, 6];% position 1: x=50, y=75, z=2, t=6;
            %
            %   **Example 2**
            %
            %   .. code-block:: matlab
            %
            %
            %     obj.mibModel.I{obj.mibModel.id}.annotations.replaceLabels(labels, positions);% replace labels with a new list
            %
            %   **Example 3**
            %
            %   .. code-block:: matlab
            %
            %
            %     replaceLabels(obj, labels, positions);% Call within the class; replace labels with a new list
            %
            
            if ~iscell(labels); labels = cellstr(labels); end
            if numel(labels) ~= size(positions, 1); error('Annotations.replaceLabels: error, number of labels and coordinates mismatch!'); end
            
            if nargin < 4; values = zeros([numel(labels), 1]) + 1; end
            
            if size(labels,1) < size(labels,2)  % transpose labels to a column
                labels = labels';
            end
            
            if size(values,1) < size(values,2)  % transpose labels to a column
                values = values';
            end
            
            obj.labelText = labels;
            obj.labelValue = values;
            obj.labelPosition = positions;
        end
        
        function result = updateLabels(obj, oldLabel, newLabelText, newLabelPos, newLabelValues)
            % UPDATELABELS - Update specified labels with newLabels.
            %
            % Syntax:
            %   function result = updateLabels(obj, oldLabel, newLabelText, newLabelPos, newLabelValues)
            %
            % Input Arguments:
            %   - **oldLabel** — a variable or a vector with an old label to be updated:
            %
            %     - **a single number or a column of numbers** — update the label with this index
            %     - **a matrix** — update all labels that have coordinates specified in the matrix ``[labelIndex, z x y t]``
            %     - **a cell array** — update all labels that have text specified in the cell array
            %
            %   - **newLabelText** — a cell or a char string with new text for the label
            %   - **newLabelPos** — coordinates of the new label ``[z, x, y]``
            %   - **newLabelValues** — *(optional)* an array of numbers with values of the labels, default = ``1``
            %
            % Output Arguments:
            %   - **result** — result of the function work: **1** - good, **0** - bad
            %
            % Usage:
            %   **Example 1**
            %
            %   .. code-block:: matlab
            %
            %
            %     label{1} = 'my label 1';
            %     newPosition(1,:) = [50, 75, 1, 5];% position 1: x=50, y=75; z=1, t=5
            %
            %   **Example 2**
            %
            %   .. code-block:: matlab
            %
            %
            %     obj.mibModel.I{obj.mibModel.id}.annotations.updateLabels(label, label, newPosition);% call from mibController, update coordinates of a label that has "my label 1" text
            %
            
            
            result = 0;
            if nargin < 3     % check parameters
                error('Annotations.updateLabels: not enough arguments!');
            end
            
            if ischar(oldLabel); oldLabel = cellstr(oldLabel); end    
            if ischar(newLabelText); newLabelText = cellstr(newLabelText); end    
            
            if nargin < 5; newLabelValues = zeros([numel(newLabelText), 1]) + 1; end
            
            if iscell(oldLabel)   % update specified with labelText label
                    indices = strcmp(oldLabel,obj.labelText);
                    obj.labelText(indices) = newLabelText;
                    obj.labelValue(indices) = newLabelValues;
                    obj.labelPosition(indices,:) = newLabelPos;
                    result = 1;
                return;
            end
            
            if size(oldLabel, 2) == 1 % a single number update specified index
                    obj.labelText(oldLabel) = newLabelText;
                    obj.labelPosition(oldLabel,:) = newLabelPos;
                    obj.labelValue(oldLabel) = newLabelValues;
                    result = 1;
                return;
            else    % find and update the specified point
                indices = ismember(obj.labelPosition, oldLabel, 'rows');
                if sum(indices) ~= 1; return; end % no matches were found
                obj.labelText(indices) = newLabelText;
                obj.labelValue(indices) = newLabelValues;
                obj.labelPosition(indices,:) = repmat(newLabelPos, [numel(sum(indices)), 1] );
                result = 1;
                return;
            end
        end
        
        function saveToFile(obj, filename, options)
            % SAVETOFILE - save Annotations to a file.
            %
            % Syntax:
            %   function saveToFile(obj, filename, options)
            %
            % Input Arguments:
            %   - **filename** — full path to output file
            %   - **options** — *(optional)* struct with saving parameters:
            %
            %     - ``.format`` — (char) output file format:
            %
            %       - ``'ann'`` — MIB annotation format
            %       - ``'landmarksAscii'`` — Amira landmarks in ASCII format
            %       - ``'landmarksBin'`` — Amira landmarks as binaries
            %       - ``'psi'`` — PSI format ASCII
            %       - ``'xls'`` — Microsoft Excel format
            %
            %     - ``.showWaitbar`` — *(optional)* logical; ``1`` = show, ``0`` = hide; requires ``.mibGUI``
            %     - ``.mibGUI`` — *(optional)* handle to the main app UIFigure, required when ``showWaitbar=1``
            %     - ``.outputDir`` — *(optional)* output directory
            %     - ``.convertToUnits`` — *(optional)* logical; convert pixel coordinates to physical units; requires ``.boundingBox`` and ``.pixSize``
            %     - ``.boundingBox`` — matrix ``[x1 width y1 height z1 depth]``, required for unit conversion
            %     - ``.pixSize`` — MIB struct with pixel sizes
            %     - ``.labelText`` — *(optional)* override ``obj.labelText`` with provided cell array
            %     - ``.labelPosition`` — *(optional)* override ``obj.labelPosition`` with provided matrix
            %     - ``.labelValue`` — *(optional)* override ``obj.labelValue`` with provided array
            %     - ``.sliceNames`` — *(optional)* cell array with filenames, used for Excel and CSV export
            %     - ``.addLabelToFilename`` — *(optional)* logical; append annotation label to filename; default ``false``
            %

            if nargin < 3; options = struct(); end
            if nargin < 2; filename = []; end
            if ~isfield(options, 'showWaitbar'); options.showWaitbar = true; end
            if ~isfield(options, 'mibGUI'); options.mibGUI = []; end
            if ~isfield(options, 'outputDir'); options.outputDir = ''; end
            if ~isfield(options, 'convertToUnits'); options.convertToUnits = 0; end
            if ~isfield(options, 'addLabelToFilename'); options.addLabelToFilename = false; end
            if options.showWaitbar && isempty(options.mibGUI); options.showWaitbar = 0; end
            
            if options.convertToUnits   % check for required bounding box and pixSize 
                if ~isfield(options, 'boundingBox') || ~isfield(options, 'pixSize') 
                    errordlg(sprintf('!!! Error !!!\n\nConversion to units requires additional parameters: boundingBox and pixSize structure'), 'Not enough parameters!');
                    return;
                end
            end
            
            % obtain filename if it is not provided
            if isempty(filename)
                Filters = {'*.ann',  'Matlab format (*.ann)';...
                           '*.csv',   'Comma-separated value (*.csv)';...
                           '*.landmarkAscii',   'Amira landmarks ASCII (*.landmarkAscii)';...
                           '*.landmarkBin',   'Amira landmarks BINARY(*.landmarkBin)';...
                           '*.psi',   'PSI format ASCII(*.psi)';...
                           '*.xls',   'Excel format (*.xls)'; };
                
                [filename, path, FilterIndex] = uiputfile(Filters, 'Save annotations...', options.outputDir); %...
                if isequal(filename,0); return; end % check for cancel
                
                filename = fullfile(path, filename);
                
                switch Filters{FilterIndex, 2}
                    case 'Matlab format (*.ann)'
                        options.format = 'ann';
                    case 'Comma-separated value (*.csv)'
                        options.format = 'csv';
                    case 'Amira landmarks ASCII (*.landmarkAscii)'
                        options.format = 'landmarkAscii';
                    case 'Amira landmarks BINARY(*.landmarkBin)'
                        options.format = 'landmarkBin';
                    case 'PSI format ASCII(*.psi)'
                         options.format = 'psi';
                    case 'Excel format (*.xls)'
                        options.format = 'xls';
                end
            end
            if options.showWaitbar; wb = uiprogressdlg(options.mibGUI, 'Value', 0, ...
                    'Message', 'Please wait...', 'Title', 'Saving Annotations', 'Indeterminate', 'off'); 
            end
            % obtain format if it is not provided
            if isempty(options.format)
                [path, fn, ext] = fileparts(filename);
                options.format = ext(2:end);
            end
            
            if ~isfield(options, 'labelText')
                labelText = obj.labelText;  %#ok<*PROPLC>
            else
                labelText = options.labelText;
            end
            if ~isfield(options, 'labelPosition')
                labelPosition = obj.labelPosition; 
            else
                labelPosition = options.labelPosition;
            end
            if ~isfield(options, 'labelValue')
                labelValue = obj.labelValue;
            else
                labelValue = options.labelValue;
            end
            
            % add label of the first annotation to filename
            if options.addLabelToFilename
                [path, fn, ext] = fileparts(filename);
                fn = [fn '_' labelText{1}];
                filename = fullfile(path, [fn ext]);
            end
            
            switch options.format
                case 'ann'
                    save(filename, 'labelText', 'labelValue', 'labelPosition', '-mat', '-v7.3');
                case 'csv'
                    LabelText = labelText;
                    LabelValue = labelValue;
                    LabelPositionXpx = labelPosition(:,2);
                    LabelPositionYpx = labelPosition(:,3);
                    LabelPositionZpx = labelPosition(:,1);
                    LabelPositionTpx = labelPosition(:,4);

                    if isfield(options, 'sliceNames')
                        Filename = options.sliceNames;
                    else
                        Filename = cell(size(LabelPositionTpx));
                    end

                    % convert to coordinates to physical units
                    if isfield(options, 'boundingBox')
                        bb = options.boundingBox;
                        LabelPositionXunits = labelPosition(:,2)*options.pixSize.x + bb(1) - options.pixSize.x/2;
                        LabelPositionYunits = labelPosition(:,3)*options.pixSize.y + bb(3) - options.pixSize.y/2;
                        LabelPositionZunits = labelPosition(:,1)*options.pixSize.z + bb(5) - options.pixSize.z;
                        LabelPositionTunits = labelPosition(:,4);
                        T = table(Filename, ...
                            LabelText, LabelValue, LabelPositionXpx, LabelPositionYpx, LabelPositionZpx, LabelPositionTpx,...
                            LabelPositionXunits, LabelPositionYunits, LabelPositionZunits, LabelPositionTunits);
                    else
                        T = table(Filename, ...
                            LabelText, LabelValue, LabelPositionXpx, LabelPositionYpx, LabelPositionZpx, LabelPositionTpx);
                    end
                    % save results as CSV
                    writetable(T, filename);
                case 'xls'
                    warning('off', 'MATLAB:xlswrite:AddSheet');
                    % Sheet 1
                    s = {'Annotations export'};
                    s(3,1) = {'Annotation'};
                    s(4,1) = {'Filename'};
                    s(4,2) = {'Text'};
                    s(4,3) = {'Value'};
                    s(3,5) = {'Coordinates, pixels'};
                    s(4,4) = {'Z'};
                    s(4,5) = {'X'};
                    s(4,6) = {'Y'};
                    s(4,7) = {'T'};
                    
                    noAnn = numel(labelText);
                    rowId = 5;
                    if isfield(options, 'sliceNames')
                        s(rowId:rowId+noAnn-1, 1) = options.sliceNames;
                    end
                    s(rowId:rowId+noAnn-1, 2) = labelText;
                    s(rowId:rowId+noAnn-1, 3) = num2cell(labelValue);
                    s(rowId:rowId+noAnn-1, 4:7) = num2cell(labelPosition);
                    
                    % convert to coordinates to physical units
                    if isfield(options, 'boundingBox')
                        s(3,9) = {sprintf('Coordinates, %s', options.pixSize.units)};
                        s(4,9) = {'Z'};
                        s(4,10) = {'X'};
                        s(4,11) = {'Y'};
                        s(4,12) = {'T'};
                        bb = options.boundingBox; 
                        labelPositionsOut(:, 1) = labelPosition(:, 1)*options.pixSize.z + bb(5) - options.pixSize.z;
                        labelPositionsOut(:, 2) = labelPosition(:, 2)*options.pixSize.x + bb(1) - options.pixSize.x/2;
                        labelPositionsOut(:, 3) = labelPosition(:, 3)*options.pixSize.y + bb(3) - options.pixSize.y/2;
                        s(rowId:rowId+noAnn-1, 9:11) = num2cell(labelPositionsOut);
                        s(rowId:rowId+noAnn-1, 12) = num2cell(labelPosition(:, 4));
                    end
                    if options.showWaitbar; wb.Value = 0.3; end
                    
                    xlswrite2(filename, s, 'Sheet1', 'A1');
                    if options.showWaitbar; wb.Value = 1; end
                case 'psi'
                    %recalcCoordinates = questdlg(sprintf('Recalculate annotations with respect to the current bounding box or save as they are?'),...
                    %    'Recalculate coordinates', 'Recalculate', 'Save as they are', 'Recalculate');
                    
                    % rearrange to [x, y, z] format from [z, x, y]
                    labelPositionsOut = [labelPosition(:,2) labelPosition(:,3) labelPosition(:,1)];
                    
                    if options.convertToUnits      % recalculate annotations to the real world coordinates
                        bb = options.boundingBox; 
                        labelPositionsOut(:, 1) = labelPositionsOut(:, 1)*options.pixSize.x + bb(1) - options.pixSize.x/2;
                        labelPositionsOut(:, 2) = labelPositionsOut(:, 2)*options.pixSize.y + bb(3) - options.pixSize.y/2;
                        labelPositionsOut(:, 3) = labelPositionsOut(:, 3)*options.pixSize.z + bb(5) - options.pixSize.z;
                    end
                    options.format = 'ascii';
                    options.overwrite = 1;
                    if options.showWaitbar; wb.Value = 0.3; end
                    io.AmiraMesh.points2psi(filename, labelPositionsOut, labelText, labelValue, options);
                    if options.showWaitbar; wb.Value = 1; end
                case {'landmarkBin', 'landmarkAscii'}
                    % rearrange to [x, y, z] format from [z, x, y]
                    labelPositionsOut = [labelPosition(:,2) labelPosition(:,3) labelPosition(:,1)];
                    
                    if options.convertToUnits      % recalculate annotations to the real world coordinates
                        bb = options.boundingBox; 
                        labelPositionsOut(:, 1) = labelPositionsOut(:, 1)*options.pixSize.x + bb(1) - options.pixSize.x/2;
                        labelPositionsOut(:, 2) = labelPositionsOut(:, 2)*options.pixSize.y + bb(3) - options.pixSize.y/2;
                        labelPositionsOut(:, 3) = labelPositionsOut(:, 3)*options.pixSize.z + bb(5) - options.pixSize.z;
                    end
                    if options.showWaitbar; wb.Value = 0.3; end
                    if strcmp(options.format, 'landmarkAscii')
                        options.format = 'ascii';
                    else
                        options.format = 'binary';
                    end
                    options.overwrite = 1;
                    io.AmiraMesh.points2amiraLandmarks(filename, labelPositionsOut, options);
                    if options.showWaitbar; wb.Value = 1; end
            end
            fprintf('Saving annotations to %s: done!\n', filename);
            if options.showWaitbar; delete(wb); end
        end
        
        function sortLabels(obj, sortBy, direction)
            % SORTLABELS - Resort the list of annotation labels.
            %
            % Syntax:
            %   function sortLabels(obj, sortBy, direction)
            %
            % Input Arguments:
            %   - **sortBy** — a string with the field to be used for sorting
            %   - 'name', *default* sort by the label name
            %   - 'value', sort by value
            %   - 'x', sort by the X coordinate
            %   - 'y', sort by the Y coordinate
            %   - 'z', sort by the Z coordinate
            %   - 't', sort by the T coordinate
            %   - **direction** — a string with sorting direction
            %   - 'ascend', *default* sort in the ascending order
            %   - 'descend', sort in the descending order
            %
            % Output Arguments:
            %
            % Usage:
            %   **Example 1**
            %
            %   .. code-block:: matlab
            %
            %
            %     obj.mibModel.I{obj.mibModel.id}.annotations.sortLabels();% call from mibController, sort the list by the label name
            %
            %   **Example 2**
            %
            %   .. code-block:: matlab
            %
            %
            %     obj.mibModel.I{obj.mibModel.id}.annotations.sortLabels('name', 'descend');% call from mibController, sort the list by the label name using descending order
            %
            
            if nargin < 3; direction = 'ascend'; end
            if nargin < 2; sortBy = 'name'; end
            
            switch sortBy
                case 'name'     % re-sort by label name
                    [~, indices] = sort(obj.labelText);
                case 'value'    % re-sort by label value
                    [~, indices] = sort(obj.labelValue);
                case 'x'        % re-sort by x coordinate
                    [~, indices] = sort(obj.labelPosition(:, 2), direction);
                case 'y'        % re-sort by y coordinate
                    [~, indices] = sort(obj.labelPosition(:, 3), direction);
                case 'z'        % re-sort by z coordinate
                    [~, indices] = sort(obj.labelPosition(:, 1), direction);
                case 't'        % re-sort by t coordinate
                    [~, indices] = sort(obj.labelPosition(:, 4), direction);
            end
            if strcmp(direction, 'descend'); indices = indices(end:-1:1); end
            obj.labelText = obj.labelText(indices);
            obj.labelValue = obj.labelValue(indices);
            obj.labelPosition = obj.labelPosition(indices,:);
        end
        
    end
    
end

