function makeMlapp(sourceFile, targetFile)
% Build an App Designer .mlapp from a class file in App Designer's generated-code form.
%
% Each "% Create <Name>" block of createComponents becomes one component: the block's lines
% are executed to build the real component, and stored as its DesignTimeProperties
% .ComponentCode template (app.ad_CODENAME_ad / app.ad_PARENTCODENAME_ad), which is how
% App Designer keeps components in appModel.mat. Callbacks, the startup function and the
% editable properties block are written to the code section.
%
% Uses undocumented App Designer internals of R2026a
% (appdesigner.internal.serialization.MLAPPSerializer); may break in later releases. Check a
% result by loading it with
% appdesigner.internal.serialization.SerializationFactory.createDeserializer(file).getAppData()
% and by opening it in App Designer.
%
% Example (from the MIB3 folder):
%   makeMlapp('development\sharpness\ImageSharpnessGUI.m', 'mib\+views\ImageSharpnessGUI.mlapp')

sourceText = string(fileread(sourceFile));
sourceLines = splitlines(sourceText);
[~, className] = fileparts(targetFile);

% ---- createComponents body
startLine = find(contains(sourceLines, "function createComponents(app)"), 1);
stopLine = find(contains(sourceLines, "% Show the figure after all components are created"), 1);
bodyLines = strtrim(sourceLines(startLine+1:stopLine-1));

blocks = struct('name', {}, 'lines', {});
for lineId = 1:numel(bodyLines)
    currentLine = bodyLines(lineId);
    blockName = regexp(currentLine, '^% Create (\w+)', 'tokens', 'once');
    if ~isempty(blockName)
        blocks(end+1) = struct('name', blockName{1}, 'lines', {strings(0, 1)}); %#ok<AGROW>
    elseif strlength(currentLine) > 0 && ~startsWith(currentLine, "%") && ~isempty(blocks)
        blocks(end).lines(end+1, 1) = currentLine;
    end
end

app = struct();
for blockId = 1:numel(blocks)
    name = blocks(blockId).name;
    templateLines = strings(0, 1);
    for lineId = 1:numel(blocks(blockId).lines)
        codeLine = blocks(blockId).lines(lineId);
        isCallback = contains(codeLine, "createCallbackFcn(");
        if isCallback
            callbackName = regexp(codeLine, '@(\w+)', 'tokens', 'once');
            propertyName = regexp(codeLine, ['^app\.' name '\.(\w+)'], 'tokens', 'once');
            templateLine = sprintf("app.ad_CODENAME_ad.%s = '%s';", propertyName{1}, callbackName{1});
        else
            eval(codeLine);   % builds the component in the struct "app"
            templateLine = regexprep(codeLine, ['app\.' name '(?=[\.\s=])'], 'app.ad_CODENAME_ad');
            if lineId == 1
                templateLine = regexprep(templateLine, '\(app\.\w+', '(app.ad_PARENTCODENAME_ad');
            end
        end
        templateLines(end+1, 1) = templateLine; %#ok<AGROW>
    end
    component = app.(name);
    if ~isprop(component, 'DesignTimeProperties')
        addprop(component, 'DesignTimeProperties');
    end
    designTime = struct('CodeName', name, 'GroupId', '', ...
        'ComponentCode', {cellstr(templateLines)}, 'ImageRelativePath', '');
    if ~isa(component, 'matlab.ui.Figure')
        designTime.DirtyProps = struct();
    end
    component.DesignTimeProperties = designTime;
end
figureHandle = app.(blocks(1).name);
cleanupFigure = onCleanup(@() delete(figureHandle));

% ---- code sections
callbacks = struct('Name', {}, 'Code', {});
startupCallback = [];
callbackNames = regexp(sourceText, 'function (\w+)\(app, \w+\)', 'tokens');
for callbackId = 1:numel(callbackNames)
    functionName = callbackNames{callbackId}{1};
    codeLines = functionBody(sourceLines, functionName);
    if strcmp(functionName, 'startupFcn')
        startupCallback = struct('Name', 'startupFcn', 'Code', {cellstr(codeLines)'});
    else
        callbacks(end+1) = struct('Name', functionName, 'Code', {cellstr(codeLines)'}); %#ok<AGROW>
    end
end

% editable section: the second "properties (Access = public)" block (after the components)
propertyStarts = find(contains(sourceLines, "properties (Access = public)"));
editableStart = propertyStarts(2);
editableStop = editableStart + find(strtrim(sourceLines(editableStart+1:end)) == "end", 1);
editableLines = [sourceLines(editableStart:editableStop); "    "];

inputParameters = regexp(sourceText, 'function startupFcn\(app, (\w+)\)', 'tokens', 'once');

serializer = appdesigner.internal.serialization.MLAPPSerializer(char(targetFile), figureHandle);
serializer.OverwriteTargetFile = true;
serializer.MatlabCodeText = char(strrep(sourceText, newline, sprintf('\n')));
serializer.EditableSectionCode = cellstr(editableLines)';
serializer.Callbacks = callbacks;
serializer.StartupCallback = startupCallback;
serializer.InputParameters = inputParameters{1};
serializer.AppTypeData = struct();
serializer.ClassName = className;
serializer.save();
fprintf('saved %s: %d components, %d callbacks\n', targetFile, numel(blocks), numel(callbacks));
end

function codeLines = functionBody(sourceLines, functionName)
% lines between "function <name>(" and its closing "end", keeping indentation
startLine = find(contains(sourceLines, "function " + functionName + "("), 1);
indent = extractBefore(sourceLines(startLine), "function");
stopLine = startLine + find(sourceLines(startLine+1:end) == indent + "end", 1);
codeLines = sourceLines(startLine+1:stopLine-1);
end
