classdef FakeProgressDialog < handle
% FAKEPROGRESSDIALOG - Minimal stand-in for a cancelable uiprogressdlg.
%
% Lets a headless test drive the cancellation path of a long-running function
% that takes a ``uiprogressdlg`` handle and polls ``CancelRequested``. The
% property is dependent: reading it counts the poll and returns ``true`` once
% ``cancelAfter`` polls have gone by, which is how a test makes the cancel land
% in a chosen phase without a window or a user:
%
%   .. code-block:: matlab
%
%      wb = mibtest.helpers.FakeProgressDialog(20);   % cancel on the 21st poll
%      [labels, stats] = utils.instances.stitch2Dto3D(volume, options, wb);
%      testCase.verifyTrue(stats.cancelled);
%      testCase.verifyEmpty(labels);
%
% Constructed with no argument it never cancels, which is the "dialog present,
% user did nothing" case - useful to assert that passing a progress handle does
% not change the result.
%
% Handle semantics are required: the function under test writes ``Message`` and
% the poll counter has to survive across calls.
%
% See also: mibtest.helpers.FakeWidget, utils.instances.stitch2Dto3D

    properties
        Message = ''
        % phase text written by the function under test
        Title = ''
        % dialog caption
        Indeterminate = 'off'
        % 'on' | 'off'
        Value = 0
        % 0-1 progress fraction
        polls = 0
        % how many times CancelRequested has been read so far
        cancelAfter = inf
        % number of polls to answer 'false' before reporting a cancel
    end

    properties (Dependent)
        CancelRequested
        % true once more than cancelAfter polls have been made
    end

    methods
        function obj = FakeProgressDialog(cancelAfter)
            if nargin > 0 && ~isempty(cancelAfter); obj.cancelAfter = cancelAfter; end
        end

        function tf = get.CancelRequested(obj)
            obj.polls = obj.polls + 1;
            tf = obj.polls > obj.cancelAfter;
        end
    end
end
