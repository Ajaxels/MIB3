function Miji_wrapper(open_imagej)
% MIJI_WRAPPER - Start Fiji/MIJ in both interactive and deployed MIB sessions.
%
% Dispatches to the standard ``Miji`` script when running interactively, or
% to ``utils.fiji.Miji_deploy`` when running as a compiled standalone application.
%
% Requires Fiji to be installed (http://fiji.sc/Fiji).
%
% Syntax:
%   .. code-block:: matlab
%
%      utils.fiji.Miji_wrapper(open_imagej)
%
% Input Arguments:
%   - **open_imagej** — [logical] passed directly to ``Miji`` or
%     ``Miji_deploy``; ``true`` opens the ImageJ window, ``false`` runs headless
%
% Updates
%


if ~isdeployed
    Miji(open_imagej);     % from Matlab, use original Miji script in the Fiji/scripts folder
    %MIJ.start;
else
    utils.fiji.Miji_deploy(open_imagej);  % from deployed im_browser, use modified Miji script (Miji_deploy) in im_browser/Tools/Fiji
end