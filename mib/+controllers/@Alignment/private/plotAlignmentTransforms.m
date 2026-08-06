function hFig = plotAlignmentTransforms(kind, payload, titleStr)
% PLOTALIGNMENTTRANSFORMS - Plot detected alignment displacements for preview.
%
% Syntax:
%   .. code-block:: matlab
%
%      hFig = plotAlignmentTransforms(kind, payload, titleStr)
%
% Shared preview plot used by the alignment confirmation dialogs
% (:func:`confirmDetectedTransforms`, :func:`previewConfirmLoadedShifts`).
%
% Input Arguments:
%   - **kind** - [char] ``'shifts'`` (translation vectors) or ``'tforms'``
%     (per-slice cumulative transforms).
%   - **payload** - [struct]
%
%     - for ``'shifts'``: fields ``shiftX`` / ``shiftY`` (numeric vectors).
%     - for ``'tforms'``: field ``tforms`` ({Nx1} cell of ``affinetform2d`` /
%       ``affine2d`` / 3x3 matrices).
%
%   - **titleStr** - [char] plot title.
%
% Output Arguments:
%   - **hFig** - handle to the created figure.

hFig = figure('Name', 'Detected alignment displacements', 'NumberTitle', 'off');

switch kind
    case 'shifts'
        sx = double(payload.shiftX(:));
        sy = double(payload.shiftY(:));
        plot(1:numel(sx), sx, '.-', 1:numel(sy), sy, '.-');
        legend('Shift X', 'Shift Y', 'Location', 'best'); grid on;
        xlabel('Frame number'); ylabel('Displacement (pixels)');
        title(titleStr);

    case 'tforms'
        tfs = payload.tforms;
        n = numel(tfs);
        tx = nan(n, 1); ty = nan(n, 1); rot = nan(n, 1);
        for k = 1:n
            A = extractMatrix(tfs{k});
            if ~isempty(A)
                tx(k) = A(1, 3); ty(k) = A(2, 3);
                rot(k) = atan2d(A(2, 1), A(1, 1));
            end
        end
        if all(isnan(tx))
            axis off;
            text(0.5, 0.5, sprintf('%d transforms', n), 'HorizontalAlignment', 'center');
            title(titleStr);
        else
            subplot(2, 1, 1);
            plot(1:n, tx, '.-', 1:n, ty, '.-');
            legend('Tx', 'Ty', 'Location', 'best'); grid on;
            ylabel('Cumulative translation (px)'); title(titleStr);
            subplot(2, 1, 2);
            plot(1:n, rot, '.-'); grid on;
            xlabel('Frame number'); ylabel('Cumulative rotation (deg)');
        end

    otherwise
        axis off;
        text(0.5, 0.5, 'Alignment coefficients', 'HorizontalAlignment', 'center');
        title(titleStr);
end
drawnow;
end

% =============================================================================
function A = extractMatrix(t)
% Best-effort 3x3 matrix from a tform entry (matrix or *tform2d / affine2d object).
A = [];
if isnumeric(t) && isequal(size(t), [3 3])
    A = t;
elseif isobject(t) && isprop(t, 'A')
    A = t.A;
elseif isobject(t) && isprop(t, 'T')
    A = t.T.';   % older affine2d stores the transposed matrix
end
end
