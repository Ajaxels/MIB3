function magFactor = getMagFactor(obj, id)
    % GETMAGFACTOR - Get magnification factor for the currently shown or specified dataset.
    %
    % Syntax:
    %   .. code-block:: matlab
    %
    %       magFactor = obj.getMagFactor(id)
    %
    % Input Arguments:
    %   - **id** - *(optional)* ID of the dataset, otherwise uses current dataset (obj.id)
    %
    % Output Arguments:
    %   - **magFactor** - magnification factor
    %
    % Usage:
    %   **Example 1** - get current magFactor and for dataset 2
    %
    %   .. code-block:: matlab
    %
    %      magFactor = obj.mibModel.getMagFactor();
    %      magFactor = obj.mibModel.getMagFactor(2);
    %
    
    if nargin < 2; id = obj.id; end
    
    magFactor = obj.I{id}.magFactor;
end
