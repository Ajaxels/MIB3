% This program is free software: you can redistribute it and/or modify
% it under the terms of the GNU General Public License as published by
% the Free Software Foundation, either version 3 of the License, or
% (at your option) any later version.
%
% This program is distributed in the hope that it will be useful,
% but WITHOUT ANY WARRANTY; without even the implied warranty of
% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
% GNU General Public License for more details.
% You should have received a copy of the GNU General Public License
% along with this program.  If not, see <https:% www.gnu.org/licenses/>

% Author: Ilya Belevich, University of Helsinki (ilya.belevich @ helsinki.fi)
% part of Microscopy Image Browser, http:\\mib.helsinki.fi
% Date: 16.04.2025

function result = cropDataset(obj, cropF, options)
% CROPDATASET - Crop image and all corresponding layers of the opened dataset.
%
% Syntax:
%   function result = cropDataset(obj, cropF, options)
%
% Orchestrates cropping across the *image,* *labels,* *mask* and
% *selection* layers, handles the Virtual → Standard conversion for
% virtual datasets, resets viewing coordinates, and updates the physical
% bounding box.
%
% Input Arguments:
%   - **cropF** — a vector ``[x1, y1, dx, dy, z1, dz, t1, dt]`` in pixels
%
%     - *x1,* *y1* — top-left corner of the crop region
%     - *dx,* *dy* — width and height of the crop region
%     - *z1,* *dz* — first slice index and number of slices
%     - *t1,* *dt* — first time point and number of time points
%     - when ``numel(cropF)`` < 7, *t1* and *dt* default to ``[1, obj.image.time]``
%
%   - **options** — *(optional)* structure with additional parameters
%
%     - ``.showWaitbar`` — logical, show a progress dialog (default: **true)**
%     - ``.UIFigure`` — handle to the parent UIFigure for the progress dialog;
%       when empty or absent the dialog is silently skipped
%     - ``.pyramidLevel`` — numeric, OME-Zarr pyramid level for virtual datasets
%       (default: **1)**
%
% Output Arguments:
%   - **result** — **1** on success, **0** on cancel or error
%
% Usage:
%   **Example 1**
%
%   .. code-block:: matlab
%
%
%     result = obj.mibModel.I{obj.mibModel.id}.cropDataset([10 20 100 200 1 5 1 1]);% crop Standard dataset
%
%   **Example 2**
%
%   .. code-block:: matlab
%
%
%     result = obj.mibModel.I{bufferId}.cropDataset(crop_factor, BatchOptLoc);% call from CropDataset controller
%

% Updates
% Ported from MIB2 mibImage.cropDataset

result = 0;

if nargin < 3; options = struct(); end
if ~isfield(options, 'showWaitbar');  options.showWaitbar  = true; end
if ~isfield(options, 'UIFigure');     options.UIFigure     = [];   end
if ~isfield(options, 'pyramidLevel'); options.pyramidLevel = 1;    end

% default time range when not supplied
if numel(cropF) < 7; cropF(7:8) = [1, obj.image.time]; end

x1 = cropF(1);  dx = cropF(3);
y1 = cropF(2);  dy = cropF(4);
z1 = cropF(5);  dz = cropF(6);
t1 = cropF(7);  dt = cropF(8);

% Optional progress dialog — only possible when a UIFigure is provided
wb = [];
if options.showWaitbar && ~isempty(options.UIFigure)
    wb = uiprogressdlg(options.UIFigure, ...
        'Value', 0.05, 'Message', 'Please wait...', 'Title', 'Cropping...');
end

% =========================================================================
%  Standard (memory-resident) path
% =========================================================================
if ~strcmp(obj.datasetType(1), 'V')

    % --- image layer -----------------------------------------------------
    obj.image.crop(cropF);
    if ~isempty(wb); wb.Value = 0.4; end

    % --- label / mask / selection layers ---------------------------------
    if isa(obj.labels, 'core.MibLabels63')
        % Packed model: single array holds model + mask + selection bits.
        % Only crop when data is present (not a NaN sentinel).
        if obj.labels.exists && ~isnan(obj.labels.data{1}(1))
            obj.labels.crop(cropF);
        end
    else
        if obj.modelExist
            obj.labels.crop(cropF);
        end
        if obj.maskExist
            obj.mask.crop(cropF);
        end
        if obj.enableSelection && obj.selection.exists && ~isnan(obj.selection.data{1}(1))
            obj.selection.crop(cropF);
        end
    end
    if ~isempty(wb); wb.Value = 0.7; end

% =========================================================================
%  Virtual (HDD-resident) path — load subvolume then switch to Standard
% =========================================================================
else
    loadOpts.x            = [x1, x1+dx-1];
    loadOpts.y            = [y1, y1+dy-1];
    loadOpts.z            = [z1, z1+dz-1];
    loadOpts.t            = [t1, t1+dt-1];
    loadOpts.pyramidLevel = options.pyramidLevel;

    % Load the subvolume from the virtual source (MibVirtualImage.getData
    % handles both BioFormats-style virtual stacks and OME-Zarr pyramids)
    img = obj.image.getData('image', 3, [], loadOpts);

    % Switch from virtual to memory-resident mode; returns [] on cancel
    newMode = obj.switchDatasetMode(0);
    if isempty(newMode)
        if ~isempty(wb); delete(wb); end
        return;
    end

    % Store the loaded subvolume in the now-Standard image layer
    obj.image.setData(img, 'image', 3, []);

    % Allocate empty service layers sized to the loaded subvolume
    emptyDims = [size(img,1), size(img,2), size(img,3), 1, size(img,5)];
    if obj.enableSelection
        if isa(obj.labels, 'core.MibLabels63')
            % Single packed array: zeros = no model/mask/selection
            obj.labels.data{1}  = zeros(emptyDims, 'uint8');
            obj.labels.height   = emptyDims(1);
            obj.labels.width    = emptyDims(2);
            obj.labels.depth    = emptyDims(3);
            obj.labels.time     = emptyDims(5);
            obj.labels.dim_yxzct = emptyDims;
        else
            obj.labels.data{1}    = NaN;
            obj.mask.data{1}      = zeros(emptyDims, 'uint8');
            obj.selection.data{1} = zeros(emptyDims, 'uint8');
        end
    else
        obj.labels.data{1}    = NaN;
        obj.mask.data{1}      = NaN;
        obj.selection.data{1} = NaN;
    end
    if ~isempty(wb); wb.Value = 0.7; end
end

% =========================================================================
%  Update MibDataset metadata (both paths)
% =========================================================================
if ~isempty(wb); wb.Value = 0.9; end

% Clamp current position to new dimensions
if obj.image.height < obj.current_yxz(1); obj.current_yxz(1) = obj.image.height; end
if obj.image.width  < obj.current_yxz(2); obj.current_yxz(2) = obj.image.width;  end
if obj.image.depth  < obj.current_yxz(3); obj.current_yxz(3) = obj.image.depth;  end

% Sync dim_yxzct from the (already updated) image layer
obj.dim_yxzct = obj.image.dim_yxzct;

% Reset viewing slices to the full new extents
current_layer = obj.slices{obj.orientation}(1);
obj.slices{1} = [1, obj.image.height];
obj.slices{2} = [1, obj.image.width];
obj.slices{3} = [1, obj.image.depth];   % depth is index 3 in MIB3 (was 4 in MIB2)
obj.slices{5} = repmat(min([obj.slices{5}, obj.image.time]), 1, 2);

% Clamp the orientation-specific current slice to the new dimension
% dim_yxzct(orientation): orient 3→depth, orient 1→height, orient 2→width
obj.slices{obj.orientation} = repmat( ...
    min(obj.dim_yxzct(obj.orientation), current_layer), 1, 2);

% Shift the physical bounding box by the crop offset (in physical units)
xyzShift = [(x1-1)*obj.image.pixSize.x, ...
            (y1-1)*obj.image.pixSize.y, ...
            (z1-1)*obj.image.pixSize.z];
obj.updateBoundingBox([], xyzShift);    % propagates pixSize to all layers

if ~isempty(wb); wb.Value = 1; delete(wb); end
result = 1;
end
