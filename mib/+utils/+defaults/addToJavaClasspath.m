function addToJavaClasspath(classpath, directory)
% function addToJavaClasspath(classpath, directory)
% add java to java class path of MATLAB
%
% Parameters:
%
% Return values:
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
% Test whether the library was already imported

expression = strcat([filesep filename]);
test = isempty(cell2mat(strfind(classpath, expression)));
end