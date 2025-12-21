classdef Imread
    % Imread
    % Loader for generic image formats supported by MATLAB imread/imfinfo.
    %
    % Goals:
    % - Extract per-file metadata using imfinfo
    % - Provide files struct compatible with existing pipeline
    % - Load data using imread with optional:
    %   * pyramidal TIF/containers: files(i).level
    %   * ROI: files(1).xMin/xMax/yMin/yMax/xyStep (+ optional zMin/zMax)
    %   * Z-range: files(i).zMin/zMax
    %   * backgroundColor: padding for mismatched XY sizes

    properties
        filenames   % cellstr
        options     % struct
    end

    methods
        function obj = Imread(filenames, options)
            if nargin < 2; options = struct(); end
            if ischar(filenames) || isstring(filenames); filenames = {char(filenames)}; end
            obj.filenames = filenames;
            obj.options = obj.applyDefaults(options);
        end

        function [img_info, files, pixSize] = getMetadata(obj)
            n = numel(obj.filenames);
            files(n) = struct();

            % Default pixSize (generic imread has no universal physical calibration)
            pixSize = struct('x', 1, 'y', 1, 'z', 1, 'units', 'um', 't', 1, 'tunits', 's');

            img_info = obj.createMetaContainer();

            for i = 1:n
                fn = obj.filenames{i};
                if exist(fn, 'file') ~= 2
                    error('io:Imread:FileNotFound', 'File not found: %s', fn);
                end

                info = imfinfo(fn);

                files(i).object_type = 'image';
                files(i).filename = fn;
                [~, ~, ext] = fileparts(fn);
                files(i).extension = lower(ext);

                % Handle pyramid selection: if "level" exists, use that page entry for metadata.
                % This mirrors how getImages.m uses files(i).level for imread(..., level). [file:2]
                level = [];
                if isfield(obj.options, 'level') && ~isempty(obj.options.level)
                    level = obj.options.level;
                elseif isfield(obj.options, 'BioFormatsIndices') && ~isempty(obj.options.BioFormatsIndices)
                    % Optional: reuse existing option naming if you already set it upstream
                    level = obj.options.BioFormatsIndices;
                end
                if ~isempty(level)
                    if level < 1 || level > numel(info)
                        error('io:Imread:BadLevel', ...
                            'Requested pyramid level/page %d out of range 1..%d for file: %s', level, numel(info), fn);
                    end
                    files(i).level = level;
                    infoSel = info(level);
                    files(i).levelMagScale = info(1).Width / infoSel.Width;
                else
                    infoSel = info(1);
                end

                files(i).height = infoSel.Height;
                files(i).width  = infoSel.Width;

                % NumberOfFrames/pages
                if ~isempty(level)
                    files(i).noLayers = 1;   % because we chose a single page/level
                else
                    files(i).noLayers = numel(info);
                end
                files(i).time = 1;

                % Determine color channels from ColorType
                if isfield(infoSel, 'ColorType') && ismember(lower(infoSel.ColorType), {'truecolor','ycbcr'})
                    files(i).color = 3;
                else
                    files(i).color = 1;
                end

                % Determine class from BitDepth (align with your existing logic)
                if isfield(infoSel, 'BitDepth')
                    switch infoSel.BitDepth
                        case {8, 24}
                            files(i).imgClass = 'uint8';
                        case {16, 48}
                            files(i).imgClass = 'uint16';
                        case {32, 96}
                            files(i).imgClass = 'uint32';
                        otherwise
                            files(i).imgClass = 'single';
                    end
                else
                    files(i).imgClass = 'uint8';
                end

                % Populate img_info from first file only (like your pipeline style)
                if i == 1
                    obj.addInfoToMeta(img_info, infoSel);
                    % Ensure required fields exist
                    if ~obj.hasKey(img_info, 'ImageDescription'); obj.setKey(img_info, 'ImageDescription', ''); end
                    obj.setKey(img_info, 'imgClass', files(i).imgClass);

                    % ColorType normalization (your getImages also enforces grayscale/truecolor at end) [file:2]
                    if isfield(infoSel, 'ColorType')
                        obj.setKey(img_info, 'ColorType', lower(infoSel.ColorType));
                    else
                        obj.setKey(img_info, 'ColorType', ternary(files(i).color == 1, 'grayscale', 'truecolor'));
                    end
                end
            end

            % Apply ROI/customSections to files struct if provided
            files = obj.applyRegionOptions(files);

            % Dimensions will be finalized after load (Height/Width/Depth), but
            % it is useful to set a preliminary estimate for callers that expect them early.
            obj.setKey(img_info, 'Height', max([files.height]));
            obj.setKey(img_info, 'Width',  max([files.width]));
            obj.setKey(img_info, 'Colors', max([files.color]));
            obj.setKey(img_info, 'Time',   1);
            obj.setKey(img_info, 'Depth',  sum([files.noLayers]));  % rough if zMin/zMax used
        end

        function [img, img_info] = getImages(obj, files, img_info)
            if nargin < 3 || isempty(img_info)
                img_info = obj.createMetaContainer();
            end

            % Preallocation strategy matches getImages.m: use max height/width/color/time and sum Z. [file:2]
            height = max([files.height]);
            width  = max([files.width]);
            color  = max([files.color]);
            time   = max([files.time]); %#ok<NASGU>

            maxZ = 0;
            if isfield(files, 'zMin')
                for i = 1:numel(files)
                    maxZ = maxZ + (files(i).zMax - files(i).zMin + 1);
                end
            else
                maxZ = sum([files.noLayers]);
            end

            imgClass = files(1).imgClass;
            if strcmp(imgClass, 'int16'); imgClass = 'uint16'; end

            if isfield(files, 'backgroundColor')
                img = zeros([height, width, color, maxZ, 1], imgClass) + files(1).backgroundColor;
            else
                img = zeros([height, width, color, maxZ, 1], imgClass);
            end

            layer_id = 1;

            for fn_index = 1:numel(files)
                maxY = min([height files(fn_index).height]);
                maxX = min([width  files(fn_index).width]);

                % If level is set, treat as single layer
                if isfield(files(fn_index), 'level') && files(fn_index).noLayers > 1
                    % we forced noLayers=1 in metadata, but just in case:
                    files(fn_index).noLayers = 1;
                end

                for subLayer = 1:files(fn_index).noLayers

                    % Z range selection (skip layers outside zMin/zMax), same behavior as getImages.m. [file:2]
                    if isfield(files, 'zMin') && files(fn_index).noLayers > 1
                        if subLayer < files(fn_index).zMin || subLayer > files(fn_index).zMax
                            continue;
                        end
                    end

                    I = obj.readFrame(files(fn_index), subLayer);

                    % Some formats may yield single-precision; your pipeline optionally rescales it
                    % using MaxSampleValue (if present). [file:2]
                    if isa(I, 'single') && obj.hasKey(img_info, 'MaxSampleValue')
                        ms = obj.getKey(img_info, 'MaxSampleValue');
                        try
                            I = bsxfun(@times, I, reshape(ms, 1, 1, []));
                        catch
                            % ignore if incompatible shape
                        end
                    end

                    % Normalize to [Y X C]
                    if ndims(I) == 2
                        I = reshape(I, size(I,1), size(I,2), 1);
                    end
                    maxC = min([color size(I,3)]);

                    img(1:maxY, 1:maxX, 1:maxC, layer_id, 1) = I(1:maxY, 1:maxX, 1:maxC);

                    layer_id = layer_id + 1;
                end
            end

            % Finalize metadata (mirrors end-of-getImages behavior) [file:2]
            obj.setKey(img_info, 'Height', height);
            obj.setKey(img_info, 'Width',  width);
            obj.setKey(img_info, 'Depth',  maxZ);
            obj.setKey(img_info, 'Time',   1);

            if obj.hasKey(img_info, 'ColorType')
                ct = obj.getKey(img_info, 'ColorType');
                if strcmpi(ct, 'indexed')
                    if ~obj.hasKey(img_info, 'Colormap') && obj.hasKey(img_info, 'ColorTable')
                        obj.setKey(img_info, 'Colormap', obj.getKey(img_info, 'ColorTable'));
                    end
                else
                    obj.setKey(img_info, 'ColorType', ternary(size(img,3)==1, 'grayscale', 'truecolor'));
                end
            else
                obj.setKey(img_info, 'ColorType', ternary(size(img,3)==1, 'grayscale', 'truecolor'));
            end

            if ~obj.hasKey(img_info, 'ImageDescription')
                obj.setKey(img_info, 'ImageDescription', '');
            end
        end
    end

    methods (Access = private)
        function I = readFrame(obj, fileRec, subLayer)
            % ROI load via PixelRegion matches getImages.m approach. [file:2]
            if ~isfield(fileRec, 'xMin')
                % no ROI
                if isfield(fileRec, 'level') && fileRec.noLayers == 1
                    I = imread(fileRec.filename, fileRec.level);
                else
                    if fileRec.noLayers == 1
                        I = imread(fileRec.filename);
                    else
                        I = imread(fileRec.filename, subLayer);
                    end
                end
            else
                pr = { ...
                    [fileRec.yMin fileRec.xyStep fileRec.yMax], ...
                    [fileRec.xMin fileRec.xyStep fileRec.xMax] ...
                };

                if fileRec.noLayers == 1
                    if isfield(fileRec, 'level')
                        I = imread(fileRec.filename, fileRec.level, 'PixelRegion', pr);
                    else
                        I = imread(fileRec.filename, 'PixelRegion', pr);
                    end
                else
                    I = imread(fileRec.filename, subLayer, 'PixelRegion', pr);
                end
            end
        end

        function files = applyRegionOptions(obj, files)
            % Apply ROI/customSections settings (if provided upstream).
            %
            % Expected fields:
            % options.customSectionsSettings.xMin/xMax/yMin/yMax/zMin/zMax/xyStep
            if isfield(obj.options, 'customSections') && obj.options.customSections && ...
               isfield(obj.options, 'customSectionsSettings') && isstruct(obj.options.customSectionsSettings)

                s = obj.options.customSectionsSettings;

                required = {'xMin','xMax','yMin','yMax','zMin','zMax','xyStep'};
                for k = 1:numel(required)
                    if ~isfield(s, required{k})
                        error('io:Imread:BadROI', 'Missing ROI field: %s', required{k});
                    end
                end

                for i = 1:numel(files)
                    files(i).xMin = s.xMin;
                    files(i).xMax = s.xMax;
                    files(i).yMin = s.yMin;
                    files(i).yMax = s.yMax;
                    files(i).zMin = s.zMin;
                    files(i).zMax = s.zMax;
                    files(i).xyStep = s.xyStep;
                end
            end
        end

        function options = applyDefaults(~, options)
            if ~isfield(options, 'customSections'); options.customSections = false; end
            if ~isfield(options, 'customSectionsSettings'); options.customSectionsSettings = struct(); end
            if ~isfield(options, 'level'); options.level = []; end
            if ~isfield(options, 'BioFormatsIndices'); options.BioFormatsIndices = []; end
        end

        function meta = createMetaContainer(~)
            % Use containers.Map by default for compatibility with existing code.
            % You can swap this to dictionary() if you standardize on R2022b+.
            meta = containers.Map('KeyType','char','ValueType','any');
        end

        function addInfoToMeta(obj, meta, infoSel)
            % Copy selected imfinfo fields into img_info (avoid huge arrays)
            f = fieldnames(infoSel);
            skip = {'StripOffsets','StripByteCounts','UnknownTags'};
            for i = 1:numel(f)
                if ismember(f{i}, skip); continue; end
                try
                    obj.setKey(meta, f{i}, infoSel.(f{i}));
                catch
                    % ignore non-storable
                end
            end
        end

        % ---- Map helpers (can be adapted later for dictionary) ----
        function tf = hasKey(~, meta, key)
            tf = isKey(meta, key);
        end
        function v = getKey(~, meta, key)
            v = meta(key);
        end
        function setKey(~, meta, key, value)
            meta(key) = value;
        end
    end
end

function out = ternary(cond, a, b)
    if cond; out = a; else; out = b; end
end
