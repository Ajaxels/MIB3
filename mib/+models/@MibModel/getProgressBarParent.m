function parentFig = getProgressBarParent(obj)
% GETPROGRESSBARPARENT - Parent figure for progress dialogs.
%
% Returns the active image document's floating window when that document is
% **undocked**, otherwise the main MIB window (``obj.mibGUI``). The undocked
% case keeps a long-running operation's progress bar on the same screen the
% user is actually working on, instead of jumping back to the main window.
%
% Used as the parent argument for ``uiprogressdlg`` and ``core.PoolWaitbar``
% in place of ``obj.mibGUI`` / ``obj.mibModel.mibGUI``.
%
% .. code-block:: matlab
%
%     wb = uiprogressdlg(obj.getProgressBarParent(), 'Value', 0, 'Title', 'Eroding...');
%
% Return values:
%   parentFig: handle to the figure to parent progress dialogs to. Always a
%       valid handle; falls back to ``obj.mibGUI`` on any error (batch/headless
%       mode, no open dataset, stale document handles, docked document).

% always-valid default: the main MIB window
parentFig = obj.mibGUI;
try
    doc = obj.mibController.cImageDoc{obj.Sets.selectedSet};
    if isvalid(doc.figureDoc) && ~doc.figureDoc.Docked
        parentFig = doc.figureDoc.Figure;
    end
catch
    % keep the main-GUI fallback
end
end
