function listenerUpdateDatasetAxes(obj, src, evtData)
% function listenerUpdateDatasetAxes(obj, src, evtData)
% Update obj.I (MibDataset).axesX and obj.I (MibDataset).axesY during fit screen, resize, or new dataset drawing
% executed upon catch of MibModel->"UpdateDatasetAxes" event
%
% Parameters:
% src: handle to MibModel
% evtData: event data, an instance of core.ToggleEventData class with the following fields:
% .Parameters field containing a structure with the
%    .evtData.Parameters.mode - update mode,
%         @li 'resize' -> [@em default] scale to width/height
%         @li 'zoom' -> scale during the zoom
%    .evtData.Parameters.index -> [@b optional] index of obj.I to update, when @em [] updates the currently selected dataset
%    .evtData.Parameters.newMagFactor -> a value of the new magnification factor, only for the 'zoom' mode
% .Source -> handle to MibModel
% .EventName -> string with the event name that triggered the callback
% see example in MibModel.datasetsSetsOps-> 'Add set'
%
% Return values:
% 

%| 
% @b Examples:
% @code 
% // call from controllers.MibController; update the axes using new magnification value of the first dataset in the global index count
% Options.mode = 'zoom';
% Options.newMagFactor = 2;
% Options.index = 1;
% eventdata = core.ToggleEventData(Options);
% notify(obj.mibModel, 'UpdateDatasetAxes', eventdata);
% @endcode 
%
% @code
% // call from controllers.MibController; to fit the screen @endcode
% Options.mode = 'resize';
% eventdata = core.ToggleEventData(Options);
% notify(obj.mibModel, 'UpdateDatasetAxes', eventdata);
% @endcode 
% @code
% // update the current dataset using the "resize" mode
% notify(obj.mibModel, 'UpdateDatasetAxes');
% @endcode 
%
% Updates
% 

% update the missing fields
if ~isprop(evtData, 'Parameters')
    Parameters = struct; 
else
    Parameters = evtData.Parameters;
end

if ~isfield(Parameters, 'mode'); Parameters.mode = 'resize'; end
if ~isfield(Parameters, 'index'); Parameters.index = obj.mibModel.id; end
if ~isfield(Parameters, 'newMagFactor'); Parameters.newMagFactor = 1; end
if ~isfield(Parameters, 'setOfDatasetsIndex'); Parameters.setOfDatasetsIndex = []; end 

% make local variables
mode = Parameters.mode;
index = Parameters.index;
newMagFactor = Parameters.newMagFactor; 

% get the set id from the dataset id OR use provided setOfDatasetsIndex
if ~isempty(Parameters.setOfDatasetsIndex)
    selectedSet = Parameters.setOfDatasetsIndex;  % Use explicit setOfDatasetsIndex
else
    selectedSet = ceil(index/obj.mibModel.Sets.datasetsInSet);  % Calculate from index
end

% get the scaling coefficient
if obj.mibModel.I{index}.orientation == 3     % xy
    coef_z = obj.mibModel.I{index}.pixSize.x/obj.mibModel.I{index}.pixSize.y;
    height = obj.mibModel.I{index}.dim_yxzct(1); % height
    width = obj.mibModel.I{index}.dim_yxzct(2);  % width
elseif obj.mibModel.I{index}.orientation == 1     % ---- xz
    coef_z = obj.mibModel.I{index}.pixSize.z/obj.mibModel.I{index}.pixSize.x;
    height = obj.mibModel.I{index}.dim_yxzct(2); % width
    width = obj.mibModel.I{index}.dim_yxzct(3);  % depth
elseif obj.mibModel.I{index}.orientation == 2    % ---- yz
    coef_z = obj.mibModel.I{index}.pixSize.z/obj.mibModel.I{index}.pixSize.y;
    height = obj.mibModel.I{index}.dim_yxzct(1); % height
    width = obj.mibModel.I{index}.dim_yxzct(3);  % depth
end

% get axes position from a previous set, as the function obtains position
% of not yet created axes
if numel(obj.cImageDoc) < selectedSet; selectedSet = selectedSet - 1; end

%drawnow;
axSize = obj.cImageDoc{selectedSet}.handles.imViewAxes.InnerPosition;

[axesX, axesY] = obj.mibModel.I{index}.getAxesLimits();
magFactor = obj.mibModel.I{index}.magFactor;
if isnan(axesX(1)) || strcmp(mode, 'resize') == 1
    imageAR = (width * coef_z) / height;  % Image aspect ratio (physical)
    axesAR = axSize(3) / axSize(4);       % Axes aspect ratio

    if imageAR > axesAR
        % Image wider than axes: fit to width
        magFactor = (width * coef_z) / axSize(3);
        axesX = [1, width];
        axesY = [height/2 - (axSize(4) * magFactor)/2, ...
            height/2 + (axSize(4) * magFactor)/2];
    else
        % Image taller/narrower than axes: fit to height
        magFactor = height / axSize(4);
        axesY = [1, height];
        axesX = [width/2 - (axSize(3) * magFactor)/(2 * coef_z), ...
            width/2 + (axSize(3) * magFactor)/(2 * coef_z)];
    end

    % if height < axSize(4) && width*coef_z >= axSize(3)     % scale to width
    %     magFactor = width*coef_z/axSize(3);
    %     axesX(1) = 1;
    %     axesX(2) = width;
    %     axesY(1) = height/2 - axSize(4)/2*magFactor;
    %     axesY(2) = height/2 + axSize(4)/2*magFactor;
    % elseif height >= axSize(4) && width*coef_z < axSize(3)     % scale to height
    %     magFactor = height/axSize(4);
    %     axesX(1) = width/2 - axSize(3)/2/coef_z*magFactor;
    %     axesX(2) = width/2 + axSize(3)/2/coef_z*magFactor;
    %     axesY(1) = 1;
    %     axesY(2) = height;
    % else        % scale to the width/height
    %     if axSize(4)/height < axSize(3)/(width*coef_z)   % scale to height
    %         magFactor = height/axSize(4);
    %         axesX(1) = width/2 - axSize(3)/coef_z/2*magFactor;
    %         axesX(2) = width/2 + axSize(3)/2/coef_z*magFactor;
    %         axesY(1) = 1;
    %         axesY(2) = height;
    %     else % scale to width
    %         magFactor = width*coef_z/axSize(3);
    %         axesX(1) = 1;
    %         axesX(2) = width;
    %         axesY(1) = height/2 - axSize(4)/2*magFactor;
    %         axesY(2) = height/2 + axSize(4)/2*magFactor;
    %     end
    % end
elseif strcmp(mode, 'zoom')
    dxHalf = diff(axesX)/2;
    dyHalf = diff(axesY)/2;
    xCenter = axesX(1) + dxHalf;
    yCenter = axesY(1) + dyHalf;
    xLim(1) = xCenter - dxHalf*newMagFactor/magFactor;
    xLim(2) = xCenter + dxHalf*newMagFactor/magFactor;
    yLim(1) = yCenter - dyHalf*newMagFactor/magFactor;
    yLim(2) = yCenter + dyHalf*newMagFactor/magFactor;
    % check for out of image boundaries cases
    if xLim(2) < 1 || xLim(1) > width
        xLim = xLim - xLim(1);
    end
    if yLim(2) < 1 || yLim(1) > height
        yLim = yLim - yLim(1);
    end
    axesX = xLim;
    axesY = yLim;
    magFactor = newMagFactor;
end
% update axes limits and magnification factor
obj.mibModel.I{index}.setAxesLimits(axesX, axesY);
obj.mibModel.I{index}.magFactor = magFactor;
obj.cImageDoc{selectedSet}.brushCursorOffset = []; 

%sprintf('axes: %d-%d %d-%d\n', axesX(1), axesX(2), axesY(1), axesY(2))

% notify listeners that the image axes were changed -> mibSnapshotController
%motifyEvent.Name = 'updteAxesLimits_changed';
%eventdata = ToggleEventData(motifyEvent);
%notify(obj.mibModel, 'modelNotify', eventdata);

end
