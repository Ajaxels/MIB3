function Miji_deploy(open_imagej)
% MIJI_DEPLOY - Modified Miji launcher for the deployed (compiled) version of MIB.
%
% Identical to the standard ``Miji.m`` except that ``javaaddpath`` calls
% are omitted (the Java classpath is pre-configured at compile time).
%
% Requires Fiji to be installed (http://fiji.sc/Fiji) and a
% ``mib_java_path.txt`` file in the MIB installation directory.
%
% Based on ``Miji.m`` by Jacques Pecreaux, Johannes Schindelin, and
% Jean-Yves Tinevez \<jeanyves.tinevez at gmail.com\>.
%
% Syntax:
%   .. code-block:: matlab
%
%      utils.fiji.Miji_deploy()
%      utils.fiji.Miji_deploy(open_imagej)
%
% Input Arguments:
%   - **open_imagej** *(optional)* — [logical] when ``true`` (default), opens
%     the ImageJ window via ``MIJ.start``; when ``false``, initialises
%     ImageJ in headless mode (``NO_SHOW`` flag)
%
% Updates
%

%
% This script sets up the classpath to Fiji and optionally starts MIJ
% Author: Jacques Pecreaux, Johannes Schindelin, Jean-Yves Tinevez

if nargin < 1
    open_imagej = true;
end

%% Maybe open the ImageJ window
if open_imagej
    %cd ..;
    fprintf('\n\nUse MIJ.exit to end the session\n\n');
    MIJ.start();
else
    % initialize ImageJ with the NO_SHOW flag (== 2)
    ij.ImageJ([], 2);
end

% Make sure that the scripts are found.
% Unfortunately, this causes a nasty bug with MATLAB: calling this
% static method modifies the static MATLAB java path, which is
% normally forbidden. The consequences of that are nasty: adding a
% class to the dynamic class path can be refused, because it would be
% falsy recorded in the static path. On top of that, the static
% path is fsck in a weird way, with file separator from Unix, causing a
% mess on Windows platform.
% So we give it up as now.
% %    fiji.User_Plugins.installScripts();

end
