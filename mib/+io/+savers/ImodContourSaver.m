classdef ImodContourSaver < io.savers.BaseSaver
    % classdef ImodContourSaver < io.savers.BaseSaver
    % Saver for IMOD contour model format output (*.mod files).
    %
    % Handles one format:
    %   'Contours for IMOD (*.mod)' — writes an IMOD binary model (.mod)
    %       containing one object per segmentation material.  Each object
    %       holds the contours (closed polygons) extracted from the label
    %       volume at each Z-slice.
    %
    % This saver is labels-only.  It is intended for workflows where
    % segmentation results from MIB3 are reviewed, refined, or processed
    % further using IMOD's 3dmod application.
    %
    % The saver delegates to the legacy helper mibExportModelToImodModel(),
    % which is ported from MIB2.
    %
    % DATA DIMENSIONS
    %   Input  data   : [H, W, D, C, T]  (MIB3 native order)
    %   mibExportModelToImodModel() expects [H, W, D] — squeezed from data.
    %
    % SAVING OPTIONS PASSED TO mibExportModelToImodModel
    %   savingOptions.modelFilename      — full output path for the .mod file
    %   savingOptions.pixSize            — struct {.x .y .z .units .t .tunits}
    %   savingOptions.xyScaleFactor      — (double) scale factor applied to XY
    %                                       pixel size when building contours;
    %                                       default 5 in silent mode
    %   savingOptions.zScaleFactor       — (double) scale factor applied to Z
    %                                       spacing; default 1 in silent mode
    %   savingOptions.colorList          — [M x 3] material RGB colours (0..1)
    %   savingOptions.ModelMaterialNames — cell array of material name strings
    %   savingOptions.showWaitbar        — logical
    %   savingOptions.generateSelectionSw — logical, default false in silent mode
    %
    % TODO: port mibExportModelToImodModel from
    %   MIB2_RENAMED_FOR_MIB3/ImportExportTools/IMOD/mibExportModelToImodModel.m
    %   to mib/+io/+IMOD/mibExportModelToImodModel.m
    %
    % USAGE EXAMPLES
    %   @code
    %   %% 1. Export segmentation contours to IMOD .mod file
    %   saver = io.SaverFactory.create('Contours for IMOD (*.mod)');
    %
    %   opts.Format         = 'Contours for IMOD (*.mod)';
    %   opts.showWaitbar    = false;
    %   opts.silent         = true;
    %   opts.overwrite      = true;
    %   opts.layerType      = 'labels';
    %   opts.xyScaleFactor  = 5;
    %   opts.zScaleFactor   = 1;
    %
    %   meta.filename       = 'source_tomo.tif';
    %   meta.pixSize        = struct('x',0.35,'y',0.35,'z',1.4, ...
    %                                'units','nm','t',1,'tunits','s');
    %   meta.materialNames  = {'Ribosome'; 'Membrane'; 'Nucleus'};
    %   meta.materialColors = [1 0 0; 0 1 0; 0 0 1];
    %
    %   labels = uint8(rand(512,512,200,1,1)*3);  % [H W D C T]
    %   fnOut = saver.save(labels, meta, '/output/Model_tomo.mod', opts);
    %   fprintf('Saved: %s\n', fnOut);
    %   @endcode
    %
    %   @code
    %   %% 2. Via MibModel batch — export contours for IMOD annotation review
    %   BatchOpt.LayerType       = {'labels'};
    %   BatchOpt.Format          = {'Contours for IMOD (*.mod)'};
    %   BatchOpt.OutputDirectoryPolicy = {'Full path'};
    %   BatchOpt.DestinationDirectory  = '/output/imod';
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

        function obj = ImodContourSaver(options)
            % function obj = ImodContourSaver(options)
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
            % Return format strings handled by ImodContourSaver.
            formats = {'Contours for IMOD (*.mod)'};
        end

        function fnOut = save(obj, data, metadata, filename, options)
            % function fnOut = save(obj, data, metadata, filename, options)
            % Write labels data as an IMOD contour model (.mod) file.
            %
            % Parameters:
            %   data     — [H, W, D, C, T] numeric label array.
            %              Only the first channel (C=1) and first time point
            %              (T=1) are used.
            %   metadata — struct; used fields:
            %     .pixSize        — struct {.x .y .z .units .t .tunits}
            %     .materialNames  — cell array of material name strings
            %     .materialColors — [M x 3] material RGB colours (0..1)
            %   filename — full output path, e.g. '/out/Model_tomo.mod'
            %   options  — struct; used fields:
            %     .Format              — format string
            %     .layerType           — expected 'labels'; warning if not
            %     .xyScaleFactor       — (double) XY contour scale factor
            %                            (default 5 in silent mode)
            %     .zScaleFactor        — (double) Z scale factor (default 1)
            %     .generateSelectionSw — (logical) generate selection object
            %                            (default false in silent mode)
            %     .showWaitbar         — logical
            %     .silent              — logical, suppress dialogs
            %     .overwrite           — logical
            %
            % Return values:
            %   fnOut — (char) path of saved .mod file, [] on failure
            %
            % Example — see class-level documentation above.

            fnOut = [];

            % --- defaults ---
            if ~isfield(options, 'showWaitbar');          options.showWaitbar          = true;   end
            if ~isfield(options, 'silent');               options.silent               = false;  end
            if ~isfield(options, 'overwrite');            options.overwrite            = true;   end
            if ~isfield(options, 'layerType');            options.layerType            = 'labels'; end
            if ~isfield(options, 'xyScaleFactor');        options.xyScaleFactor        = 5;      end
            if ~isfield(options, 'zScaleFactor');         options.zScaleFactor         = 1;      end
            if ~isfield(options, 'generateSelectionSw');  options.generateSelectionSw  = false;  end

            % --- interactive dialog (skipped in silent/batch mode) ---
            if ~options.silent
                prompts  = {'Take each Nth point in contours (> 0):', 'Show detected points in the selection layer'};
                defAns   = {num2str(options.xyScaleFactor), options.generateSelectionSw};
                dlgTitle = 'Export to IMOD';
                answer = utils.dlgs.inputUniversalDlg(obj.ParentFigure, '', prompts, defAns, dlgTitle);
                if isempty(answer); return; end
                options.xyScaleFactor       = str2double(answer{1});
                options.generateSelectionSw = answer{2};
            end

            % Warn if caller has incorrectly specified an image layer
            if ~strcmpi(options.layerType, 'labels') && ~strcmpi(options.layerType, 'mask')
                warning('ImodContourSaver:wrongLayerType', ...
                    'ImodContourSaver is designed for labels/mask layers; got ''%s''.', ...
                    options.layerType);
            end

            % --- decompose filename ---
            [pathStr, baseName, ext] = obj.splitFilename(filename);
            if isempty(ext); ext = '.mod'; end
            if isempty(pathStr); pathStr = pwd; end
            if exist(pathStr, 'dir') ~= 7; mkdir(pathStr); end
            modelFilename = fullfile(pathStr, [baseName ext]);

            % Squeeze to [H, W, D]
            model_hwd = squeeze(data(:, :, :, 1, 1));

            % --- build savingOptions for mibExportModelToImodModel ---
            savingOptions.modelFilename       = modelFilename;
            savingOptions.showWaitbar         = options.showWaitbar;
            savingOptions.overwrite           = options.overwrite;
            savingOptions.xyScaleFactor       = options.xyScaleFactor;
            savingOptions.zScaleFactor        = options.zScaleFactor;
            savingOptions.generateSelectionSw = options.generateSelectionSw;
            savingOptions.ParentFigure        = obj.ParentFigure;

            if isfield(metadata, 'pixSize') && ~isempty(metadata.pixSize)
                savingOptions.pixSize = metadata.pixSize;
            else
                savingOptions.pixSize = struct('x',1,'y',1,'z',1, ...
                    'units','nm','t',1,'tunits','s');
            end

            if isfield(metadata, 'materialColors') && ~isempty(metadata.materialColors)
                savingOptions.colorList = metadata.materialColors;
            else
                savingOptions.colorList = rand(1, 3);
            end

            if isfield(metadata, 'materialNames') && ~isempty(metadata.materialNames)
                savingOptions.ModelMaterialNames = metadata.materialNames;
            else
                savingOptions.ModelMaterialNames = {'Material 1'};
            end

            % --- call legacy mibExportModelToImodModel ---
            % TODO: port mibExportModelToImodModel from
            %   MIB2_RENAMED_FOR_MIB3/ImportExportTools/IMOD/mibExportModelToImodModel.m
            %   to mib/+io/+IMOD/mibExportModelToImodModel.m
            try
                io.IMOD.mibExportModelToImodModel(model_hwd, savingOptions);
            catch ME
                error('ImodContourSaver:missingHelper', ...
                    ['mibExportModelToImodModel() is not yet available.\n' ...
                     'Please port it from:\n' ...
                     '  MIB2_RENAMED_FOR_MIB3/ImportExportTools/IMOD/mibExportModelToImodModel.m\n' ...
                     'to:\n' ...
                     '  mib/+io/+IMOD/mibExportModelToImodModel.m\n\n' ...
                     'Original error: %s'], ME.message);
            end

            fnOut = modelFilename;
            fprintf('ImodContourSaver: saved → %s\n', modelFilename);
        end

    end
end
