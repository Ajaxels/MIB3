classdef MatModelLoader < io.loaders.BaseImageLoader
% MATMODELLOADER - Loader for MATLAB-format segmentation model files.
%
% Handles three on-disk formats written by core.MibLabels.save:
% .model  — MIB3/MIB2 native MATLAB format (modelVariable, modelMaterialNames, …)
% .mat    — MIB v1 legacy format (model_var, material_list, color_list, …)
% .mibCat — MATLAB categorical format (imgOut as categorical, options struct)
%
% The loader caches the raw model array in files(i).data during loadMetadata
% to avoid re-reading the file in loadImages.

    methods
        function obj = MatModelLoader(options)
            % MATMODELLOADER - Constructor for MatModelLoader class.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      loader = io.loaders.MatModelLoader(options)
            %
            % Input Arguments:
            %   - **options** — *(optional)* struct with fields:
            %
            %     - ``mibPath`` — [char] path to MIB directory
            %     - ``ParentFigure`` — handle to parent figure for dialogs
            %
            % Output Arguments:
            %   - **obj** — instance of MatModelLoader
            %

            obj.Options = struct();
            if nargin < 1; options = struct(); end
            obj.Options = obj.mergeOptions(obj.Options, options);
            obj.initBaseProps(options);
        end

        function [imginfo, files] = loadMetadata(obj, filenames, options)
            % LOADMETADATA - Load both metadata and raw pixels for MATLAB-format model files.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      [imginfo, files] = obj.loadMetadata(filenames, options)
            %
            % Reads each MAT/model/mibCat file, determines the labelsVariable,
            % extracts all model metadata (material names, colors, type, annotations),
            % and caches the raw array in files(i).data.
            %
            % Input Arguments:
            %   - **filenames** — cell array with full path filenames to load
            %   - **options** — *(optional)* struct for metadata loading
            %
            % Output Arguments:
            %   - **imginfo** — dictionary with model metadata containing fields:
            %
            %     - ``modelMaterialNames`` — cell array of material names
            %     - ``modelMaterialColors`` — Nx3 RGB matrix (values 0..1)
            %     - ``modelType`` — numeric type (63/255/65535/4294967295)
            %     - ``labelsVariable`` — variable name used in the MAT file
            %     - ``labelText`` — annotation text (or ``[]``)
            %     - ``labelPosition`` — annotation positions (or ``[]``)
            %     - ``labelValue`` — annotation values (or ``[]``)
            %     - ``BoundingBox`` — [1x6] bounding box (or ``[]``)
            %     - ``numEntries`` — number of successfully loaded files
            %
            %   - **files** — structure array with per-file information:
            %
            %     - ``filename`` — [char] full path
            %     - ``height``, ``width``, ``noLayers`` — dimensions
            %     - ``color``, ``time`` — always 1
            %     - ``imgClass`` — MATLAB class of the raw array
            %     - ``data`` — raw model array (cached)
            %
            % **Example 1** — load model metadata:
            %
            %   .. code-block:: matlab
            %
            %      loader = io.loaders.MatModelLoader();
            %      [imginfo, files] = loader.loadMetadata({'path/to/Labels.model'});
            %

            if nargin < 3; options = obj.Options; end
            options = obj.mergeOptions(obj.Options, options);

            % Initialize default options
            if ~isfield(options, 'waitbar'); options.waitbar = true; end

            % Init imginfo with standard defaults
            imginfo = core.MibImage.initializeImgInfo();

            % Add model-specific keys with defaults
            imginfo{"modelMaterialNames"}  = {};
            imginfo{"modelMaterialColors"} = [];
            imginfo{"modelType"}           = 255;
            imginfo{"labelsVariable"}      = 'mibModel';
            imginfo{"labelText"}           = [];
            imginfo{"labelPosition"}       = [];
            imginfo{"labelValue"}          = [];
            imginfo{"BoundingBox"}         = [];
            imginfo{"numEntries"}          = 0;

            noFiles = numel(filenames);

            % Pre-allocate files structure
            files(noFiles) = struct( ...
                'filename',  [], ...
                'height',    [], ...
                'width',     [], ...
                'noLayers',  [], ...
                'color',     [], ...
                'time',      [], ...
                'imgClass',  [], ...
                'data',      []);

            % Initialize waitbar
            pwb = [];
            if options.waitbar && ~isempty(obj.ParentFigure)
                pwb = core.PoolWaitbar(noFiles, ...
                    sprintf('Loading model data and metadata\nPlease wait...'), ...
                    obj.ParentFigure, 'Model import', true, true);
            end

            loadedCount = 0;
            for iFile = 1:noFiles
                % Check for cancel
                if ~isempty(pwb) && pwb.getCancelState()
                    pwb.deletePoolWaitbar();
                    imginfo = dictionary();
                    return;
                end

                filename = filenames{iFile};
                [~, ~, ext] = fileparts(filename);
                ext = lower(strrep(ext, '.', ''));

                % Load the MAT file
                try
                    res = load(filename, '-mat');
                catch ME
                    utils.dlgs.showErrorDialog([], ME, 'MatModel Loader Error', sprintf('Could not load file:\n%s\n', filename));
                    continue;
                end

                % --- Determine the labelsVariable ---
                labVar = '';
                if isfield(res, 'modelVariable') && ~isempty(res.modelVariable)
                    labVar = res.modelVariable;
                elseif isfield(res, 'imgVariable') && ~isempty(res.imgVariable)
                    % mibCat format
                    labVar = res.imgVariable;
                elseif isfield(res, 'model_var') && ~isempty(res.model_var)
                    % MIB v1 legacy
                    labVar = res.model_var;
                else
                    % Scan fields; skip known metadata fields
                    skipFields = {'modelMaterialNames', 'modelMaterialColors', ...
                        'modelType', 'BoundingBox', 'labelText', 'labelPosition', ...
                        'labelValue', 'material_list', 'color_list', 'bounding_box', ...
                        'model_var', 'options', 'imgVariable', 'modelVariable'};
                    fnames = fieldnames(res);
                    for k = 1:numel(fnames)
                        if ~ismember(fnames{k}, skipFields)
                            labVar = fnames{k};
                            break;
                        end
                    end
                end

                if isempty(labVar) || ~isfield(res, labVar)
                    utils.dlgs.showErrorDialog([], sprintf('Cannot determine data variable in: %s', filename), 'MatModel Loader Error', 'MatModelLoader:noDataVar');
                    continue;
                end

                % --- Extract raw array ---
                rawData = res.(labVar);

                % --- Handle mibCat format ---
                if strcmp(ext, 'mibcat') && iscategorical(rawData)
                    % Convert categorical → 0-based uint8 model indices.
                    % double() returns 1-based indices in the stored category
                    % order (Exterior first, then materials).  Subtracting 1
                    % maps: Exterior(1)→0, material1(2)→1, etc.
                    % This is correct regardless of alphabetical order, unlike
                    % grp2idx which sorts categories alphabetically first.
                    % Undefined categories (NaN after double) → 0 = Exterior.
                    origSize = size(rawData);
                    rawDataDbl = double(rawData(:));
                    rawDataDbl(isnan(rawDataDbl)) = 1;   % undefined → 0 after -1
                    rawData = uint8(rawDataDbl - 1);
                    rawData = reshape(rawData, origSize);

                    % Read options struct.  MIB2 and fixed MIB3 use 'options';
                    % older MIB3 files used 'catOptions' before the rename fix.
                    opt = struct();
                    if isfield(res, 'options');    opt = res.options; end
                    if isfield(opt, 'modelType'); imginfo{"modelType"} = opt.modelType; end

                    if isfield(opt, 'modelMaterialNames')
                        names = opt.modelMaterialNames(:);
                        % Strip implicit Exterior (index 0) — MibLabels.materialNames
                        % holds only real materials (indices 1..N).
                        if ~isempty(names) && strcmp(names{1}, 'Exterior')
                            names = names(2:end);
                        end
                        imginfo{"modelMaterialNames"} = names;
                    end

                    if isfield(opt, 'modelMaterialColors')
                        colors = opt.modelMaterialColors;
                        % MIB2 saves N+1 colors (Exterior at row 1 + N materials).
                        % Strip the Exterior row when colors count matches the
                        % full names list (including Exterior).
                        if isfield(opt, 'modelMaterialNames')
                            nAllNames = numel(opt.modelMaterialNames);
                            if nAllNames > 0 && strcmp(opt.modelMaterialNames{1}, 'Exterior') ...
                                    && size(colors, 1) == nAllNames
                                colors = colors(2:end, :);
                            end
                        end
                        imginfo{"modelMaterialColors"} = colors;
                    end
                else
                    % --- .model (MIB3/MIB2 native) or .mat (MIB v1) ---

                    % Material names
                    if isfield(res, 'modelMaterialNames')
                        imginfo{"modelMaterialNames"} = res.modelMaterialNames;
                    elseif isfield(res, 'material_list')
                        imginfo{"modelMaterialNames"} = res.material_list;
                    end

                    % Material colors
                    if isfield(res, 'modelMaterialColors')
                        imginfo{"modelMaterialColors"} = res.modelMaterialColors;
                    elseif isfield(res, 'color_list')
                        imginfo{"modelMaterialColors"} = res.color_list;
                    end

                    % Model type
                    if isfield(res, 'modelType')
                        imginfo{"modelType"} = res.modelType;
                    end

                    % Bounding box
                    if isfield(res, 'BoundingBox')
                        imginfo{"BoundingBox"} = res.BoundingBox;
                    elseif isfield(res, 'bounding_box')
                        imginfo{"BoundingBox"} = res.bounding_box;
                    end

                    % Annotations
                    if isfield(res, 'labelText')
                        imginfo{"labelText"} = res.labelText;
                    end
                    if isfield(res, 'labelPosition')
                        imginfo{"labelPosition"} = res.labelPosition;
                    end
                    if isfield(res, 'labelValue')
                        imginfo{"labelValue"} = res.labelValue;
                    end
                end

                % Auto-detect modelType if it was not stored in the file
                if ~isfield(res, 'modelType') && ~(strcmp(ext, 'mibcat') && isfield(res, 'options') && isfield(res.options, 'modelType'))
                    imginfo{"modelType"} = io.loaders.MatModelLoader.autoDetectModelType(rawData);
                end

                % Dimensions: file saves squeeze(data) → [H W D] or [H W] for 2D
                sz = size(rawData);
                H = sz(1);
                W = sz(2);
                D = 1;
                T = 1;
                if numel(sz) >= 3; D = sz(3); end
                if numel(sz) >= 5; T = sz(5); end

                imginfo{"labelsVariable"} = labVar;
                imginfo{"Height"}         = H;
                imginfo{"Width"}          = W;
                imginfo{"Depth"}          = D;
                imginfo{"Time"}           = T;
                imginfo{"imgClass"}       = class(rawData);
                imginfo{"Colors"}         = 1;
                imginfo{"Filename"}       = filename;

                files(iFile).filename = filename;
                files(iFile).height   = H;
                files(iFile).width    = W;
                files(iFile).noLayers = D;
                files(iFile).color    = 1;
                files(iFile).time     = T;
                files(iFile).imgClass = class(rawData);
                files(iFile).data     = rawData;  % cache to avoid re-reading

                loadedCount = loadedCount + 1;

                % Update waitbar
                if ~isempty(pwb); pwb.increment(); end
            end

            if ~isempty(pwb); pwb.deletePoolWaitbar(); end

            imginfo{"numEntries"} = loadedCount;
        end

        function [img, imginfo] = loadImages(~, files, imginfo, ~)
            % LOADIMAGES - Assemble cached model data from files into a 5-D array.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      [img, imginfo] = obj.loadImages(files, imginfo, options)
            %
            % Reads the pre-cached data from files(i).data and stacks them
            % along the Z dimension into a [H W D 1 T] array.
            %
            % Input Arguments:
            %   - **files** — structure array from loadMetadata with ``data``, ``noLayers``, etc.
            %   - **imginfo** — dictionary from loadMetadata
            %   - **options** — *(optional)* struct (unused, kept for interface conformance)
            %
            % Output Arguments:
            %   - **img** — [H W totalZ 1 T] model array
            %   - **imginfo** — unchanged dictionary
            %
            % **Example 1** — load model images:
            %
            %   .. code-block:: matlab
            %
            %      loader = io.loaders.MatModelLoader();
            %      [imginfo, files] = loader.loadMetadata({'Labels.model'});
            %      [img, imginfo]   = loader.loadImages(files, imginfo);
            %

            H        = max([files.height]);
            W        = max([files.width]);

            %H        = imginfo{"Height"};
            %W        = imginfo{"Width"};
            T        = imginfo{"Time"};
            imgClass = imginfo{"imgClass"};
            totalZ   = sum([files.noLayers]);

            img = zeros(H, W, totalZ, 1, T, imgClass);
            z1  = 1;
            for iFile = 1:numel(files)
                if isempty(files(iFile).data); continue; end
                % rawData = reshape(files(iFile).data, ...
                %     [files(iFile).height, files(iFile).width, ...
                %      files(iFile).noLayers, 1, files(iFile).time]);
                z2 = z1 + files(iFile).noLayers - 1;
                % img(:, :, z1:z2, 1, :) = rawData;
                if numel(files) == 1 %#ok<ISCL>
                    img = files(iFile).data;
                else    
                    img(1:files(iFile).height, 1:files(iFile).width, z1:z2, 1, :) = files(iFile).data;
                end
                z1 = z2 + 1;
            end
        end
    end

    methods (Static, Access = private)
        function modelType = autoDetectModelType(data)
            % AUTODETECTMODELTYPE - Detect model type from class and maximum pixel value.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      modelType = io.loaders.MatModelLoader.autoDetectModelType(data)
            %
            % Input Arguments:
            %   - **data** — raw model array
            %
            % Output Arguments:
            %   - **modelType** — numeric type (``63``/``255``/``65535``/``4294967295``)
            %

            switch class(data)
                case 'uint8'
                    if max(data(:)) <= 63
                        modelType = 63;
                    else
                        modelType = 255;
                    end
                case 'uint16'
                    modelType = 65535;
                case {'uint32', 'double', 'single'}
                    modelType = 4294967295;
                otherwise
                    modelType = 255;
            end
        end
    end
end
