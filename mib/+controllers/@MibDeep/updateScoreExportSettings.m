function updateScoreExportSettings(obj)
    % function updateScoreExportSettings(obj)
    % update export settings for score files

    global mibPath;

    prompts = {sprintf('Export exterior material')};
    defAns = {obj.ScoreExportOpt.IncludeExterior};
    dlgTitle = 'Export scores settings';
    
    options.WindowStyle = 'normal';
    options.Title = sprintf('Additional settings for export of score files\nOnly for Blocked-image engine'); 
    options.TitleLines = 2;                  

    answer = mibInputMultiDlg({mibPath}, prompts, defAns, dlgTitle, options);
    if isempty(answer); return; end
    obj.ScoreExportOpt.IncludeExterior = logical(answer{1});

    % % Precistion is not implemented yet

    % prompts = {...
    %     sprintf('Export precision:') ...
    %     sprintf('Export exterior material')};
    % 
    % defAns = {{'uint8', 'uint16', find(ismember({'uint8', 'uint16'}, obj.ScoreExportOpt.Precision))}; ...
    %            obj.ScoreExportOpt.IncludeExterior;};
    % dlgTitle = 'Export scores settings';
    % options.WindowStyle = 'normal';
    % %options.PromptLines = [1, 1];
    % options.WindowWidth = 1.0;
    % answer = mibInputMultiDlg({mibPath}, prompts, defAns, dlgTitle, options);
    % if isempty(answer); return; end
    % 
    % obj.ScoreExportOpt.Precision = answer{1};
    % obj.ScoreExportOpt.IncludeExterior = logical(answer{2});
end

