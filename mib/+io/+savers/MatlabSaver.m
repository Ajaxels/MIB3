classdef MatlabSaver < io.savers.BaseSaver
    % classdef MatlabSaver < io.savers.BaseSaver
    % Saver for MIB native MATLAB-based binary formats.
    %
    % Handles all native serialisation formats used by MIB:
    %
    %   'Matlab format (*.model)'            — MIB2/MIB3 native segmentation model.
    %       Variables saved: <modelVariable>, modelMaterialNames,
    %       modelMaterialColors, BoundingBox, modelVariable, modelType,
    %       [labelText, labelValue, labelPosition if annotations present]
    %
    %   'Matlab format 2D sequence (*.model)' — one .model file per Z-slice;
    %       useful for very large datasets where a full 3-D .model is too large.
    %
    %   'Matlab format for MIB ver. 1 (*.mat)' — legacy format for MIB v1
    %       compatibility.  Variables: <modelVariable>, material_list,
    %       color_list, bounding_box, model_var.
    %
    %   'Matlab categorical format (*.mibCat)' — saves labels as a MATLAB
    %       categorical array, 3-D stack or 2-D sequence.
    %       Variables: imgOut (categorical), imgVariable, options.
    %
    %   'Matlab format (*.mask)'             — binary mask in a MAT-file.
    %       Variable saved: maskImg (logical [H W D]).
    %
    % DATA DIMENSIONS
    %   Input data : [H, W, D, C, T]  — C=1 expected for all Matlab formats
    %                                    (labels/masks are always single channel)
    %
    % METADATA FIELDS USED
    %   .materialNames  — cell array of material name strings (labels formats)
    %   .materialColors — [M x 3] material RGB colours (labels formats)
    %   .labelsVariable — (char) variable name to use inside the .model file,
    %                     default 'mibModel'
    %   .modelType      — (integer) model type (e.g. 255, 63)
    %   .pixSize        — struct with voxel dimensions
    %   .boundingBox    — [xmin xmax ymin ymax zmin zmax]
    %   .annotations    — (optional) struct with .labelText, .labelValue,
    %                     .labelPosition from obj.annotations.getLabels()
    %
    % USAGE EXAMPLES
    %   @code
    %   %% 1. Save a segmentation model (MIB native format)
    %   saver = io.SaverFactory.create('Matlab format (*.model)');
    %
    %   opts.Format      = 'Matlab format (*.model)';
    %   opts.showWaitbar = true;
    %   opts.silent      = true;
    %   opts.overwrite   = true;
    %
    %   meta.filename       = 'myImage.tif';
    %   meta.materialNames  = {'Nucleus'; 'ER'; 'Mitochondria'};
    %   meta.materialColors = [0 0 1; 0 1 0; 1 0 0];  % R, G, B per material
    %   meta.labelsVariable = 'mibModel';
    %   meta.modelType      = 255;        % uint8 labels
    %   meta.dataClass      = 'uint8';
    %   meta.pixSize        = struct('x',0.065,'y',0.065,'z',0.2,'units','um','t',1,'tunits','s');
    %   meta.boundingBox    = [0 41.6 0 41.6 0 6];
    %
    %   labels = uint8(rand(256,256,30,1,1) * 3);  % values 0,1,2,3
    %   fnOut = saver.save(labels, meta, '/output/Labels_myImage.model', opts);
    %   @endcode
    %
    %   @code
    %   %% 2. Save mask in native MIB mask format
    %   saver = io.SaverFactory.create('Matlab format (*.mask)');
    %
    %   opts.Format      = 'Matlab format (*.mask)';
    %   opts.showWaitbar = false;
    %   opts.overwrite   = true;
    %
    %   meta.filename    = 'myImage.tif';
    %   meta.dataClass   = 'uint8';
    %   meta.pixSize     = struct('x',0.065,'y',0.065,'z',0.2,'units','um','t',1,'tunits','s');
    %
    %   mask = uint8(rand(256,256,30,1,1) > 0.8);  % binary mask
    %   fnOut = saver.save(mask, meta, '/output/Mask_myImage.mask', opts);
    %   @endcode
    %
    %   @code
    %   %% 3. Save as categorical format (for deep learning pipelines)
    %   saver = io.SaverFactory.create('Matlab categorical format (*.mibCat)');
    %
    %   opts.Format         = 'Matlab categorical format (*.mibCat)';
    %   opts.Saving3DPolicy = '3D stack';   % or '2D sequence'
    %   opts.FilenamePolicy = 'Use existing name';
    %   opts.showWaitbar    = false;
    %   opts.overwrite      = true;
    %
    %   meta.materialNames  = {'Exterior'; 'Nucleus'; 'Background'};
    %   meta.materialColors = [0.5 0.5 0.5; 0 0 1; 0 1 0];
    %   meta.labelsVariable = 'imgOut';
    %   meta.dataClass      = 'uint8';
    %   meta.modelType      = 255;
    %   meta.pixSize        = struct('x',0.065,'y',0.065,'z',0.2,'units','um','t',1,'tunits','s');
    %
    %   labels = uint8(rand(256,256,30,1,1) * 3);
    %   fnOut = saver.save(labels, meta, '/output/Labels.mibCat', opts);
    %   @endcode
    %
    %   @code
    %   %% 4. Via MibModel (recommended for GUI/batch workflows)
    %   BatchOpt.LayerType       = {'labels'};
    %   BatchOpt.Format          = {'Matlab format (*.model)'};
    %   BatchOpt.OutputDirectoryPolicy = {'Same as image'};
    %   BatchOpt.FilenamePolicy  = {'Use existing name'};
    %   BatchOpt.showWaitbar     = true;
    %   BatchOpt.mibBatchTooltip.LayerType = '';
    %   model.save('labels', [], BatchOpt);
    %   @endcode
    %
    % SEE ALSO
    %   io.SaverFactory, io.savers.BaseSaver,
    %   core.MibLabels.save, core.MibDataset.save, models.MibModel.save

    methods

        function obj = MatlabSaver(options)
            if nargin < 1; options = struct(); end
            obj.Options = options;
            obj.initBaseProps(options);
        end

        function formats = getSupportedFormats(~)
            formats = { ...
                'Matlab format (*.model)'; ...
                'Matlab format 2D sequence (*.model)'; ...
                'Matlab format for MIB ver. 1 (*.mat)'; ...
                'Matlab categorical format (*.mibCat)'; ...
                'Matlab format (*.mask)' };
        end

        function fnOut = save(obj, data, metadata, filename, options)
            % function fnOut = save(obj, data, metadata, filename, options)
            % Serialise data to one of the MIB MATLAB-native formats.
            %
            % The active format is selected by options.Format:
            %   'Matlab format (*.mask)'              → saveMask()
            %   'Matlab format (*.model)'             → saveModel3D()
            %   'Matlab format 2D sequence (*.model)' → saveModel2DSeq()
            %   'Matlab format for MIB ver. 1 (*.mat)'→ saveModelV1()
            %   'Matlab categorical format (*.mibCat)'→ saveModelCat()
            %
            % Parameters / Return values — see class-level docs above.

            fnOut = [];
            if ~isfield(options,'showWaitbar'); options.showWaitbar = true;  end
            if ~isfield(options,'silent');      options.silent      = false; end
            if ~isfield(options,'overwrite');   options.overwrite   = true;  end
            if ~isfield(options,'Format');      options.Format      = 'Matlab format (*.model)'; end

            switch options.Format
                case 'Matlab format (*.mask)'
                    fnOut = obj.saveMask(data, metadata, filename, options);
                case 'Matlab format (*.model)'
                    fnOut = obj.saveModel3D(data, metadata, filename, options);
                case 'Matlab format 2D sequence (*.model)'
                    fnOut = obj.saveModel2DSeq(data, metadata, filename, options);
                case 'Matlab format for MIB ver. 1 (*.mat)'
                    fnOut = obj.saveModelV1(data, metadata, filename, options);
                case 'Matlab categorical format (*.mibCat)'
                    fnOut = obj.saveModelCat(data, metadata, filename, options);
                otherwise
                    error('MatlabSaver:unknownFormat', ...
                        'Unsupported Matlab format: %s', options.Format);
            end
        end

    end  % public

    % ------------------------------------------------------------------ %
    methods (Access = private)

        function fnOut = saveMask(~, data, ~, filename, options)
            % Save binary mask as MAT-file (variable: maskImg).
            %
            % Uses save('-struct',...) to avoid eval() and dynamic variable
            % names.  The loaded file contains a top-level variable maskImg.
            fnOut = [];
            wb = [];
            if options.showWaitbar
                wb = obj.createProgressDialog('Saving mask', filename, false);
            end
            % Pack into struct so save('-struct') writes top-level variable
            vars.maskImg = logical(squeeze(data(:,:,:,1,1)));
            if ~isempty(wb); wb.Value = 0.4; end
            save(filename, '-struct', 'vars', '-v7.3');
            if ~isempty(wb); wb.Value = 1; delete(wb); end
            fnOut = filename;
            fprintf('MatlabSaver: mask saved → %s\n', filename);
        end

        function fnOut = saveModel3D(obj, data, metadata, filename, options)
            % Save full 3-D model in MIB2/MIB3 native .model format.
            %
            % Uses save('-struct', 'vars', ...) to store each variable
            % under its proper name without eval().
            %
            % Saved variables (top-level in the .model MAT-file):
            %   <labelsVariable>        — uint8/uint16 [H W D] label array
            %   modelMaterialNames      — cell array of material names
            %   modelMaterialColors     — [M x 3] RGB colours
            %   BoundingBox             — [xmin xmax ymin ymax zmin zmax]
            %   modelVariable           — char (= labelsVariable)
            %   modelType               — integer (255 for uint8 model)
            %   [labelText, labelValue, labelPosition — if .annotations present]
            fnOut = [];
            labVar = obj.getLabelsVariable(metadata);

            wb = [];
            if options.showWaitbar
                [~, fn, ex] = fileparts(filename);
                wb = obj.createProgressDialog('Saving model', sprintf('%s\n%s', fileparts(filename), [fn ex]), false);
            end

            % Build a struct whose fields become top-level MAT variables
            vars.(labVar)               = squeeze(data(:,:,:,1,1));
            vars.modelMaterialNames     = obj.getMaterialNames(metadata);
            vars.modelMaterialColors    = obj.getMaterialColors(metadata);
            vars.BoundingBox            = obj.getBoundingBox(metadata);
            vars.modelVariable          = labVar;
            vars.modelType              = obj.getModelType(metadata);

            if ~isempty(wb); wb.Value = 0.4; end

            if isfield(metadata,'annotations') && ~isempty(metadata.annotations)
                ann = metadata.annotations;
                vars.labelText     = ann.labelText;
                vars.labelValue    = ann.labelValue;
                vars.labelPosition = ann.labelPosition;
            end
            save(filename, '-struct', 'vars', '-mat', '-v7.3');

            if ~isempty(wb); wb.Value = 1; delete(wb); end
            fnOut = filename;
            fprintf('MatlabSaver: model saved → %s\n', filename);
        end

        function fnOut = saveModel2DSeq(obj, data, metadata, filename, options)
            % Save a 2-D sequence of .model files (one per Z-slice).
            %
            % Each slice uses save('-struct') so every field becomes a
            % separate top-level variable — same format as saveModel3D.
            fnOut = [];
            labVar = obj.getLabelsVariable(metadata);
            [pathStr, baseName, ext] = obj.splitFilename(filename);
            if isempty(ext); ext = '.model'; end
            if isempty(pathStr); pathStr = pwd; end

            nZ = size(data,3);
            sliceNames = obj.buildSliceNames(baseName, pathStr, nZ, ext, options, metadata);

            % Pre-compute shared variables
            sharedVars.modelMaterialNames  = obj.getMaterialNames(metadata);
            sharedVars.modelMaterialColors = obj.getMaterialColors(metadata);
            sharedVars.BoundingBox         = obj.getBoundingBox(metadata);
            sharedVars.modelVariable       = labVar;
            sharedVars.modelType           = obj.getModelType(metadata);

            hasAnnotations = isfield(metadata,'annotations') && ~isempty(metadata.annotations);
            if hasAnnotations
                ann = metadata.annotations;
                sharedVars.labelText     = ann.labelText;
                sharedVars.labelValue    = ann.labelValue;
                sharedVars.labelPosition = ann.labelPosition;
            end

            wb = [];
            if options.showWaitbar
                wb = obj.createProgressDialog('Saving model', 'Saving 2D model sequence...', false);
            end

            for z = 1:nZ
                vars          = sharedVars;
                vars.(labVar) = squeeze(data(:,:,z,1,1));
                save(sliceNames{z}, '-struct', 'vars', '-mat', '-v7.3');
                if ~isempty(wb); wb.Value = z/nZ; end
            end
            if ~isempty(wb); delete(wb); end
            fnOut = sliceNames;
            fprintf('MatlabSaver: 2D model sequence saved → %s\n', pathStr);
        end

        function fnOut = saveModelV1(obj, data, metadata, filename, options) %#ok<INUSD>
            % Save in legacy MIB v1 format (.mat) for backward compatibility.
            %
            % Variables (top-level): <labVar>, material_list, color_list,
            %                        bounding_box, model_var
            fnOut = [];
            labVar = obj.getLabelsVariable(metadata);

            vars.(labVar)         = squeeze(data(:,:,:,1,1));
            vars.material_list    = obj.getMaterialNames(metadata);
            vars.color_list       = obj.getMaterialColors(metadata);
            vars.bounding_box     = obj.getBoundingBox(metadata);
            vars.model_var        = labVar;

            if isfield(metadata,'annotations') && ~isempty(metadata.annotations)
                ann = metadata.annotations;
                vars.labelText     = ann.labelText;
                vars.labelPosition = ann.labelPosition;
            end
            save(filename, '-struct', 'vars', '-mat', '-v7.3');
            fnOut = filename;
            fprintf('MatlabSaver: MIB v1 model saved → %s\n', filename);
        end

        function fnOut = saveModelCat(obj, data, metadata, filename, options)
            % Save as MATLAB categorical array (.mibCat).
            %
            % The label volume is converted to a categorical with class names
            % derived from metadata.materialNames (prepended with 'Exterior'
            % for index 0 if not already present).
            %
            % options.Saving3DPolicy controls whether the output is a
            % single 3-D .mibCat file or a 2-D sequence.
            fnOut = [];
            if ~isfield(options,'Saving3DPolicy'); options.Saving3DPolicy = '3D stack'; end
            if ~isfield(options,'FilenamePolicy');  options.FilenamePolicy  = 'Use sequential filename'; end

            matNames = obj.getMaterialNames(metadata);
            % Prepend Exterior if not present
            if isempty(matNames) || ~strcmp(matNames{1}, 'Exterior')
                classNames = [{'Exterior'}; matNames(:)];
            else
                classNames = matNames(:);
            end

            % Build shared catOptions struct used in all slice saves
            catOptions.dimOrder            = 'yxczt';
            catOptions.modelType           = obj.getModelType(metadata);
            catOptions.modelMaterialColors = obj.getMaterialColors(metadata);
            catOptions.modelMaterialNames  = classNames;

            if strcmp(options.Saving3DPolicy, '3D stack')
                % Save full 3-D volume as a single .mibCat file.
                % Use save('-struct') to avoid eval() and dynamic variable names.
                % The loaded file contains: imgOut (categorical), imgVariable, catOptions.
                vars.imgOut      = categorical(squeeze(data(:,:,:,1,1)), ...
                    0:numel(classNames)-1, classNames);
                vars.imgVariable = 'imgOut';
                vars.catOptions  = catOptions;
                save(filename, '-struct', 'vars', '-mat', '-v7.3');
                fnOut = filename;
            else
                % 2-D sequence — one .mibCat per Z-slice
                [pathStr, baseName, ext] = obj.splitFilename(filename);
                if isempty(ext); ext = '.mibCat'; end
                nZ = size(data,3);
                sliceNames = obj.buildSliceNames(baseName, pathStr, nZ, ext, options, metadata);

                wb = [];
                if options.showWaitbar
                    wb = obj.createProgressDialog('Saving model', 'Saving categorical sequence...', false);
                end
                for z = 1:nZ
                    vars.imgOut      = categorical(squeeze(data(:,:,z,1,1)), ...
                        0:numel(classNames)-1, classNames);
                    vars.imgVariable = 'imgOut';
                    vars.catOptions  = catOptions;
                    save(sliceNames{z}, '-struct', 'vars', '-mat', '-v7.3');
                    if ~isempty(wb); wb.Value = z/nZ; end
                end
                if ~isempty(wb); delete(wb); end
                fnOut = sliceNames;
            end
            fprintf('MatlabSaver: categorical model saved → %s\n', filename);
        end

        % --- small metadata helpers ---

        function v = getLabelsVariable(~, metadata)
            if isfield(metadata,'labelsVariable') && ~isempty(metadata.labelsVariable)
                v = strrep(metadata.labelsVariable, '-', '_');
            else
                v = 'mibModel';
            end
        end

        function v = getMaterialNames(~, metadata)
            if isfield(metadata,'materialNames') && ~isempty(metadata.materialNames)
                v = metadata.materialNames(:);
            else
                v = {'Material 1'};
            end
        end

        function v = getMaterialColors(~, metadata)
            if isfield(metadata,'materialColors') && ~isempty(metadata.materialColors)
                v = metadata.materialColors;
            else
                v = rand(1,3);
            end
        end

        function v = getBoundingBox(~, metadata)
            if isfield(metadata,'boundingBox') && ~isempty(metadata.boundingBox)
                v = metadata.boundingBox;
            else
                v = [0 1 0 1 0 1];
            end
        end

        function v = getModelType(~, metadata)
            if isfield(metadata,'modelType') && ~isempty(metadata.modelType)
                v = metadata.modelType;
            elseif isfield(metadata,'dataClass')
                switch metadata.dataClass
                    case 'uint8';  v = 255;
                    case 'uint16'; v = 65535;
                    otherwise;     v = 255;
                end
            else
                v = 255;
            end
        end

    end  % private
end
