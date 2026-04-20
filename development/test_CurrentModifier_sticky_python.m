% test_CurrentModifier_sticky_python.m
%
% BUG REPORT: UIFigure.CurrentModifier becomes stale (sticky) after a
% blocking pyrun() or pyrunfile() call.
%
% When modifier keys (e.g. Shift) are released DURING a blocking Python
% call, the key-release event is queued but never delivered to MATLAB's
% event loop while the call is blocking.  After pyrun() returns,
% UIFigure.CurrentModifier still reports the previously-pressed modifier
% even though the key is no longer physically held.
%
% The same problem affects UIFigure.SelectionType: a WindowButtonDownFcn
% click that triggered the Python call can leave SelectionType stuck as
% 'extend' (Shift+LMB) on subsequent clicks.
%
% STEPS TO REPRODUCE:
%   1. Run this script.
%   2. Hold the Shift key, then click the "Start Python call" button.
%   3. While the progress bar counts (3-second pyrun sleep), RELEASE Shift.
%   4. After the call returns, observe the result labels.
%
% EXPECTED BEHAVIOUR:
%   "Modifier after pyrun" shows  {} (empty)
%
% ACTUAL BEHAVIOUR (affected versions):
%   "Modifier after pyrun" still shows  {shift}
%   even though Shift was released before pyrun() returned.
%
% WORKAROUND USED IN APPLICATION CODE:
%   Maintain a separate currentModifier property updated by
%   WindowKeyPressFcn / WindowKeyReleaseFcn, and reset it explicitly to {}
%   after every blocking Python call.  Use this property instead of reading
%   UIFigure.CurrentModifier.
%
% CONFIRMED BEHAVIOUR:
%   R2024b — NOT affected (CurrentModifier updates correctly after pyrun)
%   R2026a — AFFECTED

fig = uifigure('Name', 'CurrentModifier sticky bug (pyrun)', ...
    'Position', [200 200 480 320]);

% ---- labels ----
uilabel(fig, 'Text', 'Steps:', ...
    'FontWeight', 'bold', 'Position', [20 280 440 22]);
uilabel(fig, 'Text', '1. Hold Shift, click the button below.', ...
    'Position', [20 258 440 20]);
uilabel(fig, 'Text', '2. Release Shift WHILE the 3-second Python call runs.', ...
    'Position', [20 238 440 20]);
uilabel(fig, 'Text', '3. After it returns, check the results.', ...
    'Position', [20 218 440 20]);

uibutton(fig, 'push', ...
    'Text', 'Start Python call  (hold Shift first!)', ...
    'Position', [20 170 440 36], ...
    'ButtonPushedFcn', @(~,~) runTest(fig));

lblBefore = uilabel(fig, 'Text', 'Modifier at button press:  —', ...
    'Position', [20 130 440 22], 'Tag', 'lblBefore');
lblAfter  = uilabel(fig, 'Text', 'Modifier after pyrun:  —', ...
    'Position', [20 105 440 22], 'Tag', 'lblAfter');
lblResult = uilabel(fig, 'Text', '', ...
    'Position', [20 70 440 28], 'FontWeight', 'bold', 'Tag', 'lblResult');

uilabel(fig, 'Text', sprintf('MATLAB %s', version), ...
    'FontColor', [0.5 0.5 0.5], 'Position', [20 20 440 18]);

% ---- test callback ----
function runTest(fig)
    lblBefore = findobj(fig, 'Tag', 'lblBefore');
    lblAfter  = findobj(fig, 'Tag', 'lblAfter');
    lblResult = findobj(fig, 'Tag', 'lblResult');

    modBefore = fig.CurrentModifier;
    if isempty(modBefore)
        lblBefore.Text = 'Modifier at button press:  {} (empty — did you hold Shift?)';
        lblBefore.FontColor = [0.6 0.4 0];
    else
        lblBefore.Text = sprintf('Modifier at button press:  {%s}  ✓', strjoin(modBefore, ', '));
        lblBefore.FontColor = [0 0.45 0];
    end
    lblAfter.Text  = 'Modifier after pyrun:  running…';
    lblResult.Text = '';
    drawnow;

    % Blocking Python call — release Shift during this 3-second window
    try
        pyrun('import time; time.sleep(3)');
    catch err
        lblAfter.Text  = sprintf('pyrun failed: %s', err.message);
        lblAfter.FontColor = [0.6 0 0];
        lblResult.Text = 'Python not available — cannot reproduce.';
        lblResult.FontColor = [0.4 0.4 0.4];
        return;
    end
    
    % this pause is required to clear the sticky key modifier state
    pause(0.1);
    
    modAfter = fig.CurrentModifier;
    if isempty(modAfter)
        lblAfter.Text  = 'Modifier after pyrun:  {} (empty)';
        lblAfter.FontColor = [0 0.45 0];
        lblResult.Text = 'PASS — CurrentModifier updated correctly.';
        lblResult.FontColor = [0 0.45 0];
    else
        lblAfter.Text  = sprintf('Modifier after pyrun:  {%s}  ← still set!', ...
            strjoin(modAfter, ', '));
        lblAfter.FontColor = [0.75 0 0];
        lblResult.Text = 'BUG — CurrentModifier is stale after pyrun.';
        lblResult.FontColor = [0.75 0 0];
    end
end
