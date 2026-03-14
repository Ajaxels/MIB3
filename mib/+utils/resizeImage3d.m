function imgOut = resizeImage3d(img, scale, options)
% function imgOut = resizeImage3d(img, scale, options)
% Resize 3D dataset
%
% Parameters:
% img: a 3D (y,x,z) or 4D (y,x,c,z) dataset for resize
% scale: a number or a vector [scaleY, scaleX, scaleZ] for each dimension with resizing scaling
% factor, could be empty when options.width, options.height, options.depth
% fields are used
% options: [@em optional], additional options
% @li .algorithm - a string with resizing algorithm: 'imresize', 'interpn', 'tformarray', see below for notes
% @li .width - a new width value, overrides the scale parameter
% @li .height - a new height value, overrides the scale parameter
% @li .depth - a new depth value, overrides the scale parameter
% @li .method - interpolation method, specified as a string that identifies
% a general method or a named interpolation kernel: @b imresize: 'nearest',
% 'bilinear', 'bicubic', 'box', 'triangle', 'cubic', 'lanczos2', 'osc'
% 'lanczos3'; @b interpn: 'linear', 'nearest', 'pchip', 'cubic', 'spline';
% @b tformarray - 'nearest', 'linear','cubic'
% @li .imgType - a string with type of the dataset '4D' or '3D'
% @li .showWaitbar -> [@em optional], when 1-default, show the wait bar, when 0 - do not show the waitbar
% @li .wb - handle to an existing waitbar / uiprogressdlg; when provided it
%           is updated in place and NOT deleted on exit (the caller owns it)
% @li .ParentFigure - handle to a parent figure; when .wb is absent and
%           this is non-empty, a local uiprogressdlg is created and deleted
%           within this call (ignored when .showWaitbar is 0)
%
% Return values:
% imgOut: resampled dataset
%
% @note Resizing algorithms:
% @li 'imresize' - [@em default] (fastest) for R2017a and later uses imresize3 function, otherwise use imresize to resize XY dimension after resize the Z-dimension, gives somewhat softer images than other methods;
% @li 'interpn' - interpolation for 1-D, 2-D, 3-D, and N-D gridded data in
% ndgrid format, quite fast but requires more memory that other methods
% @li 'tformarray' - resize using a spatial transformation to N-D array,
% quite slow but more memory friendly comparing to 'interpn'

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
if strcmp(options.imgType, '3D'); img = permute(img, [1 2 4 3]); end

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


if strcmp(options.imgType, '3D')
    imgOut = permute(imgOut, [1 2 4 3]);
end

% only delete waitbars that were created here; caller-owned handles are left intact
if ~isempty(localWb); try; delete(localWb); catch; end; end

end   % resizeImage3d

% ---- local helper -----------------------------------------------------------
function mibUpdateWaitbar(wb, val)
% Update a waitbar or uiprogressdlg value without erroring on stale handles.
try
    if isa(wb, 'matlab.ui.dialog.ProgressDialog')
        wb.Value = val;
    else
        waitbar(val, wb);
    end
catch; end
end
