function secondsPerCall = timeCallSamples(fcn, nIterations)
% TIMECALLSAMPLES - time a function handle, returning per-iteration seconds.
%
% One warm-up call is excluded from the timing. Returns a 1×nIterations
% vector of wall-clock seconds measured with tic/toc.
%
% Ported from timeCall() in homeDevTest_Callback.m; returns raw samples
% instead of mean ms so PerfBaselineStore can compute both mean and min.

fcn();   % warm-up — JIT, cache warm, excluded from samples
secondsPerCall = zeros(1, nIterations);
for k = 1:nIterations
    tStart = tic;
    fcn();
    secondsPerCall(k) = toc(tStart);
end
end
