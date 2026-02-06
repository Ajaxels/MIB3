function magFactor = getMagFactor(obj, id)
    % function magFactor = getMagFactor(obj, id)
    % Get magnification factor for the currently shown or specified dataset
    %
    % Parameters:
    % id: [@b optional] ID of the dataset, otherwise uses current dataset (obj.id)
    %
    % Return values:
    % magFactor: magnification factor
    %
    % Examples:
    % @code 
    % magFactor = obj.mibModel.getMagFactor();      % get current magFactor
    % magFactor = obj.mibModel.getMagFactor(2);     % get magFactor for dataset 2 
    % @endcode
    
    if nargin < 2
        id = obj.id;
    end
    
    magFactor = obj.I{id}.magFactor;
end