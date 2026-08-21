function secondsPerCall = timeCallSamples(fcn, nIterations)
% TIMECALLSAMPLES - time a function handle, returning per-iteration seconds.
%
% One warm-up call is excluded from the timing. Returns a 1xnIterations
% vector of wall-clock seconds measured with tic/toc.
%
% Note that some of the measured accessors are O(1) regardless of dataset size:
% getData3D/getData4D return the stored array whole for the labels255 and
% labels65535 models, so MATLAB hands back a copy-on-write reference and the
% call never touches a pixel. Those land at 7-50 us on any block size, where the
% figure says more about CPU frequency and cache state at that moment than about
% MIB - see the absolute floor in PerfBaselineStore.verifyAgainstBaseline.
%
% Ported from timeCall() in homeDevTest_Callback.m; returns raw samples
% instead of mean ms so PerfBaselineStore can compute both mean and min.

fcn();   % warm-up - JIT, cache warm, excluded from samples
secondsPerCall = zeros(1, nIterations);
for k = 1:nIterations
    tStart = tic;
    fcn();
    secondsPerCall(k) = toc(tStart);
end
end
