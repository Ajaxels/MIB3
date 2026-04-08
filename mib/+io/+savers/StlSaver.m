classdef StlSaver < io.savers.BaseSaver
    % classdef StlSaver < io.savers.BaseSaver
    % Saver for binary STL (Stereolithography) isosurface mesh output.
    %
    % Handles one format:
    %   'STL isosurface as binary (*.stl)' — one binary STL file per
    %       material, e.g. 'Labels_stack_Nucleus.stl', 'Labels_stack_ER.stl'
    %
    % This saver is labels-only.  It extracts a triangular isosurface mesh
    % for each segmentation material using mibRenderModel(), optionally
    % reducing (isosurface decimation) and smoothing the mesh, then writes
    % each surface to a separate binary STL file using stlwrite().
    %
    % The result is a set of STL files suitable for visualisation in Blender,
    % Paraview, or 3-D printing pipelines.
    %
    % The saver delegates mesh generation to utils.isosurfaceMibRendering(),
    % which is ported and refactored from MIB2's mibRenderModel.
    %
    % DATA DIMENSIONS
    %   Input  data : [H, W, D, C, T]  (MIB3 native order)
    %   mibRenderModel() expects [H, W, D] — squeezed from data(:,:,:,1,1).
    %
    % OUTPUT FILENAMES
    %   Each material is written to:
    %     <fnBase>_<materialName>.stl
    %   where fnBase is the output path without extension, e.g.:
    %     /output/Labels_myStack_Nucleus.stl
    %     /output/Labels_myStack_ER.stl
    %
    % MESH GENERATION OPTIONS (passed inside savingOptions to mibRenderModel)
    %   savingOptions.reduce    — face-count reduction target (0 = no reduction;
    %                             default 500 if image width > 500, else 0)
    %   savingOptions.smooth    — number of Laplacian smoothing iterations
    %                             (default 5)
    %   savingOptions.maxFaces  — maximum face count per surface (default 300000)
    %   savingOptions.slice     — (logical) 0 = full 3-D surface (default)
    %
    % MATERIAL SELECTION
    %   options.MaterialIndex   — [] = all materials (default)
    %                             scalar = index of a single material to export
    %
    %
    % USAGE EXAMPLES
    %   @code
    %   %% 1. Export all materials as STL for Blender / 3-D printing
    %   saver = io.SaverFactory.create('STL isosurface as binary (*.stl)');
    %
    %   opts.Format         = 'STL isosurface as binary (*.stl)';
    %   opts.showWaitbar    = false;
    %   opts.silent         = true;
    %   opts.overwrite      = true;
    %   opts.layerType      = 'labels';
    %   opts.MaterialIndex  = [];     % [] = export all materials
    %   opts.reduce         = 500;    % decimate to 500 faces
    %   opts.smooth         = 5;      % 5 smoothing iterations
    %   opts.maxFaces       = 300000;
    %   opts.slice          = 0;
    %
    %   meta.filename       = 'source_stack.tif';
    %   meta.pixSize        = struct('x',0.065,'y',0.065,'z',0.2, ...
    %                                'units','um','t',1,'tunits','s');
    %   meta.boundingBox    = [0 33.3 0 33.3 0 10];
    %   meta.materialNames  = {'Nucleus'; 'ER'; 'Mitochondria'};
    %   meta.materialColors = [0 0 1; 0 1 0; 1 0 0];
    %
    %   labels = uint8(rand(512,512,50,1,1)*3);  % [H W D C T]
    %   fnOut = saver.save(labels, meta, '/output/Labels_myStack.stl', opts);
    %   % Creates: /output/Labels_myStack_Nucleus.stl
    %   %          /output/Labels_myStack_ER.stl
    %   %          /output/Labels_myStack_Mitochondria.stl
    %   @endcode
    %
    %   @code
    %   %% 2. Export only the second material (index 2)
    %   opts.MaterialIndex = 2;
    %   fnOut = saver.save(labels, meta, '/output/Labels_myStack.stl', opts);
    %   % Creates: /output/Labels_myStack_ER.stl
    %   @endcode
    %
    %   @code
    %   %% 3. Via MibModel batch
    %   BatchOpt.LayerType       = {'labels'};
    %   BatchOpt.Format          = {'STL isosurface as binary (*.stl)'};
    %   BatchOpt.OutputDirectoryPolicy = {'Full path'};
    %   BatchOpt.DestinationDirectory  = '/output/stl';
    %   BatchOpt.FilenamePolicy  = {'Use existing name'};
    %   BatchOpt.showWaitbar     = false;
    %   BatchOpt.mibBatchTooltip.LayerType = '';
    %   model.save('labels', [], BatchOpt);
    %   @endcode
    %
    % SEE ALSO
    %   io.SaverFactory, io.savers.BaseSaver, io.savers.MrcSaver,
    %   core.MibDataset.save, models.MibModel.save

    methods

        function obj = StlSaver(options)
            % function obj = StlSaver(options)
            % Constructor — accepts an optional options struct.
            %
            % Parameters:
            %   options — (struct, optional) saver-level options (usually empty;
            %             per-save options are passed to save() instead)
            if nargin < 1; options = struct(); end
            obj.Options = options;
            obj.initBaseProps(options);
        end

        function formats = getSupportedFormats(~)
            % function formats = getSupportedFormats(~)
            % Return format strings handled by StlSaver.
            formats = {'STL isosurface as binary (*.stl)'};
        end

        function fnOut = save(obj, data, metadata, filename, options)
            % function fnOut = save(obj, data, metadata, filename, options)
            % Write labels data as binary STL isosurface mesh files.
            %
            % One STL file is produced per material (or one file if
            % options.MaterialIndex is a scalar).  File names follow the
            % pattern: <fnBase>_<materialName>.stl
            %
            % Parameters:
            %   data     — [H, W, D, C, T] numeric label array.
            %              Only the first channel (C=1) and first time point
            %              (T=1) are processed.
            %   metadata — struct; used fields:
            %     .pixSize        — struct {.x .y .z .units .t .tunits}
            %     .boundingBox    — [xmin xmax ymin ymax zmin zmax]
            %     .materialNames  — cell array of material name strings
            %     .materialColors — [M x 3] material RGB colours (0..1)
            %   filename — full output path template, e.g.
            %              '/out/Labels_myStack.stl'
            %   options  — struct; used fields:
            %     .Format         — format string
            %     .layerType      — expected 'labels'; warning if not
            %     .MaterialIndex  — [] = all materials (default),
            %                       scalar = index of specific material
            %     .reduce         — (double) face reduction target;
            %                       default 500 if width > 500 else 0
            %     .smooth         — (integer) smoothing iterations (default 5)
            %     .maxFaces       — (integer) max faces per mesh (default 300000)
            %     .slice          — (logical) 0 = full 3-D mesh (default 0)
            %     .showWaitbar    — logical
            %     .silent         — logical, suppress dialogs
            %     .overwrite      — logical
            %
            % Return values:
            %   fnOut — (cell of char) paths of all saved .stl files,
            %           or single char when only one material is exported.
            %           Returns [] on failure.
            %
            % Example — see class-level documentation above.

            fnOut = [];

            % --- defaults ---
            if ~isfield(options, 'showWaitbar');   options.showWaitbar  = true;   end
            if ~isfield(options, 'silent');        options.silent       = false;  end
            if ~isfield(options, 'overwrite');     options.overwrite    = true;   end
            if ~isfield(options, 'layerType');     options.layerType    = 'labels'; end
            if ~isfield(options, 'MaterialIndex'); options.MaterialIndex = [];    end
            if ~isfield(options, 'smooth');        options.smooth       = 5;      end
            if ~isfield(options, 'maxFaces');      options.maxFaces     = 300000; end

            % Warn if caller has incorrectly specified an image layer
            if ~strcmpi(options.layerType, 'labels') && ~strcmpi(options.layerType, 'mask')
                warning('StlSaver:wrongLayerType', ...
                    'StlSaver is designed for labels/mask layers; got ''%s''.', ...
                    options.layerType);
            end

            % --- decompose filename ---
            [pathStr, baseName, ext] = obj.splitFilename(filename);
            if isempty(ext); ext = '.stl'; end
            if isempty(pathStr); pathStr = pwd; end
            if exist(pathStr, 'dir') ~= 7; mkdir(pathStr); end
            fnBase = fullfile(pathStr, baseName);

            % --- default reduce: 500 if image width > 500, else 0 ---
            nW = size(data, 2);
            if ~isfield(options, 'reduce')
                options.reduce = 500 * (nW > 500);
            end

            % --- interactive dialog (skipped in silent/batch mode) ---
            if ~options.silent
                dlgOpt.mibPath = obj.mibPath;
                dlgOpt.windowHeight = 190;
                prompts = { ...
                    'Reduce volume to width (px) [0 = no reduction]:'; ...
                    'Smoothing kernel width (px) [0 = no smoothing]:'; ...
                    'Max faces per mesh [0 = no limit]:'};
                defAns = { ...
                    num2str(options.reduce); ...
                    num2str(options.smooth); ...
                    num2str(options.maxFaces)};
                answer = utils.dlgs.inputUniversalDlg(obj.ParentFigure, '', prompts, defAns, ...
                    'Isosurface parameters', dlgOpt);
                if isempty(answer); return; end
                options.reduce   = str2double(answer{1});
                options.smooth   = str2double(answer{2});
                options.maxFaces = str2double(answer{3});
            end

            % Squeeze to [H, W, D]
            model_hwd = squeeze(data(:, :, :, 1, 1));

            % --- pixel size and bounding box ---
            if isfield(metadata, 'pixSize') && ~isempty(metadata.pixSize)
                pixSize = metadata.pixSize;
            else
                pixSize = struct('x',1,'y',1,'z',1,'units','um','t',1,'tunits','s');
            end

            if isfield(metadata, 'boundingBox') && ~isempty(metadata.boundingBox)
                boundingBox = metadata.boundingBox;
            else
                boundingBox = zeros(1, 6);
            end

            % --- material list ---
            if isfield(metadata, 'materialColors') && ~isempty(metadata.materialColors)
                materialColors = metadata.materialColors;
            else
                materialColors = rand(double(max(model_hwd(:))), 3);
            end

            if isfield(metadata, 'materialNames') && ~isempty(metadata.materialNames)
                materialNames = metadata.materialNames;
            else
                materialNames = arrayfun(@(i) sprintf('Material %d', i), ...
                    1:size(materialColors,1), 'UniformOutput', false);
            end

            % --- determine which materials to export ---
            nMaterials = numel(materialNames);
            if isempty(options.MaterialIndex)
                materialIndices = 1:nMaterials;
            else
                materialIndices = options.MaterialIndex(:)';
            end

            % --- mesh generation options ---
            meshOpts.reduce        = options.reduce;
            meshOpts.smooth        = options.smooth;
            meshOpts.maxFaces      = options.maxFaces;
            meshOpts.showRendering = ~options.silent;

            % --- waitbar ---
            wb = [];
            if options.showWaitbar && numel(materialIndices) > 1
                wb = obj.createProgressDialog('Saving images...', 'Rendering and saving STL meshes...', false);
            end

            allFn = {};

            try
                for k = 1:numel(materialIndices)
                    matIdx = materialIndices(k);

                    if matIdx < 1 || matIdx > nMaterials
                        warning('StlSaver:invalidMaterialIndex', ...
                            'Material index %d is out of range [1..%d]; skipping.', ...
                            matIdx, nMaterials);
                        continue;
                    end

                    matName  = materialNames{matIdx};
                    matColor = materialColors(matIdx, :);  % [1 x 3], values 0..1

                    % Build output filename for this material
                    % Sanitise material name for use in a filename
                    safeName = regexprep(matName, '[^a-zA-Z0-9_\-]', '_');
                    stlFile  = sprintf('%s_%s%s', fnBase, safeName, ext);

                    % --- generate isosurface mesh (+ optional rendering) ---
                    meshOpts.matColor      = matColor;
                    meshOpts.initFigure    = (k == 1);
                    meshOpts.finalizeFigure = (k == numel(materialIndices));
                    fv = utils.isosurfaceMibRendering(model_hwd, matIdx, pixSize, ...
                        boundingBox, meshOpts);

                    % Skip empty surfaces
                    if isempty(fv) || isempty(fv.faces) || isempty(fv.vertices)
                        warning('StlSaver:emptyMesh', ...
                            'Material ''%s'' produced an empty mesh; skipping.', matName);
                        continue;
                    end

                    % Write binary STL (MATLAB R2019b+ requires triangulation object)
                    TR = triangulation(fv.faces, fv.vertices);
                    stlwrite(TR, stlFile);

                    allFn{end+1} = stlFile; %#ok<AGROW>
                    fprintf('StlSaver:  material ''%s'' → %s\n', matName, stlFile);

                    if ~isempty(wb); wb.Value = k/numel(materialIndices); end
                end
            catch ME
                if ~isempty(wb); delete(wb); end
                rethrow(ME);
            end
            if ~isempty(wb); delete(wb); end

            if isempty(allFn)
                warning('StlSaver:nothingSaved', 'No STL files were produced.');
                return;
            end

            fprintf('StlSaver: saved %d file(s) → %s\n', numel(allFn), pathStr);
            if isscalar(allFn)
                fnOut = allFn{1};
            else
                fnOut = allFn(:);
            end
        end

    end
end
