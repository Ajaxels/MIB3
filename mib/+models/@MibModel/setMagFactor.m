function setMagFactor(obj, magFactor, id)
% function setMagFactor(obj, magFactor, id)
% set magnification for the currently shown or id dataset
%
% Parameters:
% magFactor: magnification factor
% id: [@b optional], id of the dataset, otherwise the currently shown
% dataset (obj.id)
%
% Return values:
% 

%| 
% @b Examples:
% @code obj.mibModel.setMagFactor(2);     // call from mibController: set current magFactor to 2 @endcode
% @code obj.mibModel.setMagFactor(2, 4);     // call from mibController: set current magFactor to 2 for dataset 4 @endcode

% Updates
% 

if nargin < 3; id = obj.id; end 
if nargin < 2
    errordlg(sprintf('!!! Error !!!\n\nthe magFactor parameter is missing'),'mibModel.setMagFactor');
    return;
end

obj.I{id}.magFactor = magFactor;
end


