function saveProtocol(obj)
% SAVEPROTOCOL - save the current protocol to a .mibProtocol (MAT) or .xls file via a dialog.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.saveProtocol()
%
% Usage:
%   Example 1::
%
%     obj.saveProtocol();
%

if isempty(obj.Protocol); return; end

fn_out = obj.mibModel.I{obj.mibModel.id}.image.filename;
dotIndex = strfind(fn_out,'.');
if ~isempty(dotIndex); fn_out = fn_out(1:dotIndex-1); end
if isempty(strfind(fn_out,'/')) && isempty(strfind(fn_out,'\')) %#ok<STREMP>
    fn_out = fullfile(obj.mibModel.currentDirectory, fn_out);
end
if isempty(fn_out); fn_out = obj.mibModel.currentDirectory; end

Filters = {'*.mibProtocol',  'Matlab format (*.mibProtocol)';...
    '*.xls',   'Excel format (*.xls)'; };

[filename, path, FilterIndex] = uiputfile(Filters, 'Save protocol...', fn_out);
if isequal(filename,0); return; end % check for cancel
fn_out = fullfile(path, filename);

switch Filters{FilterIndex,2}
    case 'Matlab format (*.mibProtocol)'
        Protocol = obj.Protocol; %#ok<PROP>
        save(fn_out, 'Protocol', '-mat', '-v7');
    case 'Excel format (*.xls)'
        warning('off', 'MATLAB:xlswrite:AddSheet');
        wb = uiprogressdlg(obj.view.gui, 'Title', 'Saving to Excel', 'Message', 'Please wait...', 'Value', 0);
        % Sheet 1
        s = {sprintf('MIB protocol file: %s', fn_out)};
        s(3,1) = {'Step'}; s(3,2) = {'Section name'}; s(3,3) = {'Action name'}; s(3,4) = {'Command'};
        s(3,5) = {'Parameter name'}; s(3,6) = {'Parameter value'};
        lineIndex = 4;
        for protId = 1:numel(obj.Protocol)
            s(lineIndex,1) = {sprintf('%d', protId)};
            s(lineIndex,2) = {obj.Protocol(protId).mibBatchSectionName};
            s(lineIndex,3) = {obj.Protocol(protId).mibBatchActionName};
            s(lineIndex,4) = {obj.Protocol(protId).Command};
            fieldNames = fieldnames(obj.Protocol(protId).Batch);
            for i=1:numel(fieldNames)
                s(lineIndex,5) = fieldNames(i);
                if isstruct(obj.Protocol(protId).Batch.(fieldNames{i}))
                    continue;
                elseif iscell(obj.Protocol(protId).Batch.(fieldNames{i}))
                    s(lineIndex,6) = {obj.Protocol(protId).Batch.(fieldNames{i}){1}};
                else
                    s(lineIndex,6) = {obj.Protocol(protId).Batch.(fieldNames{i})};
                end
                lineIndex = lineIndex + 1;
            end
            if isempty(fieldNames); lineIndex = lineIndex + 1; end  % to fix position for the STOP EXECUTION
        end
        wb.Value = 0.2;
        warning('off','MATLAB:COM:invalidargumenttype');    % switch off warnings
        xlswrite2(fn_out, s, 'Protocol');
        wb.Value = 1;
        close(wb);
end
fprintf('mib: protocol was saved to "%s"\n', fn_out);
end
