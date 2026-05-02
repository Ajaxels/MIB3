function [img_info, pixSize, result] = updatePixSizeAndResolution(img_info, pixSize, options)
% UPDATEPIXSIZEANDRESOLUTION - Calculate update resolution fields in the imageData.img_info('ImageDescription') or recalculate physical size of voxels.
%
% Syntax:
%
%   .. code-block:: matlab
%
%      [img_info, pixSize, result] = updatePixSizeAndResolution(img_info, pixSize)
%      [img_info, pixSize, result] = updatePixSizeAndResolution(img_info, pixSize, options)
%
% Optionally shows an interactive dialog so the user can review/change voxel sizes before the update is applied.
%
% - If 'BoundingBox' information exist in the imageData.img_info('ImageDescription') the function recalculates the
%   imageData.pixSize based on information from the BoundingBox.
% - If 'BoundingBox' is missing, but imageData.img_info('XResolution') is present the imageData.pixSize recalculated based
%   on XResolution and YResolution information
% - If both 'BoundingBox' and 'XResolution' is missing, the resolution is recalculated based on imageData.pixSize
%
% Input Arguments:
%   - **img_info** — information about the dataset, an instance of the MATLAB **dictionary** class.
%     Pass **[]** to skip the img_info resolution update (e.g. when only the dialog / pixSize update is needed).
%   - **pixSize** — a structure (imageData.pixSize) with dimensions of voxels, ``.x .y .z .t .tunits .units``
%     the fields are
%     - .x - physical width of a pixel
%     - .y - physical height of a pixel
%     - .z - physical depth of a pixel
%     - .t - time between the frames for 2D movies
%     - .tunits - time units
%     - .units - physical units for x, y, z. Possible values: [m, cm, mm, um, nm]
%   - **options** — *(optional)* a struct with optional fields:
%     - .showDialog   - logical (default false); when true, prompt the user with an interactive
%       dialog to review and edit the voxel sizes before applying
%     - .ParentFigure - handle to the parent figure/window used to anchor the dialog
%     - .mibPath      - (char) MIB installation directory, used for help / icon lookup
%     - .HelpUrl      - (char) URL or path for the Help button shown in the dialog
%     - .WindowStyle  - [char] ``'normal'`` (default) or ``'modal'``
%
% Output Arguments:
%   - **img_info** — updated imageData.img_info (unchanged and [] when img_info was passed as [])
%   - **pixSize** — updated imageData.pixSize (unchanged when user cancels the dialog)
%   - **result** — **1** on success, **0** when the user cancelled the interactive dialog
%
%
% .. note::
%    Requires ``Width``, ``Height``, ``Depth`` fields in ``img_info`` when ``img_info`` is not ``[]``.
%
% Usage:
%
%   **Example 1** — update resolution fields in img_info from a known pixSize (no dialog)
%
%   .. code-block:: matlab
%
%      pixSize.x = 0.05; pixSize.y = 0.05; pixSize.z = 0.2;
%      pixSize.t = 1; pixSize.units = 'um'; pixSize.tunits = 's';
%      [img_info, pixSize] = utils.updatePixSizeAndResolution(img_info, pixSize);
%
%   **Example 2** — recalculate pixSize from BoundingBox / XResolution stored in img_info
%
%   .. code-block:: matlab
%
%      [img_info, pixSize] = utils.updatePixSizeAndResolution(img_info);
%
%   **Example 3** — interactive dialog only (no img_info update needed, e.g. from MibRibbon)
%
%   .. code-block:: matlab
%
%      dlgOpts.showDialog   = true;
%      dlgOpts.ParentFigure = obj.view.gui;
%      dlgOpts.mibPath      = obj.mibModel.mibPath;
%      dlgOpts.HelpUrl      = fullfile(obj.mibModel.mibPath, 'techdoc/html/user-interface/menu/dataset/index.html#parameters');
%      [~, pixSize, result] = utils.updatePixSizeAndResolution([], obj.mibModel.I{id}.pixSize, dlgOpts);
%      if result == 0; return; end
%      obj.mibModel.I{id}.pixSize = pixSize;
%
%   **Example 4** — interactive dialog + img_info update in one call (e.g. during save)
%
%   .. code-block:: matlab
%
%      dlgOpts.showDialog   = true;
%      dlgOpts.ParentFigure = obj.mibGUI;
%      dlgOpts.mibPath      = obj.mibPath;
%      [img_info, pixSize, result] = utils.updatePixSizeAndResolution(img_info, currentPixSize, dlgOpts);
%      if result == 0; return; end
%

% Updates
% 13.03.2026 added optional interactive dialog and result return value

result = 1;
if nargin < 3; options = struct(); end
if ~isfield(options, 'showDialog');   options.showDialog   = false; end
if ~isfield(options, 'ParentFigure'); options.ParentFigure = []; end
if ~isfield(options, 'mibPath');      options.mibPath      = ''; end
if ~isfield(options, 'HelpUrl');      options.HelpUrl      = ''; end
if ~isfield(options, 'WindowStyle');  options.WindowStyle  = 'normal'; end


% Remember whether the caller explicitly supplied pixSize (used later to decide
% whether to trust img_info{'XResolution'} or the provided/dialog-updated pixSize)
pixSizeProvided = nargin >= 2 && ~isempty(pixSize);

if ~pixSizeProvided
    pixSize.x = 1;
    pixSize.y = 1;
    pixSize.z = 1;
    pixSize.t = 1;
    pixSize.tunits = 's';
    pixSize.units = 'um';
end

%% Interactive dialog — prompt user to review / change voxel sizes
if options.showDialog
    unitsList = {'m', 'cm', 'mm', 'um', 'nm'};
    unitIdx   = find(strcmp(unitsList, pixSize.units), 1);
    if isempty(unitIdx); unitIdx = 4; end   % fall back to 'um'

    % Round off IEEE 754 noise that accumulates when pixSize was derived from
    % a BoundingBox string (e.g. 0.013000000000000003 → 0.013)
    pixSize.x = round(pixSize.x, 10, 'significant');
    pixSize.y = round(pixSize.y, 10, 'significant');
    pixSize.z = round(pixSize.z, 10, 'significant');

    prompts = {'Voxel size X:'; 'Voxel size Y:'; 'Voxel size Z:'; ...
               'Time between frames:'; 'Pixel units:'; 'Time units (h, m, s):'};
    defAns  = {pixSize.x; pixSize.y; pixSize.z; pixSize.t; ...
               [unitsList, {unitIdx}]; pixSize.tunits};

    dlgOptions.WindowStyle = 'normal';
    dlgOptions.WindowHeight = 320;
    dlgOptions.WindowWidth = 300;
    dlgOptions.LabelPosition = 'top';
    dlgOptions.Focus = 1;
    dlgOptions.WindowStyle = options.WindowStyle;
    if ~isempty(options.mibPath);  dlgOptions.mibPath  = options.mibPath;  end
    if ~isempty(options.HelpUrl);  dlgOptions.HelpUrl  = options.HelpUrl;  end

    answer = utils.dlgs.inputUniversalDlg(options.ParentFigure, '', prompts, defAns, ...
        'Dataset parameters', dlgOptions);
    if isempty(answer)
        result = 0;
        return;
    end

    pixSize.x      = answer{1};   % double from numeric edit field
    pixSize.y      = answer{2};
    pixSize.z      = answer{3};
    pixSize.t      = answer{4};
    pixSize.units  = answer{5};   % string from dropdown
    pixSize.tunits = answer{6};   % string from text edit

    pixSizeProvided = true;   % treat dialog answer as explicitly provided
end

%% When no img_info is requested, stop here — pixSize already updated above
if isempty(img_info); return; end

% update resolution and pixel sizes
curr_text = img_info{'ImageDescription'};
if iscell(curr_text); curr_text = curr_text{1}; end
width  = img_info{'Width'};
height = img_info{'Height'};
depth  = img_info{'Depth'};
bb_info_exist = strfind(curr_text,'BoundingBox');
if bb_info_exist > 0   % use information from the BoundingBox parameter for pixel sizes if it is exist
    spaces = strfind(curr_text,' ');
    if numel(spaces) < 7; spaces(7) = numel(curr_text); end
    tab_pos = strfind(curr_text,sprintf('|'));
    pos = min([spaces(7) tab_pos]);
    bb_coord = str2num(curr_text(spaces(1):pos)); %#ok<ST2NM>
    dx = bb_coord(2)-bb_coord(1);
    dy = bb_coord(4)-bb_coord(3);
    dz = bb_coord(6)-bb_coord(5);
    % Round to 10 significant figures to remove IEEE 754 noise from the
    % BoundingBox string → division round-trip (e.g. 4.823/371 ≠ 0.013 exactly)
    pixSize.x = round(dx/(max([width 2])-1),  10, 'significant');  % tweak for single-layered tifs (Amira)
    pixSize.y = round(dy/(max([height 2])-1), 10, 'significant');
    pixSize.z = round(dz/(max([depth 2])-1),  10, 'significant');
    if isnan(pixSize.z);   pixSize.z = pixSize.x; end  % fix to do not get errors for setting of DataAspectRatio
    pixSize.units = 'um';
    resolution = utils.calculateResolution(pixSize);
else
    if ~isKey(img_info,'XResolution') || pixSizeProvided
        resolution = utils.calculateResolution(pixSize);
    else
        if ischar(img_info{'XResolution'})  % this may come from ome.tiff when loading with bio-formats, but in practice it is not resolution, but pixel size
            img_info{'XResolution'} = str2double(img_info{'XResolution'}); 
            img_info{'YResolution'} = str2double(img_info{'YResolution'}); 
        end
        if isempty(img_info{'XResolution'}) || img_info{'XResolution'} == 0 || img_info{'YResolution'} == 0
            resolution = mibCalculateResolution(pixSize);
        else
            pixSize_temp = utils.calculatePixSizes([img_info{'XResolution'} img_info{'YResolution'}], img_info{'ResolutionUnit'}, 'um');
            pixSize.x = pixSize_temp.x;
            pixSize.y = pixSize_temp.y;
            pixSize.z = pixSize_temp.x;
            resolution = utils.calculateResolution(pixSize);
        end
    end
    
    % generate BoundingBox Info and add to ImageDescription
    coef = 1; % um
    dx = (max([width 2])-1)*pixSize.x*coef;     % tweek for Amira single layer images max([w 2])
    dy = (max([height 2])-1)*pixSize.y*coef;
    dz = (max([depth 2])-1)*pixSize.z*coef; %#ok<PROP>
    newBB = [0, dx,0, dy, 0, dz];
    str2 = sprintf('BoundingBox %.5f %.5f %.5f %.5f %.5f %.5f ',...
    newBB(1), newBB(2), newBB(3), newBB(4), newBB(5), newBB(6));
    curr_text = img_info{'ImageDescription'};
    if iscell(curr_text); curr_text = curr_text{1}; end
    img_info{'ImageDescription'} = sprintf('%s|%s', str2, curr_text); 
    
end
img_info{'XResolution'} = resolution(1);
img_info{'YResolution'} = resolution(2);
img_info{'ResolutionUnit'} = 'Inch';
end
