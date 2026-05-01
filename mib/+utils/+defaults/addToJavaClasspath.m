function addToJavaClasspath(classpath, directory)
% ADDTOJAVACLASSPATH - Add JAR files from a directory to the MATLAB Java classpath.
%
% Syntax:
%   .. code-block:: matlab
%
%      addToJavaClasspath(classpath, directory)
%
% Scans ``directory`` for ``*.jar`` files and appends any that are not already
% in ``classpath`` using ``javaaddpath``.
%
% Input Arguments:
%   - **classpath** — [cell of char] current Java classpath entries (from ``javaclasspath``)
%   - **directory** — [char] full path to the directory containing JAR files
%
% Usage:
%
%   **Example 1** — add BioFormats JARs during MIB startup
%
%   .. code-block:: matlab
%
%      addToJavaClasspath(javaclasspath, fullfile(mibPath, 'jars'));
%

%

jarList = dir(strcat([directory filesep '*.jar']));
path_= cell(0);
for i = 1:length(jarList)
    if not_yet_in_classpath(classpath, jarList(i).name)
        path_{length(path_) + 1} = strcat([directory filesep jarList(i).name]);
    end
end

% Add them to the classpath
if ~isempty(path_)
    try
        javaaddpath(path_, '-end');
    catch err
        fprintf('%s\n', err.identifier);
    end
end
end

function test = not_yet_in_classpath(classpath, filename)
% NOT_YET_IN_CLASSPATH - Test whether the library was already imported.
%
% Syntax:
%   function test = not_yet_in_classpath(classpath, filename)
%

expression = strcat([filesep filename]);
test = isempty(cell2mat(strfind(classpath, expression)));
end
