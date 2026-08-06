function connImaris = connectToImaris(connImaris, mibGUI)
% CONNECTTOIMARIS - Connect to Imaris from MATLAB.
%
% Syntax:
%   function connImaris = connectToImaris(connImaris, mibGUI)
%
% Input Arguments:
%   - **connImaris** - *(optional)* a handle to an existing Imaris connection, or [] to create a fresh connection
%   - **mibGUI** - *(optional)* handle to the main MIB window, used for progress and error dialogs
%
% Output Arguments:
%   - **connImaris** - a handle to the Imaris connection, or [] on failure
%

% @note
% Uses IceImarisConnector bindings.
% @b Requires:
% 1. Set system environment variable IMARISPATH to the Imaris installation
%    directory, for example "C:\tools\science\imaris"
% 2. Restart MATLAB

%|
% @b Examples:
% @code obj.mibModel.connImaris = io.imaris.connectToImaris(obj.mibModel.connImaris, obj.mibGUI); @endcode

% Updates
%

if nargin < 2; mibGUI = []; end
if nargin < 1; connImaris = []; end

% link the Imaris Java library on the first use (lazy, skipped at MIB startup)
utils.ensureJavaLibraries({'imaris'});

% show progress dialog
if ~isempty(mibGUI)
    progressDialog = uiprogressdlg(mibGUI, 'Value', 0, ...
        'Message', 'Connecting to Imaris...', ...
        'Title', 'Connecting to Imaris', ...
        'Indeterminate', 'on');
else
    progressDialog = waitbar(0, 'Please wait...', 'Name', 'Connecting to Imaris');
end

if isempty(connImaris)
    try
        connImaris = IceImarisConnector(0);
        if ~isempty(mibGUI); progressDialog.Value = 0.3; else; waitbar(0.3, progressDialog); end
    catch exception
        errorMessage = sprintf('Could not connect to Imaris Server.\nPlease start Imaris and try again!\n\n%s', exception.message);
        if ~isempty(mibGUI)
            utils.dlgs.showErrorDialog(mibGUI, errorMessage, 'Missing Imaris');
        else
            errordlg(errorMessage, 'Missing Imaris');
        end
        delete(progressDialog);
        connImaris = [];
        return;
    end
    if ~isempty(mibGUI); progressDialog.Value = 0.7; else; waitbar(0.7, progressDialog); end
    if connImaris.isAlive == 0
        connImaris.startImaris();
        if ~isempty(mibGUI); progressDialog.Value = 0.95; else; waitbar(0.95, progressDialog); end
    end
else
    imarisLib = ImarisLib;
    server = imarisLib.GetServer();
    if isempty(server)
        errorMessage = 'Could not connect to Imaris Server.\nPlease start Imaris and try again!';
        if ~isempty(mibGUI)
            utils.dlgs.showErrorDialog(mibGUI, errorMessage, 'Missing Imaris');
        else
            errordlg(errorMessage, 'Missing Imaris');
        end
        delete(progressDialog);
        connImaris = [];
        return;
    end
    numberOfObjects = server.GetNumberOfObjects();
    if numberOfObjects == 0
        connImaris.startImaris();
    else
        notAlive = 1;
        objectIndex = 0;
        while notAlive
            objectId = server.GetObjectID(objectIndex);
            connImaris = IceImarisConnector(objectId);
            if connImaris.isAlive
                notAlive = 0;
            end
            objectIndex = objectIndex + 1;
        end
    end
end
delete(progressDialog);
end
