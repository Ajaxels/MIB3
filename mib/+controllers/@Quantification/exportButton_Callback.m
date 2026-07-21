function exportButton_Callback(obj, batchModeSwitch)
% EXPORTBUTTON_CALLBACK - Export quantification results to Excel, CSV, MAT file, or MATLAB workspace.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.exportButton_Callback()
%       obj.exportButton_Callback(batchModeSwitch)
%
% In interactive mode (batchModeSwitch = 0) shows a file-save dialog and
% lets the user choose the format.  
%
% Supported formats:
%   - Excel (``*.xls``) via xlswrite2 (in mib/external/)
%   - Comma-separated values (``*.csv``) via writecell / dlmwrite
%   - MATLAB struct (``*.mat``) — full or minimalistic (no PixelIdxList/BoundingBox)
%   - Export to MATLAB workspace via assignin
%
% Input Arguments:
%   - **batchModeSwitch** — *(optional)* logical; 1 = headless batch mode, skips dialogs; default 0
%

% Updates
%

if nargin < 2; batchModeSwitch = 0; end

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.Quantification.exportButton_Callback: triggered\n');
end

id = obj.mibModel.getActiveId();
dataset = obj.mibModel.I{id};
fn_out = dataset.image.filename;

if batchModeSwitch == 0
    choice = 'Save as...';
    if ~isdeployed
        choice = utils.dlgs.inputQuestDlg(obj.view.gui, 'Would you like to save results?', ...
            'Export', 'Save as...', 'Export to MATLAB', 'Cancel', 'Save as...');
        if strcmp(choice, 'Cancel'); return; end
    end

    filterIndex = 0;
    if strcmp(choice, 'Save as...')
        if isempty(fn_out)
            fn_out = obj.mibModel.currentDirectory;
        else
            [fn_out, name] = fileparts(fn_out);
            fn_out = fullfile(fn_out, [name '_analysis']);
        end
        [filename, Path, filterIndex] = uiputfile( ...
            {'*.xls',  'Excel format (*.xls)'; ...
             '*.csv',  'Comma-separated values (*.csv)'; ...
             '*.mat',  'MATLAB format (*.mat)'; ...
             '*.mat',  'MATLAB format minimalistic (*.mat)'; ...
             '*.*',    'All Files (*.*)'}, ...
            'Save as...', fn_out);
        if isequal(filename, 0); return; end
        [~, obj.BatchOpt.ExportFilename, Extension] = fileparts(filename);
        obj.BatchOpt.ExportResultsTo(1) = obj.BatchOpt.ExportResultsTo{2}(filterIndex + 2);
    else    % Export to MATLAB
        obj.BatchOpt.ExportResultsTo{1} = choice;
        answer = utils.dlgs.inputSingleDlg(obj.view.gui, ...
            {'Variable name for export:'}, {'MIB_stats'}, 'Export to MATLAB');
        if isempty(answer); return; end
        obj.BatchOpt.ExportFilename = answer;
    end
else
    filterIndex = find(ismember(obj.BatchOpt.ExportResultsTo{2}, obj.BatchOpt.ExportResultsTo{1}), 1) - 2;
    if isempty(fn_out)
        Path = obj.mibModel.currentDirectory;
    else
        Path = fileparts(fn_out);
    end
    if filterIndex > 0
        Extension = obj.BatchOpt.ExportResultsTo{1}(end-4:end-1);
    end
end

OPTIONS.frame         = obj.BatchOpt.DatasetType{1};
OPTIONS.mode          = obj.BatchOpt.ObjectShape{1};
OPTIONS.connectivity  = obj.BatchOpt.Connectivity{1};
OPTIONS.colorChannel1 = obj.BatchOpt.ColorChannel1{1};
OPTIONS.colorChannel2 = obj.BatchOpt.ColorChannel2{1};
OPTIONS.units         = obj.BatchOpt.Units{1};

if strcmp(obj.BatchOpt.MaterialIndex, '-1')
    OPTIONS.type = 'Mask';
elseif strcmp(obj.BatchOpt.MaterialIndex, '0')
    OPTIONS.type = 'Exterior';
else
    OPTIONS.type = 'Model';
end

OPTIONS.filename = dataset.image.filename;
if strcmp(OPTIONS.type, 'Mask')
    OPTIONS.mask_fn = dataset.labels.maskFilename;
elseif strcmp(OPTIONS.type, 'Exterior')
    OPTIONS.model_fn = dataset.labels.filename;
    OPTIONS.material_id = 'Exterior';
else
    OPTIONS.model_fn = dataset.labels.filename;
    if ~strcmp(obj.BatchOpt.MaterialIndex, '-2')
        matIdx = str2double(obj.BatchOpt.MaterialIndex);
        % For large models (maxMaterials >= 256) materialNames holds only two
        % placeholder entries while the selected index may be much larger, so
        % indexing into materialNames would exceed its bounds. In that case the
        % material name is simply the numeric index string itself.
        if dataset.labels.maxMaterials < 256 && ~isnan(matIdx) && ...
                matIdx >= 1 && matIdx <= numel(dataset.labels.materialNames)
            OPTIONS.material_id = sprintf('%s (%s)', obj.BatchOpt.MaterialIndex, dataset.labels.materialNames{matIdx});
        else
            OPTIONS.material_id = obj.BatchOpt.MaterialIndex;
        end
    else
        OPTIONS.material_id = 'Full model';
    end
end

if strcmp(OPTIONS.frame, '2D, Slice')
    OPTIONS.slicenumber = dataset.getCurrentSliceNumber();
else
    OPTIONS.slicenumber = 0;
end

curInt = get(0, 'DefaulttextInterpreter');
set(0, 'DefaulttextInterpreter', 'none');

% Resolve [F] filename template
templatePos = strfind(obj.BatchOpt.ExportFilename, '[');
if ~isempty(templatePos)
    [~, fn] = fileparts(dataset.image.sliceName('Filename'));
    exportFilenameLocal = sprintf('%s%s%s', ...
        obj.BatchOpt.ExportFilename(1:templatePos(1)-1), fn, ...
        obj.BatchOpt.ExportFilename(templatePos(1)+3:end));
else
    exportFilenameLocal = obj.BatchOpt.ExportFilename;
end

if strcmp(obj.BatchOpt.ExportResultsTo{1}, 'Export to MATLAB')
    % Sanitize the target variable name. In interactive mode the user types a
    % name (default 'MIB_stats'), but in batch mode ExportFilename keeps its
    % file-style default (e.g. '/img_analysis'), which is not a legal MATLAB
    % variable name and would make assignin throw — leaving no variable behind.
    varName = exportFilenameLocal;
    if ~isempty(varName) && (varName(1) == '/' || varName(1) == '\')
        varName = varName(2:end);   % drop leading path separator from file-style default
    end
    if isempty(varName)
        varName = 'MIB_stats';
    elseif ~isvarname(varName)
        varName = matlab.lang.makeValidName(varName);
    end
    STATSOUT = obj.STATS;
    STATSOUT(1).OPTIONS = OPTIONS;
    assignin('base', varName, STATSOUT);
    fprintf('"%s" structure with results was created in the MATLAB workspace\n', varName);
elseif ismember(obj.BatchOpt.ExportResultsTo{1}, obj.BatchOpt.ExportResultsTo{2}(3:6))
    if exportFilenameLocal(1) ~= filesep
        exportFilenameLocal = [filesep exportFilenameLocal];
    end
    fn = [Path, exportFilenameLocal, Extension];

    if obj.BatchOpt.showWaitbar && ~isempty(obj.view) && isvalid(obj.view.gui)
        wb = uiprogressdlg(obj.view.gui, 'Title', 'Saving results', ...
            'Message', sprintf('%s\nPlease wait...', fn), 'Indeterminate', 'on');
    end

    Path2 = fileparts(fn);
    if exist(Path2, 'dir') == 0; mkdir(Path2); end
    if exist(fn, 'file') == 2;  delete(fn); end

    % Build slice names for export
    if ~isempty(dataset.image.sliceName)
        snList = dataset.image.sliceName;
        if numel(snList) == dataset.image.depth
            sliceNames = snList;
        else
            sliceNames = repmat(snList, [dataset.image.depth, 1]);
        end
    else
        [~, snBase, snExt] = fileparts(dataset.image.filename);
        sliceNames = repmat({[snBase, snExt]}, [dataset.image.depth, 1]);
    end

    STATS = obj.STATS; %#ok<PROPLC>

    if filterIndex == 3 || filterIndex == 4    % MAT file
        centroidsMatrix = num2cell(cat(1, STATS.Centroid)); %#ok<PROPLC>
        zVectorArray = cell2mat(centroidsMatrix(:,3));
        [STATS.Filename] = deal(sliceNames(round(zVectorArray))); %#ok<PROPLC>
        if dataset.image.time == 1
            STATS = rmfield(STATS, 'TimePnt'); %#ok<PROPLC>
        end
        if filterIndex == 4
            STATS = rmfield(STATS, 'PixelIdxList'); %#ok<PROPLC>
            STATS = rmfield(STATS, 'BoundingBox');  %#ok<PROPLC>
        end
        warning('error', 'MATLAB:save:sizeTooBigForMATFile');
        try
            save(fn, 'OPTIONS', 'STATS', '-v7');
        catch
            save(fn, 'OPTIONS', 'STATS', '-v7.3');
        end
        warning('off', 'MATLAB:save:sizeTooBigForMATFile');

    elseif filterIndex == 1 || filterIndex == 2     % Excel or CSV
        warning('off', 'MATLAB:xlswrite:AddSheet');
        s = {'Quantification Results'};
        s(2,1) = {['Image filename: ' dataset.image.filename]};
        if strcmp(OPTIONS.type, 'Model') || strcmp(OPTIONS.type, 'Exterior')
            s(3,1) = {['Model filename: ' OPTIONS.model_fn]};
            s(3,9) = {OPTIONS.material_id};
        else
            if ~isnan(OPTIONS.mask_fn)
                s(3,1) = {['Mask filename: ' OPTIONS.mask_fn]};
            end
        end
        pixSize = dataset.image.pixSize;
        fieldNames = fieldnames(pixSize);
        s(4,1) = {'Pixel size and units:'};
        for field = 1:numel(fieldNames)
            s(4, field*2) = fieldNames(field);
            s(4, field*2+1) = {pixSize.(fieldNames{field})};
        end
        s(5,1) = {sprintf('CALCULATED IN %s', upper(obj.BatchOpt.Units{1}))};
        if ~strcmp(OPTIONS.units, 'pixels') && strcmp(OPTIONS.mode, 'Shape3D') && pixSize.x ~= pixSize.z
            s(5,6) = {sprintf('ATTENTION: some 3D parameters require ISOTROPIC pixels!')};
        end

        start = 9;
        s(7,1) = {'Results:'};
        s(8,1) = {'Index'}; s(8,2) = {'ObjID'}; s(8,3) = {'Filename'};
        s(8,5) = {'Centroid px'}; s(9,4) = {'X'}; s(9,5) = {'Y'}; s(9,6) = {'Z'};
        s(8,7) = {'TimePnt'};

        noObj = numel(STATS);
        s(start+1:start+noObj, 1) = num2cell(1:noObj);
        s(start+1:start+noObj, 2) = num2cell(cat(1, STATS.ObjectId));
        centroidsMatrix = num2cell(cat(1, STATS.Centroid));
        zVectorArray = ceil(cell2mat(centroidsMatrix(:,3)));
        s(start+1:start+noObj, 3) = sliceNames(round(zVectorArray));
        s(start+1:start+noObj, 4:6) = centroidsMatrix;
        s(start+1:start+noObj, 7) = num2cell(cat(1, STATS.TimePnt));

        STATS = rmfield(STATS, {'Centroid','PixelIdxList','TimePnt','BoundingBox'}); %#ok<PROPLC>
        fieldNames = fieldnames(STATS);
        fieldNamesForTitles = fieldNames;
        correlationId = find(ismember(fieldNamesForTitles, 'Correlation'), 1);
        if ~isempty(correlationId)
            fieldNamesForTitles{correlationId} = sprintf('Correlation %s/%s', OPTIONS.colorChannel1, OPTIONS.colorChannel2);
        end
        s(8, 8:7+numel(fieldNames)) = fieldNamesForTitles';
        for fIdx = 1:numel(fieldNames)
            s(start+1:start+noObj, 7+fIdx) = num2cell(cat(1, STATS.(fieldNames{fIdx})));
        end

        if filterIndex == 1
            xlswrite2(fn, s, 'Sheet1', 'A1');
        else
            if verLessThan('MATLAB', '9.6')
                fid = fopen(fn, 'w');
                for i = 1:start
                    for j = 1:5+numel(fieldNames)
                        if isfield(s, '') || (i <= size(s,1) && j <= size(s,2) && ~isempty(s{i,j}))
                            fprintf(fid, '%s,', num2str(s{i,j}));
                        else
                            fprintf(fid, ',');
                        end
                    end
                    fprintf(fid, '\n');
                end
                fclose(fid);
                dlmwrite(fn, cell2mat(s(start+1:end,:)), 'delimiter', ',', '-append'); %#ok<DLMWT>
            else
                writecell(s, fn);
            end
        end
    end

    if obj.BatchOpt.showWaitbar && exist('wb','var'); delete(wb); end
    fprintf('MIB: statistics saved to %s\n', fn);
end
set(0, 'DefaulttextInterpreter', curInt);
end
