function imgOut = resizeImage3d(img, scale, options)
% RESIZEIMAGE3D - Resize a 3D or 4D image dataset.
%
% Syntax:
%
%   .. code-block:: matlab
%
%      imgOut = resizeImage3d(img, scale)
%      imgOut = resizeImage3d(img, scale, options)
%
% Input Arguments:
%   - **img** — [numeric] 3D ``(y, x, z)`` or 4D ``(y, x, z, c)`` dataset to resize
%   - **scale** — [numeric] scalar or vector ``[scaleY, scaleX, scaleZ]`` resize factor;
%     pass ``[]`` when ``options.width`` / ``options.height`` / ``options.depth`` are used instead
%   - **options** *(optional)* — struct with resizing settings:
%
%     - ``.algorithm``    — [char] resizing algorithm: ``'imresize'`` *(default)*, ``'interpn'``, ``'tformarray'``
%     - ``.width``        — [numeric] target width; overrides the ``scale`` parameter
%     - ``.height``       — [numeric] target height; overrides the ``scale`` parameter
%     - ``.depth``        — [numeric] target depth; overrides the ``scale`` parameter
%     - ``.method``       — [char] interpolation method (depends on algorithm — see note below)
%     - ``.imgType``      — [char] dataset type: ``'4D'`` or ``'3D'`` (auto-detected when absent)
%     - ``.showWaitbar``  — [logical] show a progress bar (default: ``1``); set to ``0`` to suppress
%     - ``.wb``           — handle to an existing ``uiprogressdlg``; updated in place, NOT deleted on exit
%     - ``.ParentFigure`` — handle to a parent figure; a local progress dialog is created/deleted when ``.wb`` is absent
%
% Output Arguments:
%   - **imgOut** — [numeric] resampled dataset (same class as input)
%
% .. note::
%    **Algorithm and method combinations:**
%
%    - ``'imresize'`` *(default, fastest)* — uses ``imresize3`` on R2017a+, otherwise resizes XY then Z.
%      Methods: ``'nearest'``, ``'bilinear'``, ``'bicubic'`` *(default)*, ``'lanczos2'``, ``'lanczos3'``, etc.
%    - ``'interpn'`` — N-D gridded interpolation; faster than ``'tformarray'`` but needs more memory.
%      Methods: ``'linear'``, ``'nearest'``, ``'cubic'`` *(default)*, ``'spline'``, ``'pchip'``.
%    - ``'tformarray'`` — spatial transform; slowest but most memory-friendly.
%      Methods: ``'nearest'``, ``'linear'``, ``'cubic'``.
%
% Usage:
%
%   **Example 1** — resize uniformly to 50 %
%
%   .. code-block:: matlab
%
%      imgOut = utils.resizeImage3d(img, 0.5);
%
%   **Example 2** — resize to specific dimensions with bicubic interpolation
%
%   .. code-block:: matlab
%
%      opts.width  = 512;
%      opts.height = 512;
%      opts.depth  = 64;
%      opts.method = 'bicubic';
%      imgOut = utils.resizeImage3d(img, [], opts);
%

% Updates
% 11.04.2017, IB added imresize3 if it is available
% 2026, IB fixed imresize3 API (Method must be name-value pair); added
%           options.wb and options.ParentFigure progress-bar propagation

imgOut = [];
if nargin < 3; options = struct(); end
if nargin < 2; errordlg(sprintf('!!! Error !!!\n\nPlease provide the scaling factor'),'Missing parameters'); return; end;

if ~isfield(options, 'imgType')
    if ndims(img) == 4
        options.imgType = '4D';
    else
        options.imgType = '3D';
    end
end
img = permute(img, [1 2 4 3]);  % 3D:[y,x,z]→[y,x,1,z]; 4D new layout:[y,x,z,c]→[y,x,c,z]

[height, width, colors, depth] = size(img);

if ~isempty(scale) && numel(scale) == 1
    scale = [scale, scale, scale];
end

if ~isfield(options, 'algorithm'); options.algorithm = 'imresize'; end
if ~isfield(options, 'height'); options.height = round(height*scale(1)); end
if ~isfield(options, 'width'); options.width = round(width*scale(2)); end
if ~isfield(options, 'depth'); options.depth = round(depth*scale(3)); end
if ~isfield(options, 'showWaitbar');  options.showWaitbar  = 1;  end
if ~isfield(options, 'wb');           options.wb           = []; end
if ~isfield(options, 'ParentFigure'); options.ParentFigure = []; end

if ~isfield(options, 'method')
    switch options.algorithm
        case 'imresize'
            options.method = 'bicubic';
        case 'interpn'
            options.method = 'cubic';
        case 'tformarray'
            options.method = 'cubic';
    end
end

switch options.algorithm
    case 'imresize'
        methodsList = {'nearest', 'bilinear', 'bicubic', 'box', 'triangle', 'cubic', 'lanczos2', 'lanczos3', 'osc'};
    case 'interpn'
        methodsList = {'linear', 'nearest', 'pchip', 'cubic', 'spline'};
    case 'tformarray'
        methodsList = {'nearest', 'linear','cubic'};
end
errorMethod = ismember(options.method, methodsList);
if errorMethod==0
    errordlg(sprintf('!!! Error !!!\n\nWrong combination of resizing algorithm and resizing method. Please use one of the following: %s', cell2mat(arrayfun(@(x) sprintf(' %s', cell2mat(x)), methodsList,'Uniform', false))),'Wrong method');
    return;
end

newH = options.height;
newW = options.width;
newZ = options.depth;

% ---- set up progress bar ---------------------------------------------------
localWb = [];   % dialog created here (must be deleted on exit)
wb = options.wb;
wbMsg = sprintf('Resizing [%d %d %d %d] -> [%d %d %d %d] using %s...', ...
    height, width, colors, depth, newH, newW, colors, newZ, options.algorithm);

if options.showWaitbar
    if ~isempty(wb)
        % update the caller's existing handle
        try
            if isa(wb, 'matlab.ui.dialog.ProgressDialog')
                wb.Message = wbMsg;
            else
                waitbar(get(wb,'Value'), wb, wbMsg);
            end
        catch; end
    elseif ~isempty(options.ParentFigure)
        % create a local uiprogressdlg
        try
            wb = uiprogressdlg(options.ParentFigure, ...
                'Title',   'Resize image', ...
                'Message', wbMsg);
            localWb = wb;
        catch
            wb = [];
        end
    else
        % classic waitbar (no parent figure available)
        wb = waitbar(0, wbMsg, 'Name', 'Resize image');
        localWb = wb;
    end
end
% ---------------------------------------------------------------------------

if strcmp(options.algorithm, 'imresize')
    imgOut = zeros([newH, newW, colors, newZ], class(img));   %#ok<ZEROLIKE> % allocate space
    
    if ~isempty(which('imresize3')) && ndims(img)>3     % use imresize3 if it exist, introduced in R2017a, seems to be 30% faster
        % imresize3 uses 'cubic' for what imresize calls 'bicubic'
        imresize3Method = options.method;
        if strcmp(imresize3Method, 'bicubic'); imresize3Method = 'cubic'; end
        for colId=1:colors
            % Method must be passed as a name-value pair, not positionally
            imgOut(:,:,colId,:) = permute(imresize3(squeeze(img(:,:,colId,:)), [newH, newW, newZ], 'Method', imresize3Method), [1 2 4 3]);
        end
    else    % use older implementation via imresize
        if newW ~= width || newH ~= height  % resize xy dimension
            imgOut2 = zeros(newH, newW, colors, depth, class(img)); %#ok<ZEROLIKE>
            modVal = round(depth/10);
            for zIndex = 1:depth
                if ~strcmp(options.method, 'osc')
                    imgOut2(:,:,:,zIndex) = imresize(img(:, :, :, zIndex), [newH newW], options.method);
                else
                    imgOut2(:,:,:,zIndex) = imresize(img(:, :, :, zIndex), [newH newW], {@mibOscResampling, 4});
                end
                if mod(zIndex, modVal) == 0 && options.showWaitbar && ~isempty(wb); mibUpdateWaitbar(wb, zIndex/depth); end
            end
        end
        if newZ ~= depth
            if exist('imgOut2','var') == 0; imgOut2 = img; end
            if size(imgOut2, 1)*1.82 < size(imgOut2, 2)
                modVal = round(newH/10);
                for hIndex = 1:newH
                    tempImg = imresize(permute(imgOut2(hIndex, :, :, :), [4 2 3 1]), [newZ, newW], options.method);
                    imgOut(hIndex,:,:,:) = permute(tempImg, [4 2 3 1]);
                    if mod(hIndex,modVal) == 0 && options.showWaitbar && ~isempty(wb); mibUpdateWaitbar(wb, hIndex/newH); end
                end
            else
                modVal = round(newW/10);
                for wIndex = 1:newW
                    tempImg = imresize(permute(imgOut2(:, wIndex, :, :), [1 4 3 2]), [newH newZ], options.method);
                    imgOut(:,wIndex,:,:) = permute(tempImg, [1 4 3 2]);
                    if mod(wIndex,modVal) == 0 && options.showWaitbar && ~isempty(wb); mibUpdateWaitbar(wb, wIndex/newW); end
                end
            end
        else
            imgOut = imgOut2;
        end
    end
elseif strcmp(options.algorithm, 'interpn')
    imgOut = zeros([newH, newW, colors, newZ], class(img));   %#ok<ZEROLIKE> % allocate space
    [xi,yi,zi] = ndgrid(linspace(1, height, newH), linspace(1, width, newW), linspace(1, depth, newZ));
    if options.showWaitbar && ~isempty(wb); mibUpdateWaitbar(wb, 0.1); end
    for colId=1:colors
        if strcmp(options.method,'nearest')
            imgOut(:,:,colId,:) = permute(interpn(squeeze(img(:,:,colId,:)), xi, yi, zi, options.method),[1 2 4 3]);
        else
            if isa(img,'uint8')
                imgOut(:,:,colId,:) = permute(uint8(interpn(single(squeeze(img(:,:,colId,:))), xi, yi, zi, options.method)),[1 2 4 3]);
            elseif isa(img,'uint16')
                imgOut(:,:,colId,:) = permute(uint16(interpn(single(squeeze(img(:,:,colId,:))), xi, yi, zi, options.method)),[1 2 4 3]);
            end
        end
        if options.showWaitbar && ~isempty(wb); mibUpdateWaitbar(wb, colId/colors); end
    end
    if options.showWaitbar && ~isempty(wb); mibUpdateWaitbar(wb, 0.9); end
else
    imgOut = zeros([newH, newW, colors, newZ], class(img));   %#ok<ZEROLIKE> % allocate space
    hgtForm = makehgtform('scale',[newW/width, newH/height, newZ/depth]);
    tForm = maketform('affine', hgtForm);
    R = makeresampler(options.method, 'replicate');
    
    for colId=1:colors
        imgOut(:,:,colId,:) = permute(tformarray(squeeze(img(:,:,colId,:)), tForm, R, [1 2 3], [1 2 3], [newH, newW, newZ], [], 0), [1 2 4 3]);
    end
end


imgOut = permute(imgOut, [1 2 4 3]);  % internal [y,x,c,z] → new layout [y,x,z,c]

% only delete waitbars that were created here; caller-owned handles are left intact
if ~isempty(localWb); try; delete(localWb); catch; end; end

end   % resizeImage3d

% ---- local helper -----------------------------------------------------------
function mibUpdateWaitbar(wb, val)
% MIBUPDATEWAITBAR - Update a waitbar or uiprogressdlg value without erroring on stale handles.
%
% Syntax:
%   function mibUpdateWaitbar(wb, val)
%
try
    if isa(wb, 'matlab.ui.dialog.ProgressDialog')
        wb.Value = val;
    else
        waitbar(val, wb);
    end
catch; end
end
