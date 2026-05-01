function exportONNXNetwork(Network, filename, varargin)
% EXPORTONNXNETWORK - Export a trained network or layer graph to ONNX model format.
%
% Syntax:
%   .. code-block:: matlab
%
%      exportONNXNetwork(Network, filename)
%      exportONNXNetwork(Network, filename, Name, Value, ...)
%
% Exports ``Network`` with weights to the ONNX file ``filename``.
% If ``filename`` already exists it is overwritten.
%
% Input Arguments:
%   - **Network** — trained network or layer graph specified as a
%     ``SeriesNetwork``, ``DAGNetwork``, ``dlnetwork``, or ``layerGraph``
%   - **filename** — [char|string] output file path
%
% Name-Value Arguments:
%   - ``'NetworkName'`` — [char|string] name stored inside the ONNX file
%     (default: ``'Network'``)
%   - ``'OpsetVersion'`` — [integer] ONNX operator-set version to use;
%     supported values: ``6``, ``7``, ``8``, ``9`` (default: ``8``)
%   - ``'BatchSize'`` — [integer] explicit batch size to export, or ``[]``
%     for variable batch size (default: ``[]``)


% Copyright 2018-2023 The Mathworks, Inc.


%% Check if support package is installed
breadcrumbFile = 'nnet.internal.cnn.supportpackages.isOnnxInstalled';
fullpath = which(breadcrumbFile);

%if isdeployed
   % Function is being called from a compiled app; throw an error    
%   error(message("nnet_cnn:supportpackages:CannotDeployImporterOrExporter", mfilename));
%   msgbox('I am in the deployed part!');
% elseif isempty(fullpath)
if isempty(fullpath)   
   % Not installed; throw an error
   name = 'Deep Learning Toolbox Converter for ONNX Model Format';
   basecode = 'ONNXCONVERTER';
   error(message('nnet_cnn:supportpackages:InstallRequired', ...
       mfilename, name, basecode));
end

% if isempty(fullpath)
%     % Not installed; throw an error
%     name = 'Deep Learning Toolbox Converter for ONNX Model Format';
%     basecode = 'ONNXCONVERTER';
%     error(message('nnet_cnn:supportpackages:InstallRequired', ...
%         mfilename, name, basecode));
% end

% Call the main function
nnet.internal.cnn.onnx.exportONNXNetwork(Network, filename, varargin{:});
end
